import 'plugin_manifest.dart';

/// UI 组件插件定义。
///
/// 当 [PluginManifest.executorType] == `'ui_component'` 时使用本定义。
/// 一个 UI 组件插件向 UI 编辑器注册一个新组件类型：
/// - 在组件面板（[ComponentPanel]）中以 [displayName] 显示，归入 [category] 分类；
/// - 选中后属性面板按 [props] 描述渲染属性编辑器；
/// - 触发事件按 [events] 列表给出（存储仍用英文标识，UI 显示时映射中文）；
/// - 渲染时调用 [renderFn]：以节点 props 为输入，返回一个 UiNode 子树作为输出
///   （输出名固定为 `tree`）。编辑器将该子树替换原节点继续递归渲染。
///
/// **渲染函数限制**：[renderFn] 与函数插件类似，禁用项目变量 / 数据库 /
/// UI 控制 / 定时器 / 外部触发等依赖项目上下文的节点。运行时通过
/// [FunctionPluginExecutor] 复用解释器执行（同步结果取 `tree` 输出）。
class UiComponentDef {
  /// 组件类型标识（唯一，自动加 `plugin_` 前缀避免与内置组件冲突）。
  ///
  /// 例如 manifest 声明 `'clock'`，则最终注册的组件 type 为 `'plugin_clock'`。
  final String componentType;

  /// 中文展示名（如「时钟」）。
  final String displayName;

  /// 分类标识（对应 [ComponentCategory]：layout / display / media / input /
  /// container / indicator）。未知值归入 display。
  final String category;

  /// 图标标识（图标名，UI 侧映射到 IconData；未知值回退为 widgets）。
  final String icon;

  /// 是否可容纳子节点。
  final bool canHaveChildren;

  /// 属性描述列表（用于属性面板渲染）。
  final List<UiComponentProp> props;

  /// 触发事件列表（英文标识，UI 显示时通过 `_eventLabel` 映射中文）。
  final List<String> events;

  /// 渲染函数 IR（[FunctionDef] 的 JSON 快照）。
  ///
  /// 输入端口应与 [props] 一一对应（同名 + 类型匹配）；输出端口固定为
  /// `tree`（类型 any），其值为 UiNode 子树的 JSON。
  /// 若 [renderFn] 为空，编辑器退化为占位渲染（显示 displayName + props 摘要）。
  final FunctionExecutorDef? renderFn;

  const UiComponentDef({
    required this.componentType,
    required this.displayName,
    required this.category,
    this.icon = 'widgets',
    this.canHaveChildren = false,
    this.props = const [],
    this.events = const [],
    this.renderFn,
  });

  factory UiComponentDef.fromJson(Map<String, dynamic> json) {
    return UiComponentDef(
      componentType: (json['componentType'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'display',
      icon: (json['icon'] as String?) ?? 'widgets',
      canHaveChildren: (json['canHaveChildren'] as bool?) ?? false,
      props: (json['props'] as List?)
              ?.map((e) => UiComponentProp.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      events: (json['events'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      renderFn: (json['renderFn'] as Map<String, dynamic>?) != null
          ? FunctionExecutorDef.fromJson(
              json['renderFn'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'componentType': componentType,
        'displayName': displayName,
        'category': category,
        'icon': icon,
        'canHaveChildren': canHaveChildren,
        'props': props.map((e) => e.toJson()).toList(),
        'events': events,
        if (renderFn != null) 'renderFn': renderFn!.toJson(),
      };

  /// 完整组件类型（带 `plugin_` 前缀）。
  String get fullType => componentType.startsWith('plugin_')
      ? componentType
      : 'plugin_$componentType';
}

/// UI 组件属性描述（与 UI 编辑器 `_PropDescriptor` 对齐）。
class UiComponentProp {
  /// 属性键名。
  final String key;

  /// 中文标签。
  final String label;

  /// 编辑类型：'text' / 'number' / 'color' / 'dropdown'。
  final String kind;

  /// 下拉选项（仅 kind == 'dropdown' 时使用）。
  final List<String>? options;

  /// 是否支持 `#` 绑定。
  final bool bindable;

  const UiComponentProp({
    required this.key,
    required this.label,
    this.kind = 'text',
    this.options,
    this.bindable = false,
  });

  factory UiComponentProp.fromJson(Map<String, dynamic> json) {
    return UiComponentProp(
      key: (json['key'] as String?) ?? '',
      label: (json['label'] as String?) ?? json['key'] as String? ?? '',
      kind: (json['kind'] as String?) ?? 'text',
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
      bindable: (json['bindable'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'kind': kind,
        if (options != null) 'options': options,
        if (bindable) 'bindable': bindable,
      };
}
