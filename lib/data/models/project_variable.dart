import 'port.dart';

/// 项目级变量定义。
///
/// 属于 `#` 作用域的项目变量来源，可在任意函数的节点编辑页内
/// 通过 `#proj:<varId>` 引用。[type] 约束其值类型校验。
class ProjectVariable {
  /// 唯一标识。
  final String id;

  /// 变量名（在项目内唯一，用于展示与 `#` 引用解析）。
  final String name;

  /// 变量类型。
  final PortType type;

  /// 默认值（与 [type] 对应的原始值，可为 null）。
  final Object? defaultValue;

  const ProjectVariable({
    required this.id,
    required this.name,
    required this.type,
    this.defaultValue,
  });

  ProjectVariable copyWith({
    String? id,
    String? name,
    PortType? type,
    Object? defaultValue,
  }) =>
      ProjectVariable(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        defaultValue: defaultValue ?? this.defaultValue,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectVariable &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          defaultValue == other.defaultValue;

  @override
  int get hashCode => Object.hash(id, name, type, defaultValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.toJson(),
        if (defaultValue != null) 'defaultValue': defaultValue,
      };

  factory ProjectVariable.fromJson(Map<String, dynamic> json) =>
      ProjectVariable(
        id: json['id'] as String,
        name: json['name'] as String,
        type: PortType.fromJson(json['type']),
        defaultValue: json['defaultValue'],
      );

  @override
  String toString() => 'ProjectVariable($name: $type)';
}
