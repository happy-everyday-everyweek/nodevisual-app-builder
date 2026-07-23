import '../../data/models/control_edge.dart';
import '../../data/models/function_def.dart';

/// 节点图 DAG 校验工具。
///
/// 双平面模型要求控制流图（[FunctionDef.controlEdges]）必须是
/// 有向无环图（DAG），以保证节点可按拓扑序遍历执行。本工具负责：
/// - 在新增边前预检是否会形成环（[wouldCreateCycle]）；
/// - 对整个函数图做完整性校验（[validateGraph]）。
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

  /// 整图校验：返回错误描述列表（空列表表示通过）。
  ///
  /// 当前检测项：
  /// 1. 控制流图中是否已存在环（防御性，正常编辑流程不会出现）；
  /// 2. 是否存在孤立节点（无任何入边或出边）；
  /// 3. 边是否引用了不存在的节点；
  /// 4. 一个节点的入口是否被多条边占据（v1 限制单入）。
  static List<String> validateGraph(FunctionDef fn) {
    final errors = <String>[];

    // 1. 环检测（迭代 DFS，按 fromNode 出发回溯自身）。
    if (_hasCycle(fn.controlEdges)) {
      errors.add('控制流图中存在环，无法拓扑排序执行');
    }

    final nodeIds = <String>{for (final n in fn.nodes) n.id};

    // 2. 边引用合法性 + 4. 单入限制。
    final inDegree = <String, int>{};
    for (final edge in fn.controlEdges) {
      if (!nodeIds.contains(edge.fromNode)) {
        errors.add('连线 ${edge.fromNode}.${edge.fromPort} -> ${edge.toNode} '
            '引用了不存在的源节点');
      }
      if (!nodeIds.contains(edge.toNode)) {
        errors.add('连线 ${edge.fromNode}.${edge.fromPort} -> ${edge.toNode} '
            '引用了不存在的目标节点');
      }
      inDegree[edge.toNode] = (inDegree[edge.toNode] ?? 0) + 1;
    }
    for (final entry in inDegree.entries) {
      if (entry.value > 1) {
        errors.add('节点 ${entry.key} 的入口被 ${entry.value} 条边占据，'
            'v1 仅支持单入');
      }
    }

    // 3. 孤立节点（无入边且无出边）。
    final connected = <String>{};
    for (final edge in fn.controlEdges) {
      connected.add(edge.fromNode);
      connected.add(edge.toNode);
    }
    for (final node in fn.nodes) {
      if (!connected.contains(node.id)) {
        errors.add('节点 ${node.kind}#${node.id} 是孤立的，'
            '未连接到任何控制流');
      }
    }

    return errors;
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
