import 'package:collection/collection.dart';

/// 容器组件向子组件提供的运行时上下文（仅运行时，不持久化）。
///
/// 由容器组件在渲染时按组件树位置注入子组件：
/// - `list_vertical` / `list_horizontal`：注入 `item`（当前项）/
///   `index`（索引）。每渲染一个列表项，注入一份新的 [ComponentContext]。
/// - `tab_container`：注入 `tab`（当前 Tab 索引）。
/// - `slider` / `switch`：注入 `value`（当前值）。
///
/// 子组件通过 `#` 引用 [VariableSource.component] 时，[VariableRef.fieldName]
/// 形如 `'item'` / `'index'` / `'item.name'` / `'tab'` / `'value'`，由
/// `ScopeResolver` 解析为 `fields[fieldName]` 或 `fields[item][name]`。
///
/// **不持久化**：[ComponentContext] 是渲染期对象，序列化时丢弃。
class ComponentContext {
  /// 容器组件 id（与 [VariableRef.componentId] 对应）。
  final String componentId;

  /// 上下文字段（key = 字段名如 `item` / `index` / `tab` / `value`，
  /// value = 运行时值，可能是 Map / num / String 等）。
  final Map<String, Object?> fields;

  ComponentContext({
    required this.componentId,
    Map<String, Object?>? fields,
  }) : fields = fields ?? {};

  /// 按字段名取值。
  ///
  /// 支持点路径：
  /// - `'item'` → `fields['item']`
  /// - `'item.name'` → `(fields['item'] as Map)['name']`
  /// - `'index'` → `fields['index']`
  /// 不存在返回 null；中间值不是 Map 时返回 null。
  Object? get(String fieldName) {
    if (fieldName.isEmpty) return fields;
    final dot = fieldName.indexOf('.');
    if (dot < 0) return fields[fieldName];
    final rootKey = fieldName.substring(0, dot);
    final rest = fieldName.substring(dot + 1);
    final root = fields[rootKey];
    return _dig(root, rest);
  }

  /// 递归深挖点路径（支持任意层级 `item.user.name`）。
  static Object? _dig(Object? root, String path) {
    var current = root;
    for (final segment in path.split('.')) {
      if (current is Map<String, dynamic>) {
        current = current[segment];
      } else if (current is Map) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  /// 创建子上下文（保留 componentId，合并额外字段）。
  ComponentContext withFields(Map<String, Object?> additional) {
    return ComponentContext(
      componentId: componentId,
      fields: {...fields, ...additional},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComponentContext &&
          componentId == other.componentId &&
          const DeepCollectionEquality().equals(fields, other.fields);

  @override
  int get hashCode => Object.hash(componentId, fields);

  @override
  String toString() => 'ComponentContext($componentId: $fields)';
}
