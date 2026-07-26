import '../../data/models/control_edge.dart';
import '../../data/models/function_def.dart';
import '../build_pipeline/build_target.dart';
import 'node_kinds.dart';

/// 校验问题严重级别。
enum IssueSeverity {
  /// 错误：阻断函数执行（环、悬挂引用、多入等）。
  error,

  /// 警告：非阻断，但需用户注意（孤立节点、平台不匹配等）。
  warning,
}

/// 单条图校验问题。
class DagValidationIssue {
  const DagValidationIssue({
    required this.severity,
    required this.message,
    this.nodeId,
    this.autoFixable = false,
  });

  /// 严重级别。
  final IssueSeverity severity;

  /// 问题描述。
  final String message;

  /// 关联节点 id（用于点击聚焦）；无关联节点时为 null。
  final String? nodeId;

  /// 是否可自动修复（如孤立节点可自动删除）。
  final bool autoFixable;

  @override
  String toString() => '${severity.name}: $message';
}

/// 节点图 DAG 校验工具。
///
/// 双平面模型要求控制流图（[FunctionDef.controlEdges]）必须是
/// 有向无环图（DAG），以保证节点可按拓扑序遍历执行。本工具负责：
/// - 在新增边前预检是否会形成环（[wouldCreateCycle]）；
/// - 对整个函数图做完整性校验（[validateGraph]）；
/// - 多端平台兼容性校验（[validatePlatforms]）；
/// - 收集可自动修复的孤立节点（[collectIsolatedNodes]）。
class DagValidator {
  DagValidator._();

