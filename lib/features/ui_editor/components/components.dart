/// UI 编辑器内置组件定义（Phase 3）。
///
/// 本文件为 barrel：统一导出所有内置组件的 [ComponentDef] 顶层常量，
/// 供 [ComponentRegistry]（component_registry_v2.dart）注册使用。
///
/// 分类：
/// - display：纯展示组件（text / image / video / icon / chart）。
/// - interactive：交互组件（button / input / picker 等 17 个）。
/// - container：容器组件（container / conditional / loop / list / query）。
///
/// 消费方一般通过 [ComponentRegistry.byType] / [ComponentRegistry.byCategory]
/// 查询，无需直接引用具体组件常量。
library;

export '../component_registry_v2.dart' show
    ComponentCategory,
    ComponentDef,
    ComponentRegistry,
    EventSpec,
    PropSpec,
    PropType,
    StyleSpec,
    StyleType;

// ---- 展示类 ----
export 'display/chart.dart' show chartComponentDef;
export 'display/icon.dart' show iconComponentDef;
export 'display/image.dart' show imageComponentDef;
export 'display/text.dart' show textComponentDef;
export 'display/video.dart' show videoComponentDef;

// ---- 交互类 ----
export 'interactive/button.dart' show buttonComponentDef;
export 'interactive/button_group.dart' show buttonGroupComponentDef;
export 'interactive/cascader.dart' show cascaderComponentDef;
export 'interactive/color_picker.dart' show colorPickerComponentDef;
export 'interactive/date_picker.dart' show datePickerComponentDef;
export 'interactive/dropdown.dart' show dropdownComponentDef;
export 'interactive/fab.dart' show fabComponentDef;
export 'interactive/file_upload.dart' show fileUploadComponentDef;
export 'interactive/icon_button.dart' show iconButtonComponentDef;
export 'interactive/link.dart' show linkComponentDef;
export 'interactive/pagination.dart' show paginationComponentDef;
export 'interactive/radio.dart' show radioComponentDef;
export 'interactive/rich_text_editor.dart' show richTextEditorComponentDef;
export 'interactive/slider.dart' show sliderComponentDef;
export 'interactive/switch.dart' show switchComponentDef;
export 'interactive/tabs.dart' show tabsComponentDef;
export 'interactive/text_input.dart' show textInputComponentDef;

// ---- 容器类 ----
export 'container/conditional_container.dart' show conditionalContainerComponentDef;
export 'container/container.dart' show containerComponentDef;
export 'container/list.dart' show listComponentDef;
export 'container/loop_container.dart' show loopContainerComponentDef;
export 'container/query_container.dart' show queryContainerComponentDef;
