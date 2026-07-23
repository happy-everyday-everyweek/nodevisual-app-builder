import 'package:collection/collection.dart';

import 'port.dart';

const DeepCollectionEquality _nodeDeepEq = DeepCollectionEquality();

/// 节点在画布上的二维坐标。
class NodePosition {
  /// 横坐标（逻辑像素）。
  final double x;

  /// 纵坐标（逻辑像素）。
  final double y;

  const NodePosition({required this.x, required this.y});

  NodePosition copyWith({double? x, double? y}) => NodePosition(
        x: x ?? this.x,
        y: y ?? this.y,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodePosition && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory NodePosition.fromJson(Map<String, dynamic> json) => NodePosition(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );

  @override
  String toString() => 'NodePosition($x, $y)';
}

/// 函数内的节点（函数段的核心组成单元）。
///
/// **节点输出动态化**：节点按配置动态声明任意数量命名输出
/// ——[controlOutputs]（控制流分支）与 [dataOutputs]（数据输出）。
/// 类型校验仅在 [dataOutputs] 的 [PortType] 值层进行。
///
/// [params] 内的值可通过 `#` 引用（[VariableRef] 的 JSON 形式）
/// 引用控制流上游输出 / 函数变量 / 项目变量。
class Node {
  /// 唯一标识。
  final String id;

  /// 节点类型标识（对应节点配置模板，如 'if' / 'httpRequest' / 'setVar'）。
  final String kind;

  /// 节点参数（可含 `#` 引用，序列化为原始 JSON 结构）。
  final Map<String, dynamic> params;

  /// 画布坐标。
  final NodePosition position;

  /// 动态命名控制输出列表（如 then / else 分支）。
  final List<ControlOutput> controlOutputs;

  /// 动态命名数据输出列表（带原始类型）。
  final List<DataOutput> dataOutputs;

  const Node({
    required this.id,
    required this.kind,
    required this.params,
    required this.position,
    this.controlOutputs = const [],
    this.dataOutputs = const [],
  });

  Node copyWith({
    String? id,
    String? kind,
    Map<String, dynamic>? params,
    NodePosition? position,
    List<ControlOutput>? controlOutputs,
    List<DataOutput>? dataOutputs,
  }) =>
      Node(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        params: params ?? this.params,
        position: position ?? this.position,
        controlOutputs: controlOutputs ?? this.controlOutputs,
        dataOutputs: dataOutputs ?? this.dataOutputs,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Node &&
          id == other.id &&
          kind == other.kind &&
          _nodeDeepEq.equals(params, other.params) &&
          position == other.position &&
          _nodeDeepEq.equals(controlOutputs, other.controlOutputs) &&
          _nodeDeepEq.equals(dataOutputs, other.dataOutputs);

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        position,
        Object.hashAll(controlOutputs),
        Object.hashAll(dataOutputs),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'params': params,
        'position': position.toJson(),
        'controlOutputs': controlOutputs.map((e) => e.toJson()).toList(),
        'dataOutputs': dataOutputs.map((e) => e.toJson()).toList(),
      };

  factory Node.fromJson(Map<String, dynamic> json) => Node(
        id: json['id'] as String,
        kind: json['kind'] as String,
        params: (json['params'] as Map<String, dynamic>?) ?? const {},
        position: NodePosition.fromJson(
          json['position'] as Map<String, dynamic>,
        ),
        controlOutputs: (json['controlOutputs'] as List<dynamic>?)
                ?.map((e) => ControlOutput.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        dataOutputs: (json['dataOutputs'] as List<dynamic>?)
                ?.map((e) => DataOutput.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() => 'Node($kind#$id)';
}