  /// 检查在已有 [edges] 基础上新增 [newEdge] 是否会形成环。
  ///
  /// 思路：新增边 `fromNode -> toNode` 形成环的充要条件是
  /// **当前图中已存在从 [newEdge.toNode] 回到 [newEdge.fromNode] 的路径**。
  /// 故从 [newEdge.toNode] 出发 DFS，若能到达 [newEdge.fromNode] 则成环。
  ///
  /// 注意：[edges] 不应包含 [newEdge] 自身（即检测"添加后"的状态）。
  static bool wouldCreateCycle(
    List<ControlEdge> edges,
    ControlEdge newEdge,
  ) {
    // 自环直接判为环。
    if (newEdge.fromNode == newEdge.toNode) return true;

    // 构建邻接表（不含 newEdge）。
    final adjacency = <String, List<String>>{};
    for (final e in edges) {
      adjacency.putIfAbsent(e.fromNode, () => <String>[]).add(e.toNode);
    }

    final visited = <String>{};
    final stack = <String>[newEdge.toNode];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == newEdge.fromNode) return true;
      if (!visited.add(current)) continue;
      final nexts = adjacency[current];
      if (nexts == null) continue;
      for (final next in nexts) {
        if (!visited.contains(next)) {
          stack.add(next);
        }
      }
    }
    return false;
  }

  /// 整图校验：返回问题列表（空列表表示通过）。
  ///
  /// 检测项：
  /// 1. 控制流图中是否已存在环（error）；
  /// 2. 边是否引用了不存在的节点（error）；
  /// 3. 一个节点的入口是否被多条边占据（error，v1 限制单入）；
  /// 4. 孤立节点（warning，可自动修复——删除）。
  static List<DagValidationIssue> validateGraph(FunctionDef fn) {
    final issues = <DagValidationIssue>[];

    // 1. 环检测（迭代 DFS，按 fromNode 出发回溯自身）。
    if (_hasCycle(fn.controlEdges)) {
      issues.add(const DagValidationIssue(
        severity: IssueSeverity.error,
        message: '控制流图中存在环，无法拓扑排序执行',
      ));
    }

    final nodeIds = <String>{for (final n in fn.nodes) n.id};

    // 2. 边引用合法性 + 3. 单入限制。
    final inDegree = <String, int>{};
    for (final edge in fn.controlEdges) {
      if (!nodeIds.contains(edge.fromNode)) {
        issues.add(DagValidationIssue(
          severity: IssueSeverity.error,
          message: '连线 ${edge.fromNode}.${edge.fromPort} -> ${edge.toNode} '
              '引用了不存在的源节点',
        ));
      }
      if (!nodeIds.contains(edge.toNode)) {
        issues.add(DagValidationIssue(
          severity: IssueSeverity.error,
          message: '连线 ${edge.fromNode}.${edge.fromPort} -> ${edge.toNode} '
              '引用了不存在的目标节点',
        ));
      }
      inDegree[edge.toNode] = (inDegree[edge.toNode] ?? 0) + 1;
    }
    for (final entry in inDegree.entries) {
      if (entry.value > 1) {
        issues.add(DagValidationIssue(
          severity: IssueSeverity.error,
          nodeId: entry.key,
          message: '节点 ${entry.key} 的入口被 ${entry.value} 条边占据，'
              'v1 仅支持单入',
        ));
      }
    }

    // 4. 孤立节点（无入边且无出边）—— 警告级别，可自动修复（删除）。
    // function_input / function_output 不计入孤立节点（它们是函数的固有
    // 入口/出口，即便没有连线也是合法的初始/终止状态）。
    final connected = <String>{};
    for (final edge in fn.controlEdges) {
      connected.add(edge.fromNode);
      connected.add(edge.toNode);
    }
    for (final node in fn.nodes) {
      if (!connected.contains(node.id) &&
          node.kind != 'function_input' &&
          node.kind != 'function_output') {
        issues.add(DagValidationIssue(
          severity: IssueSeverity.warning,
          nodeId: node.id,
          autoFixable: true,
          message: '节点 ${node.kind}#${node.id.substring(0, 6)} 是孤立的，'
              '未连接到任何控制流（可自动删除）',
        ));
      }
    }

    return issues;
  }

  /// 多端平台兼容性校验：返回警告级别的问题列表。
  ///
  /// 检测函数内是否存在仅在某些平台可用的节点，但用户选中的目标平台
  /// 不包含这些平台。这类问题为**非阻断性警告**（节点在不可用平台会被
  /// 跳过或降级），仅提示用户注意。
  ///
  /// [selectedTargets] 为用户当前选中的编译目标平台集合。
  static List<DagValidationIssue> validatePlatforms(
    FunctionDef fn,
    Set<BuildTarget> selectedTargets,
  ) {
    final issues = <DagValidationIssue>[];
    if (selectedTargets.isEmpty) return issues;
    for (final node in fn.nodes) {
      final spec = NodeKindRegistry.getSpec(node.kind);
      if (spec == null || spec.isAllPlatforms) continue;
      // 节点限定的平台与用户选中平台无交集 → 警告。
      final nodePlatforms = spec.platforms!.toSet();
      final supported = selectedTargets.intersection(nodePlatforms);
      if (supported.isEmpty) {
        final nodePlatLabel = nodePlatforms.map((t) => t.label).join('/');
        issues.add(DagValidationIssue(
          severity: IssueSeverity.warning,
          nodeId: node.id,
          message: '节点 ${spec.displayName}（${node.kind}）仅支持'
              ' $nodePlatLabel，但当前目标平台不包含它（运行时将跳过）',
        ));
      }
    }
    return issues;
  }

  /// 收集所有可自动修复的孤立节点 id（用于一键删除）。
  ///
  /// 与 [validateGraph] 中孤立节点判定一致：无入边且无出边，且不是
  /// function_input / function_output。
  static List<String> collectIsolatedNodes(FunctionDef fn) {
    final connected = <String>{};
    for (final edge in fn.controlEdges) {
      connected.add(edge.fromNode);
      connected.add(edge.toNode);
    }
    final result = <String>[];
    for (final node in fn.nodes) {
      if (!connected.contains(node.id) &&
          node.kind != 'function_input' &&
          node.kind != 'function_output') {
        result.add(node.id);
      }
    }
    return result;
  }

  /// 整图环检测（基于颜色标记的迭代 DFS）。
  static bool _hasCycle(List<ControlEdge> edges) {
    final adjacency = <String, List<String>>{};
    for (final e in edges) {
      adjacency.putIfAbsent(e.fromNode, () => <String>[]).add(e.toNode);
    }

    // 0 = 未访问，1 = 在当前 DFS 栈中，2 = 已完成。
    final state = <String, int>{};
    final stack = <_DfsFrame>[];
    for (final start in adjacency.keys) {
      if (state[start] != null && state[start] != 0) continue;
      stack.add(_DfsFrame(start, 0));
      while (stack.isNotEmpty) {
        final frame = stack.last;
        final node = frame.node;
        if (frame.index == 0) {
          if (state[node] == 1) {
            // 不应发生，防御性返回。
            stack.removeLast();
            continue;
          }
          if (state[node] == 2) {
            stack.removeLast();
            continue;
          }
          state[node] = 1;
        }
        final nexts = adjacency[node] ?? const <String>[];
        var advanced = false;
        while (frame.index < nexts.length) {
          final next = nexts[frame.index];
          frame.index++;
          final s = state[next] ?? 0;
          if (s == 1) return true; // 回边 = 环
          if (s == 2) continue;
          stack.add(_DfsFrame(next, 0));
          advanced = true;
          break;
        }
        if (!advanced) {
          state[node] = 2;
          stack.removeLast();
        }
      }
    }
    return false;
  }
}

/// 迭代 DFS 的栈帧（节点 + 当前未探索子节点索引）。
class _DfsFrame {
  _DfsFrame(this.node, this.index);

  final String node;
  int index;
}
