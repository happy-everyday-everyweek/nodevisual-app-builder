import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/control_edge.dart';
import '../../data/models/entry.dart';
import '../../data/models/func_param.dart';
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

  /// 自增当前函数的版本号（每次退出编辑器自动保存时调用）。
  ///
  /// 用户每完成一次编辑会话（退出函数编辑器），版本号 +1，用于追踪
  /// 函数的编辑次数。版本号从 1 开始，新建函数不经此方法时保持 1。
  void bumpVersion() {
    final fn = _currentFunction;
    if (fn == null) return;
    _commit(fn.copyWith(version: fn.version + 1));
  }

  // ---- 节点 ----

  /// 添加节点；返回新节点 id。
  ///
  /// [position] 为画布坐标；不提供时默认 (0, 0)，由调用方在画布中心放置。
  ///
  /// 子母节点设计：当插入的节点有 2 个或以上控制流输出时，自动走
  /// [addWithBranches] 生成母节点 + 各输出端口对应的 branch 子节点。
  String addNode(String kind, {NodePosition? position}) {
    final fn = _currentFunction;
    if (fn == null) return '';
    // 子母节点：controlOutputs >= 2 的节点自动生成母节点 + 子节点。
    if (_needsBranches(kind)) {
      return addWithBranches(kind, position: position);
    }
    final node = _createDefaultNode(kind)
        .copyWith(position: position ?? const NodePosition(x: 0, y: 0));
    _commit(fn.copyWith(nodes: [...fn.nodes, node]));
    return node.id;
  }

  /// 判断 kind 是否需要子母节点设计（controlOutputs >= 2）。
  ///
  /// 通过查询 [NodeKindRegistry] 的 spec，解析默认 outputs 判断。
  /// branch 子节点本身只有 1 个输出，不触发递归。入参/出参节点也不触发。
  bool _needsBranches(String kind) {
    if (kind == 'branch' || kind == 'function_input' ||
        kind == 'function_output' || kind == 'return') {
      return false;
    }
    final spec = NodeKindRegistry.getSpec(kind);
    if (spec == null) return false;
    // 动态输出节点（如 if）：用默认 params 解析输出端口数。
    final params = <String, dynamic>{
      for (final p in spec.paramSchema) p.name: p.defaultValue,
    };
    final outputs = resolveOutputsInProject(spec, params, const []);
    return outputs.controlOutputs.length >= 2;
  }

  /// 插入母节点 + 各控制流输出端口对应的 branch 子节点（子母节点设计）。
  ///
  /// 通用版本：服务于 if / loop 等所有 controlOutputs >= 2 的母节点。
  /// - 创建 1 个母节点（按 [kind] 默认规格）
  /// - 为母节点的每个控制流输出端口创建 1 个 branch 子节点
  /// - 自动连线：母节点端口 → 对应 branch 子节点入口
  ///
  /// 子节点 positioned 在母节点下方水平展开。返回母节点 id。
  String addWithBranches(String kind, {NodePosition? position}) {
    final fn = _currentFunction;
    if (fn == null) return '';
    final pos = position ?? const NodePosition(x: 0, y: 0);
    final parentNode = _createDefaultNode(kind).copyWith(position: pos);
    final ports = _controlPortNamesOf(parentNode);
    final children = <Node>[];
    final newEdges = <ControlEdge>[];
    for (var i = 0; i < ports.length; i++) {
      final portName = ports[i];
      final childPos = _branchPosition(pos, i, ports.length);
      final child = _createDefaultNode('branch').copyWith(
        position: childPos,
        params: {
          'parentId': parentNode.id,
          'portName': portName,
          'name': '分支: $portName',
        },
      );
      children.add(child);
      // 自动连线：母节点的端口输出 → branch 子节点入口。
      newEdges.add(ControlEdge(
        fromNode: parentNode.id,
        fromPort: portName,
        toNode: child.id,
      ));
    }
    _commit(fn.copyWith(
      nodes: [...fn.nodes, parentNode, ...children],
      controlEdges: [...fn.controlEdges, ...newEdges],
    ));
    return parentNode.id;
  }

  /// 同步母节点的分支子节点：按当前控制流输出端口增删 branch 子节点。
  ///
  /// 通用版本：当母节点的 controlOutputs 动态变化时（如 if 的 cases 变更）调用：
  /// - 新增的端口 → 创建对应 branch 子节点（positioned 在母节点下方）
  /// - 删除的端口 → 移除对应 branch 子节点及其关联边
  /// - 已存在的端口 → 保留（不重置用户已建立的连线）
  ///
  /// 静态输出节点（如 loop 的 body/completed）输出不变，调用本方法为幂等无操作。
  void syncBranches(String parentNodeId) {
    final fn = _currentFunction;
    if (fn == null) return;
    Node? parentNode;
    for (final n in fn.nodes) {
      if (n.id == parentNodeId && n.kind != 'branch') {
        parentNode = n;
        break;
      }
    }
    if (parentNode == null) return;
    final desiredPorts = _controlPortNamesOf(parentNode);
    // 现有子节点：parentId == parentNodeId 的 branch 节点。
    final existingChildren = fn.nodes
        .where((n) =>
            n.kind == 'branch' && n.params['parentId'] == parentNodeId)
        .toList(growable: false);
    final existingPortNames = existingChildren
        .map((n) => n.params['portName']?.toString() ?? '')
        .toList(growable: false);

    final toAdd = <String>[];
    for (final p in desiredPorts) {
      if (!existingPortNames.contains(p)) toAdd.add(p);
    }
    final toRemove = <String>{};
    for (var i = 0; i < existingChildren.length; i++) {
      final name = existingPortNames[i];
      if (!desiredPorts.contains(name)) {
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
    for (final p in toAdd) {
      final idx = desiredPorts.indexOf(p);
      final childPos = _branchPosition(parentNode.position, idx, desiredPorts.length);
      final child = _createDefaultNode('branch').copyWith(
        position: childPos,
        params: {
          'parentId': parentNodeId,
          'portName': p,
          'name': '分支: $p',
        },
      );
      newBranchNodes.add(child);
      // 自动连线：母节点的端口输出 → 新 branch 子节点入口。
      newEdges.add(ControlEdge(
        fromNode: parentNodeId,
        fromPort: p,
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

  /// 读取节点当前的控制流输出端口名列表。
  ///
  /// 优先用节点实例的 [Node.controlOutputs]（已解析），兜底用 spec 默认输出。
  List<String> _controlPortNamesOf(Node node) {
    if (node.controlOutputs.isNotEmpty) {
      return node.controlOutputs.map((c) => c.name).toList(growable: false);
    }
    // 兜底：从 spec 解析（适用于刚创建、controlOutputs 未填充的情况）。
    final spec = NodeKindRegistry.getSpec(node.kind);
    if (spec == null) return const ['next'];
    final outputs = resolveOutputsInProject(spec, node.params, const []);
    final names = outputs.controlOutputs.map((c) => c.name).toList(growable: false);
    return names.isEmpty ? const ['next'] : names;
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

  /// 同步函数签名（入参/出参节点编辑签名时调用）。
  ///
  /// 入参/出参节点取代侧边栏签名编辑：
  /// - [isInputs] 为 true：[params] 替换 [FunctionDef.inputs]，
  ///   同时把对应 function_input 节点的 dataOutputs 更新为 [params] 派生的 DataOutput。
  /// - [isInputs] 为 false：[params] 替换 [FunctionDef.outputs]，
  ///   function_output 节点无需更新 outputs（终止节点无数据输出）。
  ///
  /// 同时刷新依赖此函数签名的 function_call 节点端口由调用方在进入编辑页时
  /// 按 [NodeKindSpec.projectOutputs] 重新派生，此处不处理。
  void syncFunctionSignature(
    String ioNodeId,
    bool isInputs,
    List<FuncParam> params,
  ) {
    final fn = _currentFunction;
    if (fn == null) return;
    // 找到对应 IO 节点（仅更新同 id 节点的 dataOutputs）。
    final newNodes = fn.nodes.map((n) {
      if (n.id != ioNodeId) return n;
      if (isInputs && n.kind == 'function_input') {
        return n.copyWith(
          dataOutputs: dataOutputsFromParams(params),
        );
      }
      return n;
    }).toList(growable: false);
    _commit(fn.copyWith(
      inputs: isInputs ? params : fn.inputs,
      outputs: isInputs ? fn.outputs : params,
      nodes: newNodes,
    ));
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
