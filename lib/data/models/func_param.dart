import 'port.dart';

/// 函数签名参数（入参 / 出参公用模型）。
///
/// 用于 [FunctionDef.inputs] / [FunctionDef.outputs] 的显式签名声明。
/// `function_call` 节点按目标函数的 [inputs] 动态生成参数端口，
/// 按 [outputs] 动态生成命名数据输出端口；`return` 节点按 [outputs]
/// 名映射返回多值。
class FuncParam {
  /// 参数名（在所属函数的 inputs / outputs 内唯一）。
  final String name;

  /// 参数类型。
  final PortType type;

  /// 默认值（仅 inputs 有意义；outputs 通常无默认值）。
  final Object? defaultValue;

  /// 描述（可空，用于编辑器展示）。
  final String? description;

  const FuncParam({
    required this.name,
    required this.type,
    this.defaultValue,
    this.description,
  });

  FuncParam copyWith({
    String? name,
    PortType? type,
    Object? defaultValue,
    String? description,
  }) =>
      FuncParam(
        name: name ?? this.name,
        type: type ?? this.type,
        defaultValue: defaultValue ?? this.defaultValue,
        description: description ?? this.description,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FuncParam &&
          name == other.name &&
          type == other.type &&
          defaultValue == other.defaultValue &&
          description == other.description;

  @override
  int get hashCode => Object.hash(name, type, defaultValue, description);

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.toJson(),
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (description != null) 'description': description,
      };

  factory FuncParam.fromJson(Map<String, dynamic> json) => FuncParam(
        name: json['name'] as String,
        type: PortType.fromJson(json['type']),
        defaultValue: json['defaultValue'],
        description: json['description'] as String?,
      );

  @override
  String toString() => 'FuncParam($name: $type)';
}
