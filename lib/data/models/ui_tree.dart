import 'package:collection/collection.dart';

import 'variable_ref.dart';

const DeepCollectionEquality _uiDeepEq = DeepCollectionEquality();

/// UI 属性绑定（UI 段的 IR 元素）。
///
/// 将 UI 节点的某个属性绑定到一个变量引用，实现 UI 与数据联动。
/// 绑定的 [ref] 可引用上游节点输出、函数变量或项目变量。
class Binding {
  /// 绑定的变量引用。
  final VariableRef ref;

  const Binding({required this.ref});

  Binding copyWith({VariableRef? ref}) => Binding(ref: ref ?? this.ref);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Binding && ref == other.ref;

  @override
  int get hashCode => ref.hashCode;

  Map<String, dynamic> toJson() => {'ref': ref.toJson()};

  factory Binding.fromJson(Map<String, dynamic> json) => Binding(
        ref: VariableRef.fromJson(
          json['ref'] as Map<String, dynamic>,
        ),
      );

  @override
  String toString() => 'Binding($ref)';
}

/// UI 树节点（UI 段的核心组成单元）。
///
/// 通过 [children] 形成无限嵌套的 UI 树；[props] 保存静态属性，
/// [bindings] 保存动态绑定（属性名 -> [Binding]）。
class UiNode {
  /// 唯一标识。
  final String id;

  /// UI 类型标识（如 'Text' / 'Column' / 'ElevatedButton'）。
  final String type;

  /// 静态属性。
  final Map<String, dynamic> props;

  /// 子节点列表。
  final List<UiNode> children;

  /// 属性绑定（属性名 -> 绑定）。
  final Map<String, Binding> bindings;

  const UiNode({
    required this.id,
    required this.type,
    this.props = const {},
    this.children = const [],
    this.bindings = const {},
  });

  UiNode copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? props,
    List<UiNode>? children,
    Map<String, Binding>? bindings,
  }) =>
      UiNode(
        id: id ?? this.id,
        type: type ?? this.type,
        props: props ?? this.props,
        children: children ?? this.children,
        bindings: bindings ?? this.bindings,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UiNode &&
          id == other.id &&
          type == other.type &&
          _uiDeepEq.equals(props, other.props) &&
          _uiDeepEq.equals(children, other.children) &&
          _uiDeepEq.equals(bindings, other.bindings);

  @override
  int get hashCode => Object.hash(id, type, children, bindings);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        if (props.isNotEmpty) 'props': props,
        if (children.isNotEmpty)
          'children': children.map((e) => e.toJson()).toList(),
        if (bindings.isNotEmpty)
          'bindings': bindings
              .map((key, value) => MapEntry(key, value.toJson())),
      };

  factory UiNode.fromJson(Map<String, dynamic> json) => UiNode(
        id: json['id'] as String,
        type: json['type'] as String,
        props: (json['props'] as Map<String, dynamic>?) ?? const {},
        children: (json['children'] as List<dynamic>?)
                ?.map((e) => UiNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        bindings: (json['bindings'] as Map<String, dynamic>?)
                ?.map((key, value) => MapEntry(
                      key,
                      Binding.fromJson(value as Map<String, dynamic>),
                    )) ??
            const {},
      );

  @override
  String toString() => 'UiNode($type#$id)';
}
