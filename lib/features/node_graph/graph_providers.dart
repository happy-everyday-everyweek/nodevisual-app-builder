import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/control_edge.dart';
import '../../data/models/function_def.dart';
import '../../data/models/node.dart';
import '../../data/models/port.dart';
import '../functions/function_providers.dart';
import '../plugins/plugin_registry.dart';
import '../project/project_providers.dart';
import 'dag_validator.dart';
import 'node_kinds.dart';

const Uuid _uuid = Uuid();

/// 当前在节点图编辑器中打开的函数 id（null 表示未打开）。
///
/// 由 [FunctionEditorScreen] 进入时设置、退出时清空。
/// [GraphMutator] watch 本 provider 以镜像当前编辑的 [FunctionDef]。
final editedFunctionIdProvider = StateProvider<String?>((ref) => null);

/// 当前选中的节点 id（仅画布层 UI 状态，不持久化）。
final selectedNodeIdProvider = StateProvider<String?>((ref) => null);

/// 节点图变更器：管理当前编辑函数的 nodes + controlEdges。
///
/// state 始终镜像 [projectMutatorProvider] 中对应 [editedFunctionIdProvider]
/// 的 [FunctionDef]（在 [build] 中 watch）。所有变更方法把新 [FunctionDef]
/// 快照通过 [ProjectMutator.replaceFunction] 写回项目并持久化。
///
/// 变更方法读取最新函数时使用 [_currentFunction]（直接从
/// [currentProjectProvider] 取值），避免连续多次调用之间 state 尚未
/// rebuild 导致读到陈旧快照。
class GraphMutator extends Notifier<FunctionDef?> {
  @override
  FunctionDef? build() {
    final fid = ref.watch(editedFunctionIdProvider);
    if (fid == null) return null;
    final project = ref.watch(projectMutatorProvider);
    if (project == null) return null;
    return findFunction(project, fid);
  }

  FunctionDef? get _currentFunction {
    final fid = ref.read(editedFunctionIdProvider);
    if (fid == null) return null;
    final project = ref.read(currentProjectProvider);
    if (project == null) return null;
    return findFunction(project, fid);
  }

  void _commit(FunctionDef fn) {
    ref.read(projectMutatorProvider.notifier).replaceFunction(fn);
  }

  /// 公开提交入口（供签名编辑面板等外部 UI 直接更新函数元数据）。
  ///
  /// 调用方传入新的 [FunctionDef]（通常为 `_currentFunction.copyWith(...)`），
  /// 本方法直接写回项目并持久化，然后 GraphMutator 会通过 watch 自动镜像。
  void replaceFunction(FunctionDef fn) => _commit(fn);

  // ---- 节点 ----

  /// 添加节点；返回新节点 id。
  ///
  /// [position] 为画布坐标；不提供时默认 (0, 0)，由调用方在画布中心放置。
  String addNode(String kind, {NodePosition? position}) {
    final fn = _currentFunction;
    if (fn == null) return '';
    final node = _createDefaultNode(kind)
        .copyWith(position: position ?? const NodePosition(x: 0, y: 0));
    _commit(fn.copyWith(nodes: [...fn.nodes, node]));
    return node.id;
  }

  /// 移动节点到指定画布坐标。
  void moveNode(String id, NodePosition position) {
    final fn = _currentFunction;
    if (fn == null) return;
    final newNodes = fn.nodes
        .map((n) => n.id == id ? n.copyWith(position: position) : n)
        .toList(growable: false);
    _commit(fn.copyWith(nodes: newNodes));
  }

  /// 删除节点；同时删除其关联的所有控制流边，并清除其选中态。
  void removeNode(String id) {
    final fn = _currentFunction;
    if (fn == null) return;
    final newNodes =
        fn.nodes.where((n) => n.id != id).toList(growable: false);
    final newEdges = fn.controlEdges
        .where((e) => e.fromNode != id && e.toNode != id)
        .toList(growable: false);
    _commit(fn.copyWith(nodes: newNodes, controlEdges: newEdges));
    if (ref.read(selectedNodeIdProvider) == id) {
      ref.read(selectedNodeIdProvider.notifier).state = null;
    }
  }

