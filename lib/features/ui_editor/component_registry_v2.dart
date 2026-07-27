import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../data/models/ui_tree.dart';
import 'components/components.dart';

/// UI 编辑器组件分类。
///
/// 与旧版 [ComponentCategory]（segment_view.dart 内置）相比，新版归并为
/// 三大类：展示 / 交互 / 容器。布局类与指示器类组件并入展示或容器，
/// 媒体与输入两类合并到交互或展示，简化属性面板分组。
enum ComponentCategory {
  /// 展示类（纯展示，不触发用户事件）。
  display,

  /// 交互类（响应用户输入并触发事件）。
  interactive,

  /// 容器类（可容纳子组件，向子组件注入上下文变量）。
  container,
}

/// 组件属性编辑类型（驱动属性面板渲染对应编辑器）。
enum PropType {
  /// 单行文本。
  text,

  /// 多行文本。
  multiline,

  /// 数值。
  number,

  /// 布尔。
  boolean,

  /// 下拉选择（搭配 [PropSpec.options]）。
  select,

  /// 颜色（颜色选择器，值为 hex 字符串）。
  color,

  /// 图片资源（本地上传 / base64 / url）。
  image,

  /// URL（带校验的链接输入）。
  url,

  /// 字符串数组（简单 list，如 options）。
  list,

  /// 树形结构（级联选择等用，值为嵌套 map 列表）。
  tree,
}

/// 组件样式编辑类型（驱动样式面板渲染对应编辑器）。
enum StyleType {
  /// 文本。
  text,

  /// 数值。
  number,

  /// 布尔。
  boolean,

  /// 下拉选择（搭配 [StyleSpec.options]）。
  select,

  /// 颜色（hex 字符串）。
  color,

  /// 尺寸（数值 + 单位 px/percent）。
  size,

  /// 间距（4 方向独立数值，如 padding/margin）。
  spacing,
}

/// 组件属性规格。
///
/// 描述 UI 编辑器属性面板中一项属性如何渲染、默认值、是否支持 `#` 引用。
/// [supportsBinding] 为 true 时，属性值可以是静态值或 [Binding]，
/// 由编辑器在属性面板提供「绑定变量」入口。
class PropSpec {
  /// 属性键名（与 [UiNode.props] 的 key 对齐）。
  final String key;

  /// 中文标签。
  final String label;

  /// 编辑类型。
  final PropType type;

  /// 默认值（创建组件时填入 [UiNode.props]）。
  final dynamic defaultValue;

  /// 下拉选项（仅 [type] == [PropType.select] 时使用）。
  final List<String>? options;

  /// 是否支持 `#` 引用变量。
  final bool supportsBinding;

