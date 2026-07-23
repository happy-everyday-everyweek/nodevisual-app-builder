/// 控制流连线（双平面模型的"画布连线"平面）。
///
/// **双平面模型**：[ControlEdge] 仅表达执行顺序与控制流分支，
/// **不承载任何数据，也不做类型校验**。数据平面通过节点编辑页
/// 内的 `#` 引用（[VariableRef]）完成，二者解耦。
///
/// 一条 [ControlEdge] 表示：从 [fromNode] 的命名控制输出 [fromPort]
/// 流向目标节点 [toNode] 的入口。
class ControlEdge {
  /// 起始节点 id。
  final String fromNode;

  /// 起始节点的命名控制输出端口名（对应 [ControlOutput.name]）。
  final String fromPort;

  /// 目标节点 id（目标节点默认入口，无需指定端口名）。
  final String toNode;

  const ControlEdge({
    required this.fromNode,
    required this.fromPort,
    required this.toNode,
  });

  ControlEdge copyWith({
    String? fromNode,
    String? fromPort,
    String? toNode,
  }) =>
      ControlEdge(
        fromNode: fromNode ?? this.fromNode,
        fromPort: fromPort ?? this.fromPort,
        toNode: toNode ?? this.toNode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlEdge &&
          fromNode == other.fromNode &&
          fromPort == other.fromPort &&
          toNode == other.toNode;

  @override
  int get hashCode => Object.hash(fromNode, fromPort, toNode);

  Map<String, dynamic> toJson() => {
        'fromNode': fromNode,
        'fromPort': fromPort,
        'toNode': toNode,
      };

  factory ControlEdge.fromJson(Map<String, dynamic> json) => ControlEdge(
        fromNode: json['fromNode'] as String,
        fromPort: json['fromPort'] as String,
        toNode: json['toNode'] as String,
      );

  @override
  String toString() =>
      'ControlEdge($fromNode.$fromPort -> $toNode)';
}