  /// 更新节点参数（整体替换 params）。
  void updateNodeParams(String id, Map<String, dynamic> params) {
    final fn = _currentFunction;
    if (fn == null) return;
    final newNodes = fn.nodes
        .map((n) => n.id == id ? n.copyWith(params: params) : n)
        .toList(growable: false);
    _commit(fn.copyWith(nodes: newNodes));
  }

  /// 设置节点的命名控制流输出列表。
  void setNodeControlOutputs(String id, List<ControlOutput> outputs) {
    final fn = _currentFunction;
    if (fn == null) return;
    final newNodes = fn.nodes
        .map((n) =>
            n.id == id ? n.copyWith(controlOutputs: outputs) : n,)
        .toList(growable: false);
    _commit(fn.copyWith(nodes: newNodes));
  }

  /// 设置节点的命名数据输出列表。
  void setNodeDataOutputs(String id, List<DataOutput> outputs) {
    final fn = _currentFunction;
    if (fn == null) return;
    final newNodes = fn.nodes
        .map((n) => n.id == id ? n.copyWith(dataOutputs: outputs) : n)
        .toList(growable: false);
    _commit(fn.copyWith(nodes: newNodes));
  }

  /// 一次性更新节点的 params / controlOutputs / dataOutputs（单次提交）。
  ///
  /// 节点编辑页在修改参数（可能同时引发动态 outputs 变化）时使用，
  /// 避免多次分别提交导致的中间态与多余持久化。任一字段为 null 表示保持原值。
  void updateNode(
    String id, {
    Map<String, dynamic>? params,
    List<ControlOutput>? controlOutputs,
    List<DataOutput>? dataOutputs,
  }) {
    final fn = _currentFunction;
    if (fn == null) return;
    final newNodes = fn.nodes
        .map((n) => n.id == id
            ? n.copyWith(
                params: params ?? n.params,
                controlOutputs: controlOutputs ?? n.controlOutputs,
                dataOutputs: dataOutputs ?? n.dataOutputs,
              )
            : n,)
        .toList(growable: false);
    _commit(fn.copyWith(nodes: newNodes));
  }

  // ---- 控制流边 ----

  /// 添加控制流边。
  ///
  /// 返回值：
  /// - `AddEdgeResult.success`：成功（含单入替换场景）；
  /// - `AddEdgeResult.cycle`：会形成环，已拒绝；
  /// - `AddEdgeResult.invalid`：节点或端口不存在。
  ///
  /// v1 限制：一个节点的入口只能接一条边。若 [toNode] 已有入边，
  /// 旧边被替换。同一 (fromNode, fromPort) 也只能引出一条边，
  /// 重复时替换旧边（避免一个分支扇出到多个目标）。
  AddEdgeResult addEdge({
    required String fromNode,
    required String fromPort,
    required String toNode,
  }) {
    final fn = _currentFunction;
    if (fn == null) return AddEdgeResult.invalid;

    final fromExists = fn.nodes.any((n) => n.id == fromNode);
    final toExists = fn.nodes.any((n) => n.id == toNode);
    if (!fromExists || !toExists) return AddEdgeResult.invalid;

    final fromPortExists = fn.nodes
        .firstWhere((n) => n.id == fromNode)
        .controlOutputs
        .any((o) => o.name == fromPort);
    if (!fromPortExists) return AddEdgeResult.invalid;

    final newEdge = ControlEdge(
      fromNode: fromNode,
      fromPort: fromPort,
      toNode: toNode,
    );

    // 单入限制：移除 toNode 现有入边（替换）。
    // 单出限制：移除 (fromNode, fromPort) 现有出边（替换）。
    final filteredEdges = fn.controlEdges.where((e) {
      if (e.toNode == toNode) return false; // 替换目标入边
      if (e.fromNode == fromNode && e.fromPort == fromPort) {
        return false; // 替换源端口出边
      }
      return true;
    }).toList();

    // 环检测：在过滤后的边集上预检。
    if (DagValidator.wouldCreateCycle(filteredEdges, newEdge)) {
      return AddEdgeResult.cycle;
    }

    _commit(fn.copyWith(
      controlEdges: [...filteredEdges, newEdge],
    ),);
    return AddEdgeResult.success;
  }

