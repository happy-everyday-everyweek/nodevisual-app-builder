import 'package:collection/collection.dart';

import 'variable_ref.dart';

const DeepCollectionEquality _uiDeepEq = DeepCollectionEquality();

/// 加载态策略（仅用于含时间线的引用：函数变量、组件上下文未渲染对应项）。
///
/// 当 `#` 引用解析时变量未就绪（函数未执行/执行中/失败，或容器组件
/// 未渲染到对应项），系统按此策略返回占位值，避免 UI 出现 undefined。
enum LoadingStrategy {
  /// 按类型返回默认值（number→0, string→'', list→[], map→{}, bool→false）。
  typeDefault,

  /// 返回用户填写的占位文字（[Binding.placeholderText]）。
  placeholder,

  /// 不渲染该属性（文本类返回空串，图片类返回 null 触发不渲染）。
  blank;

  /// 序列化为字符串。
  String toJson() => name;

  /// 反序列化，未知值降级为 [typeDefault]。
  static LoadingStrategy fromJson(Object? value) {
    if (value is LoadingStrategy) return value;
    if (value is String) {
      return LoadingStrategy.values.firstWhere(
        (e) => e.name == value,
        orElse: () => LoadingStrategy.typeDefault,
      );
    }
    return LoadingStrategy.typeDefault;
  }
}

/// UI 属性绑定（UI 段的 IR 元素）。
///
/// 将 UI 节点的某个属性绑定到一个变量引用，实现 UI 与数据联动。
/// 绑定的 [ref] 可引用项目变量 / 组件上下文变量 / 函数变量 / 上游节点输出。
///
/// 当 [ref] 指向函数变量或组件上下文变量时，可能因时间线或容器渲染
/// 时机未就绪，由 [loadingStrategy] 决定占位行为，避免用户手动处理。
class Binding {
  /// 绑定的变量引用。
  final VariableRef ref;

  /// 加载态策略（默认 [LoadingStrategy.typeDefault]）。
  final LoadingStrategy loadingStrategy;

  /// 占位文字（仅 [LoadingStrategy.placeholder] 时使用）。
  final String? placeholderText;

  const Binding({
    required this.ref,
    this.loadingStrategy = LoadingStrategy.typeDefault,
    this.placeholderText,
  });

  /// 向后兼容构造：仅 ref，默认 typeDefault 策略。
  factory Binding.fromRef(VariableRef ref) => Binding(ref: ref);

  Binding copyWith({
    VariableRef? ref,
    LoadingStrategy? loadingStrategy,
    Object? placeholderText = _sentinel,
  }) =>
      Binding(
        ref: ref ?? this.ref,
        loadingStrategy: loadingStrategy ?? this.loadingStrategy,
        placeholderText: identical(placeholderText, _sentinel)
            ? this.placeholderText
            : placeholderText as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Binding &&
          ref == other.ref &&
          loadingStrategy == other.loadingStrategy &&
          placeholderText == other.placeholderText;

  @override
  int get hashCode => Object.hash(ref, loadingStrategy, placeholderText);

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'ref': ref.toJson()};
    if (loadingStrategy != LoadingStrategy.typeDefault) {
      json['loadingStrategy'] = loadingStrategy.toJson();
    }
    if (placeholderText != null) json['placeholderText'] = placeholderText;
    return json;
  }

  factory Binding.fromJson(Map<String, dynamic> json) => Binding(
        ref: VariableRef.fromJson(json['ref'] as Map<String, dynamic>),
        loadingStrategy: LoadingStrategy.fromJson(json['loadingStrategy']),
        placeholderText: json['placeholderText'] as String?,
      );

  @override
  String toString() =>
      'Binding($ref, $loadingStrategy${placeholderText != null ? ', "$placeholderText"' : ''})';
}

/// UI 树节点（UI 段的核心组成单元）。
///
/// 通过 [children] 形成无限嵌套的 UI 树；[props] 保存静态属性，
/// [bindings] 保存动态绑定（属性名 -> [Binding]）。
///
/// [pageId] 标记此节点（及其子树）所属的页面；顶层 UI 节点的 pageId
/// 用于关联 [Page] 概念，承载页面级触发与页面作用域函数变量。
class UiNode {
  /// 唯一标识。
  final String id;

  /// UI 类型标识（如 'Text' / 'Column' / 'ElevatedButton'）。
  final String type;

  /// 所属页面 id（标记此节点所属页面；顶层节点关联 [Page.id]）。
  final String? pageId;

  /// 静态属性。
  final Map<String, dynamic> props;

  /// 子节点列表。
  final List<UiNode> children;

  /// 属性绑定（属性名 -> 绑定）。
  final Map<String, Binding> bindings;

  const UiNode({
    required this.id,
    required this.type,
    this.pageId,
    this.props = const {},
    this.children = const [],
    this.bindings = const {},
  });

  UiNode copyWith({
    String? id,
    String? type,
    Object? pageId = _sentinel,
    Map<String, dynamic>? props,
    List<UiNode>? children,
    Map<String, Binding>? bindings,
  }) =>
      UiNode(
        id: id ?? this.id,
        type: type ?? this.type,
        pageId: identical(pageId, _sentinel)
            ? this.pageId
            : pageId as String?,
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
          pageId == other.pageId &&
          _uiDeepEq.equals(props, other.props) &&
          _uiDeepEq.equals(children, other.children) &&
          _uiDeepEq.equals(bindings, other.bindings);

  @override
  int get hashCode => Object.hash(id, type, pageId, children, bindings);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        if (pageId != null) 'pageId': pageId,
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
        pageId: json['pageId'] as String?,
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

const Object _sentinel = Object();
