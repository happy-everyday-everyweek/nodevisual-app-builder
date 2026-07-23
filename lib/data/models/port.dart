/// 端口数据类型（类型在"输出值层"声明）。
///
/// 双平面模型要求类型校验只发生在命名数据输出的值层，
/// 画布连线（控制流）不做类型校验。v1 中 [list] / [map]
/// 为无参容器，不携带元素类型参数。
enum PortType {
  /// 数值（int / double 统一为 number）。
  number,

  /// 字符串。
  string,

  /// 布尔。
  boolean,

  /// 任意类型（动态），绕过类型校验。
  any,

  /// 无参列表容器。
  list,

  /// 无参映射容器。
  map;

  /// 序列化为字符串。
  ///
  /// 注意：[boolean] 序列化为 `"bool"` 以对齐 spec IR schema 的原始类型名
  /// （`number / string / bool / any`，`List / Map` 无参容器）。
  String toJson() => this == PortType.boolean ? 'bool' : name;

  /// 从字符串反序列化，未知值降级为 [any]。
  /// 同时兼容 `"bool"` 与 `"boolean"` 两种写法。
  static PortType fromJson(Object? value) {
    if (value is PortType) return value;
    if (value is String) {
      if (value == 'bool') return PortType.boolean;
      return PortType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => PortType.any,
      );
    }
    return PortType.any;
  }
}

/// 控制流输出端口。
///
/// 节点按配置动态声明任意数量的命名控制输出
/// （如 if 节点的 `then` / `else` 分支）。
class ControlOutput {
  /// 端口名（在同一节点内唯一）。
  final String name;

  const ControlOutput({required this.name});

  ControlOutput copyWith({String? name}) =>
      ControlOutput(name: name ?? this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlOutput && name == other.name;

  @override
  int get hashCode => name.hashCode;

  Map<String, dynamic> toJson() => {'name': name};

  factory ControlOutput.fromJson(Map<String, dynamic> json) =>
      ControlOutput(name: json['name'] as String);

  @override
  String toString() => 'ControlOutput($name)';
}

/// 数据输出端口。
///
/// 类型校验仅在数据输出值层进行：每个命名数据输出声明
/// 一个原始类型 [type]。节点编辑页内的 `#` 引用据此推断。
class DataOutput {
  /// 端口名（在同一节点内唯一）。
  final String name;

  /// 输出值的原始类型。
  final PortType type;

  const DataOutput({required this.name, required this.type});

  DataOutput copyWith({String? name, PortType? type}) => DataOutput(
        name: name ?? this.name,
        type: type ?? this.type,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataOutput && name == other.name && type == other.type;

  @override
  int get hashCode => Object.hash(name, type);

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.toJson(),
      };

  factory DataOutput.fromJson(Map<String, dynamic> json) => DataOutput(
        name: json['name'] as String,
        type: PortType.fromJson(json['type']),
      );

  @override
  String toString() => 'DataOutput($name: $type)';
}