  /// 删除指定的控制流边。
  void removeEdge({
    required String fromNode,
    required String fromPort,
    required String toNode,
  }) {
    final fn = _currentFunction;
    if (fn == null) return;
    final newEdges = fn.controlEdges
        .where((e) =>
            !(e.fromNode == fromNode &&
                e.fromPort == fromPort &&
                e.toNode == toNode),)
        .toList(growable: false);
    _commit(fn.copyWith(controlEdges: newEdges));
  }

  // ---- 默认节点工厂 ----

  /// 按 kind 生成默认节点（含默认 params、controlOutputs、dataOutputs）。
  ///
  /// 优先委托 [NodeKindRegistry] / [createNodeForKind]（基础节点 + 内置
  /// plugin_openai/plugin_anthropic 等）；db_* 与市场安装的 plugin_<id>
  /// 不在 NodeKindRegistry 中，保留本地默认（市场插件走 PluginRegistry）。
  /// position 由调用方覆盖；id 已生成。
  Node _createDefaultNode(String kind) {
    if (NodeKindRegistry.isRegistered(kind)) {
      return createNodeForKind(kind);
    }
    final id = _uuid.v4();
    // 市场插件节点（kind = plugin_<id>）：从 PluginRegistry 获取规格创建。
    if (kind.startsWith('plugin_')) {
      final pluginId = kind.substring(7);
      final registry = ref.read(pluginRegistryProvider);
      final entry = registry.get(pluginId);
      if (entry != null) {
        final spec = entry.spec;
        return Node(
          id: id,
          kind: kind,
          params: {
            'pluginId': pluginId,
            'name': spec.displayName,
          },
          position: const NodePosition(x: 0, y: 0),
          controlOutputs: const [ControlOutput(name: 'next')],
          dataOutputs: spec.outputs
              .map((o) => DataOutput(name: o.name, type: o.type))
              .toList(),
        );
      }
      // 插件未注册，降级为通用 plugin 节点。
      return Node(
        id: id,
        kind: kind,
        params: {'pluginId': pluginId, 'name': kind},
        position: const NodePosition(x: 0, y: 0),
        controlOutputs: const [ControlOutput(name: 'next')],
        dataOutputs: const [DataOutput(name: 'result', type: PortType.any)],
      );
    }
    switch (kind) {
      case 'db_query':
        return Node(
          id: id,
          kind: kind,
          params: const {'table': '', 'filter': null},
          position: const NodePosition(x: 0, y: 0),
          controlOutputs: const [ControlOutput(name: 'next')],
          dataOutputs: const [
            DataOutput(name: 'rows', type: PortType.list),
            DataOutput(name: 'count', type: PortType.number),
          ],
        );
      case 'db_insert':
      case 'db_update':
      case 'db_delete':
        return Node(
          id: id,
          kind: kind,
          params: const {'table': '', 'data': null},
          position: const NodePosition(x: 0, y: 0),
          controlOutputs: const [ControlOutput(name: 'next')],
          dataOutputs: const [
            DataOutput(name: 'affected', type: PortType.number),
          ],
        );
      default:
        return Node(
          id: id,
          kind: kind,
          params: const {},
          position: const NodePosition(x: 0, y: 0),
          controlOutputs: const [ControlOutput(name: 'next')],
        );
    }
  }
}

/// [GraphMutator.addEdge] 的结果。
enum AddEdgeResult {
  /// 成功（含单入 / 单出替换场景）。
  success,

  /// 会形成环，已拒绝。
  cycle,

  /// 节点或端口不存在。
  invalid,
}

/// 节点图变更器 provider。
final graphMutatorProvider =
    NotifierProvider<GraphMutator, FunctionDef?>(GraphMutator.new);