  const PropSpec({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.options,
    this.supportsBinding = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropSpec &&
          key == other.key &&
          label == other.label &&
          type == other.type &&
          defaultValue == other.defaultValue &&
          _listEq(options, other.options) &&
          supportsBinding == other.supportsBinding;

  @override
  int get hashCode =>
      Object.hash(key, label, type, defaultValue, supportsBinding);

  @override
  String toString() => 'PropSpec($key)';
}

/// 组件样式规格。
///
/// 描述样式面板中一项样式的编辑方式与默认值。样式与 [PropSpec] 区分：
/// props 偏功能参数，styles 偏视觉样式（颜色/尺寸/排版等）。
class StyleSpec {
  /// 样式键名（与 [UiNode.style] 的 key 对齐）。
  final String key;

  /// 中文标签。
  final String label;

  /// 编辑类型。
  final StyleType type;

  /// 默认值（创建组件时填入 [UiNode.style]）。
  final dynamic defaultValue;

  /// 下拉选项（仅 [type] == [StyleType.select] 时使用）。
  final List<String>? options;

  const StyleSpec({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.options,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StyleSpec &&
          key == other.key &&
          label == other.label &&
          type == other.type &&
          defaultValue == other.defaultValue &&
          _listEq(options, other.options);

  @override
  int get hashCode => Object.hash(key, label, type, defaultValue);

  @override
  String toString() => 'StyleSpec($key)';
}

/// 组件事件规格。
///
/// 描述组件可触发的事件名（如 `onTap`），UI 编辑器据此在触发面板列出
/// 该组件的可绑定事件，映射到 [UiNode.triggers]。
class EventSpec {
  /// 事件英文标识（与 [UiNode.triggers] 的 key 对齐）。
  final String name;

  /// 中文标签。
  final String label;

  const EventSpec({required this.name, required this.label});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventSpec && name == other.name && label == other.label;

  @override
  int get hashCode => Object.hash(name, label);

  @override
  String toString() => 'EventSpec($name)';
}

/// 组件定义。
///
/// 描述一个 UI 组件类型的完整元信息：分类、图标、可编辑属性 / 样式 /
/// 触发事件、是否容器、默认样式与默认布局。属性面板、组件面板、
/// 触发面板均据此渲染。
///
/// 动画配置由框架统一处理（[UiNode.animations]），不在此处声明。
class ComponentDef {
  /// 组件类型标识（与 [UiNode.type] 对齐，如 `'text'` / `'button'`）。
  final String type;

  /// 中文展示名。
  final String label;

  /// 分类。
  final ComponentCategory category;

  /// 组件面板图标。
  final IconData? icon;

  /// 可编辑属性规格列表。
  final List<PropSpec> props;

  /// 可编辑样式规格列表。
  final List<StyleSpec> styles;

  /// 可触发事件列表。
  final List<EventSpec> events;

  /// 是否容器类（可容纳 children）。
  final bool isContainer;

  /// 默认样式（创建组件时填入 [UiNode.style]）。
  final Map<String, dynamic> defaultStyle;

  /// 默认布局配置（创建组件时填入 [UiNode.layout]；null 表示流式）。
  final LayoutConfig? defaultLayout;

  const ComponentDef({
    required this.type,
    required this.label,
    required this.category,
    this.icon,
    this.props = const [],
    this.styles = const [],
    this.events = const [],
    this.isContainer = false,
    this.defaultStyle = const {},
    this.defaultLayout,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComponentDef &&
          type == other.type &&
          label == other.label &&
          category == other.category &&
          icon == other.icon &&
          _listEq(props, other.props) &&
          _listEq(styles, other.styles) &&
          _listEq(events, other.events) &&
          isContainer == other.isContainer &&
          _deepEq(defaultStyle, other.defaultStyle) &&
          defaultLayout == other.defaultLayout;

  @override
  int get hashCode =>
      Object.hash(type, label, category, icon, isContainer, defaultLayout);

  @override
  String toString() => 'ComponentDef($type)';
}

/// 内置组件注册表（v2）。
///
/// 集中登记所有内置 UI 组件类型，提供按分类 / 按类型查询接口。
/// 与旧版 [ComponentRegistry]（component_registry.dart，仅承载插件组件）解耦：
/// - 内置组件 → 本注册表（静态）。
/// - 插件组件 → 旧注册表（运行时动态注册）。
///
/// UI 编辑器消费时合并两个数据源即可。
class ComponentRegistry {
  /// 全部内置组件定义（按 display → interactive → container 顺序）。
  static final List<ComponentDef> _defs = [
    // ---- 展示类 ----
    textComponentDef,
    imageComponentDef,
    videoComponentDef,
    iconComponentDef,
    chartComponentDef,

    // ---- 交互类 ----
    buttonComponentDef,
    iconButtonComponentDef,
    buttonGroupComponentDef,
    fabComponentDef,
    switchComponentDef,
    radioComponentDef,
    dropdownComponentDef,
    cascaderComponentDef,
    textInputComponentDef,
    sliderComponentDef,
    datePickerComponentDef,
    colorPickerComponentDef,
    fileUploadComponentDef,
    richTextEditorComponentDef,
    linkComponentDef,
    tabsComponentDef,
    paginationComponentDef,

    // ---- 容器类 ----
    containerComponentDef,
    conditionalContainerComponentDef,
    loopContainerComponentDef,
    listComponentDef,
    queryContainerComponentDef,
  ];

  /// 全部组件定义（只读视图）。
  static List<ComponentDef> get all => List.unmodifiable(_defs);

  /// 按分类筛选。
  static List<ComponentDef> byCategory(ComponentCategory cat) =>
      _defs.where((d) => d.category == cat).toList(growable: false);

  /// 按 type 查询；未注册返回 null。
  static ComponentDef? byType(String type) {
    for (final d in _defs) {
      if (d.type == type) return d;
    }
    return null;
  }

  /// 判断 type 是否为已注册的内置组件。
  static bool isRegistered(String type) => byType(type) != null;

  /// 判断 type 是否为容器类组件（可容纳 children）。
  static bool isContainer(String type) {
    final def = byType(type);
    return def != null && def.isContainer;
  }

  ComponentRegistry._();
}

// ---- 内部工具：列表 / map 深比较 ----

bool _listEq<T>(List<T>? a, List<T>? b) =>
    const DeepCollectionEquality().equals(a, b);

bool _deepEq(Object? a, Object? b) =>
    const DeepCollectionEquality().equals(a, b);
