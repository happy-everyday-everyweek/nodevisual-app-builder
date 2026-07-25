import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/control_edge.dart';
import '../../data/models/entry.dart';
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

  // ---- 触发器（entry）----
  //
  // 触发器声明函数"如何被触发"。timer / external 两类触发器与具体 UI
  // 组件 / 页面无关，因此由函数编辑器内编辑（每个函数声明自己的 entry）。
  // uiEvent / pageEvent 仍由 UI 编辑器编辑（与组件 / 页面绑定）。

  /// 为当前函数设置定时器触发器；[intervalMs] 为触发间隔（毫秒）。
  void setTimerEntry(int intervalMs) {
    final fn = _currentFunction;
    if (fn == null) return;
    _commit(fn.copyWith(
      entry: FunctionEntry(kind: EntryKind.timer, ref: '$intervalMs'),
    ));
  }

  /// 为当前函数设置外部触发器；[ref] 为外部事件标识
  ///（如深链路径 `/page/detail` 或推送事件名）。
  void setExternalEntry(String ref) {
    final fn = _currentFunction;
    if (fn == null) return;
    _commit(fn.copyWith(
      entry: FunctionEntry(kind: EntryKind.external, ref: ref),
    ));
  }

  /// 清除当前函数的触发器（entry 置空，函数仅能被显式调用）。
  void clearEntry() {
    final fn = _currentFunction;
    if (fn == null) return;
    _commit(fn.copyWith(entry: null));
  }

  // ---- 节点 ----

  /// 添加节点；返回新节点 id。
  ///
  /// [position] 为画布坐标；不提供时默认 (0, 0)，由调用方在画布中心放置。
  String addNode(String kind, {NodePosition? position}) {
    final fn = _currentFunction;
    if (fn == null) return '';
    // 子母节点：插入 if 条件节点时自动生成母节点 + 2 个子节点（分支出口）。
    if (kind == 'if') {
      return addIfWithBranches(position: position);
    }
    final node = _createDefaultNode(kind)
        .copyWith(position: position ?? const NodePosition(x: 0, y: 0));
    _commit(fn.copyWith(nodes: [...fn.nodes, node]));
    return node.id;
  }

  /// 插入 if 条件节点（母节点）+ 2 个 if_branch 子节点（分支出口）。
  ///
  /// 子母节点设计：用户插入条件节点时，自动生成：
  /// - 1 个母节点（if，含 condition + cases=['true','false']）
  /// - 2 个子节点（if_branch，分别对应 'true' / 'false' 分支）
  ///
  /// 子节点 positioned 在母节点下方左右展开。返回母节点 id。
  String addIfWithBranches({NodePosition? position}) {
    final fn = _currentFunction;
    if (fn == null) return '';
    final pos = position ?? const NodePosition(x: 0, y: 0);
    final parentNode = _createDefaultNode('if').copyWith(position: pos);
    final cases = _ifCasesOf(parentNode);
    final children = <Node>[];
    final newEdges = <ControlEdge>[];
    for (var i = 0; i < cases.length; i++) {
      final childPos = _branchPosition(pos, i, cases.length);
      final child = _createDefaultNode('if_branch').copyWith(
        position: childPos,
        params: {
          'parentId': parentNode.id,
          'caseName': cases[i],
          'name': '分支: ${cases[i]}',
        },
      );
      children.add(child);
      // 自动连线：母节点的 case 输出 → 子分支节点入口。
      newEdges.add(ControlEdge(
        fromNode: parentNode.id,
        fromPort: cases[i],
        toNode: child.id,
      ));
    }
    _commit(fn.copyWith(
      nodes: [...fn.nodes, parentNode, ...children],
      controlEdges: [...fn.controlEdges, ...newEdges],
    ));
    return parentNode.id;
  }

  /// 同步 if 母节点的分支子节点：按当前 cases 增删 if_branch 子节点。
  ///
  /// 当用户在节点编辑页修改 if 的 cases 后调用：
  /// - 新增的 case → 创建对应 if_branch 子节点（positioned 在母节点下方）
  /// - 删除的 case → 移除对应 if_branch 子节点及其关联边
  /// - 已存在的 case → 保留（不重置用户已建立的连线）
  void syncIfBranches(String ifNodeId) {
    final fn = _currentFunction;
    if (fn == null) return;
    Node? parentNode;
    for (final n in fn.nodes) {
      if (n.id == ifNodeId && n.kind == 'if') {
        parentNode = n;
        break;
      }
    }
    if (parentNode == null) return;
    final desiredCases = _ifCasesOf(parentNode);
    // 现有子节点：parentId == ifNodeId 的 if_branch 节点。
    final existingChildren = fn.nodes
        .where((n) =>
            n.kind == 'if_branch' && n.params['parentId'] == ifNodeId)
        .toList(growable: false);
    final existingCaseNames = existingChildren
        .map((n) => n.params['caseName']?.toString() ?? '')
        .toList(growable: false);

    final toAdd = <String>[];
    for (final c in desiredCases) {
      if (!existingCaseNames.contains(c)) toAdd.add(c);
    }
    final toRemove = <String>{};
    for (final i = 0; i < existingChildren.length; i++) {
      final name = existingCaseNames[i];
      if (!desiredCases.contains(name)) {
        toRemove.add(existingChildren[i].id);
      }
    }
    if (toAdd.isEmpty && toRemove.isEmpty) return;

    final newNodes = <Node>[];
    for (final n in fn.nodes) {
      if (toRemove.contains(n.id)) continue;
      newNodes.add(n);
    }
    final newBranchNodes = <Node>[];
    final newEdges = <ControlEdge>[];
    for (final c in toAdd) {
      final idx = desiredCases.indexOf(c);
      final childPos = _branchPosition(parentNode.position, idx, desiredCases.length);
      final child = _createDefaultNode('if_branch').copyWith(
        position: childPos,
        params: {
          'parentId': ifNodeId,
          'caseName': c,
          'name': '分支: $c',
        },
      );
      newBranchNodes.add(child);
      // 自动连线：母节点的 case 输出 → 新子分支节点入口。
      newEdges.add(ControlEdge(
        fromNode: ifNodeId,
        fromPort: c,
        toNode: child.id,
      ));
    }
    final allNodes = [...newNodes, ...newBranchNodes];
    // 保留未被删除的边，并追加新增的边（同时去重：若该 fromPort 已有边则替换）。
    final existingEdges = fn.controlEdges
        .where((e) =>
            !toRemove.contains(e.fromNode) && !toRemove.contains(e.toNode))
        .toList(growable: false);
    final newFromPorts = newEdges.map((e) => '${e.fromNode}:${e.fromPort}').toSet();
    final filteredExisting = existingEdges
        .where((e) => !newFromPorts.contains('${e.fromNode}:${e.fromPort}'))
        .toList(growable: false);
    _commit(fn.copyWith(
      nodes: allNodes,
      controlEdges: [...filteredExisting, ...newEdges],
    ));
  }

  /// 读取 if 节点当前的 cases 列表（含 default）。
  List<String> _ifCasesOf(Node ifNode) {
    final rawCases = ifNode.params['cases'];
    List<String> cases;
    if (rawCases is List) {
      cases = rawCases.map((e) => e.toString()).toList(growable: false);
    } else {
      cases = const ['true', 'false'];
    }
    if (cases.isEmpty) cases = const ['true'];
    if (ifNode.params['includeDefault'] == true) {
      cases = [...cases, 'default'];
    }
    return cases;
  }

  /// 计算第 [index] 个分支子节点相对母节点的画布位置。
  ///
  /// 子节点在母节点下方水平展开：偶数个时左右对称，奇数个时从左到右排列。
  NodePosition _branchPosition(NodePosition parent, int index, int total) {
    const branchOffsetY = 140.0; // 母节点下方间距
    const branchSpacingX = 200.0; // 子节点水平间距
    final startX = parent.x - ((total - 1) * branchSpacingX) / 2;
    return NodePosition(
      x: startX + index * branchSpacingX,
      y: parent.y + branchOffsetY,
    );
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
