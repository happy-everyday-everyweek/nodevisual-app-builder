import '../../data/models/function_def.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/project_variable.dart';
import '../../data/models/variable_ref.dart';
import '../node_graph/node_kinds.dart';

/// 控制流上游节点的一个可引用命名数据输出。
///
/// 由 [ScopeResolver.resolveUpstreamOutputs] 产出，描述"沿控制流反向
/// 闭包可达的某节点的某个 dataOutput"，供变量选择卡片展示与建立
/// [VariableRef.upstream] 引用。
class UpstreamOutput {
  /// 输出所属节点 id。
  final String nodeId;

  /// 节点 kind（如 'arithmetic' / 'variable_get'）。
  final String nodeKind;

  /// 节点展示名（取自 [NodeKindRegistry]，未注册时回退为 [nodeKind]）。
  final String nodeLabel;

  /// 命名数据输出名。
  final String outputName;

  /// 输出值类型。
  final PortType type;

  const UpstreamOutput({
    required this.nodeId,
    required this.nodeKind,
    required this.nodeLabel,
    required this.outputName,
    required this.type,
  });

  /// 建立 [VariableRef.upstream] 引用。
  VariableRef toRef() =>
      VariableRef.upstream(nodeId: nodeId, outputName: outputName);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpstreamOutput &&
          nodeId == other.nodeId &&
          nodeKind == other.nodeKind &&
          nodeLabel == other.nodeLabel &&
          outputName == other.outputName &&
          type == other.type;

  @override
  int get hashCode => Object.hash(nodeId, nodeKind, nodeLabel, outputName, type);

  @override
  String toString() => 'UpstreamOutput($nodeLabel.$outputName: $type)';
}

/// `#` 作用域三来源的可用变量集合。
///
/// - [upstream]：控制流上游节点输出（[UpstreamOutput]）。
/// - [funcVars]：函数变量（[FunctionVariable]）。
/// - [projectVars]：项目变量（[ProjectVariable]）。
class AvailableVars {
  /// 控制流上游节点输出列表。
  final List<UpstreamOutput> upstream;

  /// 函数局部变量列表。
  final List<FunctionVariable> funcVars;

  /// 项目级变量列表。
  final List<ProjectVariable> projectVars;

  const AvailableVars({
    this.upstream = const [],
    this.funcVars = const [],
    this.projectVars = const [],
  });

  /// 三来源是否全为空。
  bool get isEmpty =>
      upstream.isEmpty && funcVars.isEmpty && projectVars.isEmpty;
}

/// `#` 引用作用域解析器。
///
/// 双平面模型下，数据平面的 `#` 引用作用域 = 控制流上游节点输出
/// + 函数变量 + 项目变量。本类负责：
///
/// - [resolveUpstreamOutputs]：沿 [ControlEdge] 反向传递闭包，收集可达
///   节点的命名数据输出（循环作用域由闭包语义天然保证——不可达即不可见）。
/// - [resolveAllAvailable]：合并三来源返回 [AvailableVars]。
/// - [matchByName]：按名称（大小写不敏感）跨三来源匹配，支持 `#名称`
///   快速引用（唯一命中直建引用，多义/未命中交由卡片选择）。
///
/// **防环**：闭包计算带 visited 集合，控制流图意外成环时不会死循环。
class ScopeResolver {
  ScopeResolver._();

  /// 沿控制流反向闭包，收集从 [nodeId] 出发可达（作为祖先）的节点的
  /// 命名数据输出。
  ///
  /// 反向定义：对边 `fromNode --fromPort--> toNode`，若 `toNode` 在闭包内，
  /// 则 `fromNode` 亦在闭包内（即 [nodeId] 的控制流上游）。
  /// [nodeId] 自身的输出不计入（节点不可引用自身输出）。
  ///
  /// 返回结果按节点在 [FunctionDef.nodes] 中的声明顺序稳定排列，
  /// 同节点内按 [Node.dataOutputs] 顺序。
  static List<UpstreamOutput> resolveUpstreamOutputs(
    FunctionDef functionDef,
    String nodeId,
  ) {
    // 反向 BFS：从 nodeId 出发，沿 toNode==c 的边回溯到 fromNode。
    final visited = <String>{};
    final stack = <String>[nodeId];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      for (final edge in functionDef.controlEdges) {
        if (edge.toNode != current) continue;
        final pred = edge.fromNode;
        // 防环：visited 去重；排除 nodeId 自身（不可引用自身输出）。
        if (pred == nodeId) continue;
        if (visited.add(pred)) {
          stack.add(pred);
        }
      }
    }

    // 按 nodes 声明顺序稳定输出。
    final result = <UpstreamOutput>[];
    for (final node in functionDef.nodes) {
      if (node.id == nodeId) continue;
      if (!visited.contains(node.id)) continue;
      final spec = NodeKindRegistry.getSpec(node.kind);
      final label = spec?.displayName ?? node.kind;
      for (final out in node.dataOutputs) {
        result.add(UpstreamOutput(
          nodeId: node.id,
          nodeKind: node.kind,
          nodeLabel: label,
          outputName: out.name,
          type: out.type,
        ));
      }
    }
    return result;
  }

  /// 合并三来源返回 [AvailableVars]。
  ///
  /// [project] 为 null 时 [AvailableVars.projectVars] 为空。
  static AvailableVars resolveAllAvailable(
    FunctionDef functionDef,
    Project? project,
    String nodeId,
  ) {
    return AvailableVars(
      upstream: resolveUpstreamOutputs(functionDef, nodeId),
      funcVars: functionDef.funcVars,
      projectVars: project?.projectVars ?? const [],
    );
  }

  /// 按 [name]（大小写不敏感）跨三来源匹配候选变量。
  ///
  /// 匹配规则：
  /// - 上游输出按 [UpstreamOutput.outputName] 匹配；
  /// - 函数变量按 [FunctionVariable.name] 匹配；
  /// - 项目变量按 [ProjectVariable.name] 匹配。
  ///
  /// 返回候选的 [VariableRef] 列表（保留来源信息，供调用方冲突标注）。
  /// 列表长度：
  /// - 0：未命中；
  /// - 1：唯一命中，可直接建立引用；
  /// - >1：跨来源同名冲突，交由卡片选择。
  static List<VariableRef> matchByName(
    FunctionDef functionDef,
    Project? project,
    String nodeId,
    String name,
  ) {
    final lower = name.toLowerCase();
    final refs = <VariableRef>[];
    for (final u in resolveUpstreamOutputs(functionDef, nodeId)) {
      if (u.outputName.toLowerCase() == lower) {
        refs.add(u.toRef());
      }
    }
    for (final v in functionDef.funcVars) {
      if (v.name.toLowerCase() == lower) {
        refs.add(VariableRef.funcVar(varId: v.id));
      }
    }
    if (project != null) {
      for (final v in project.projectVars) {
        if (v.name.toLowerCase() == lower) {
          refs.add(VariableRef.projVar(varId: v.id));
        }
      }
    }
    return refs;
  }
}
