import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 条件渲染容器组件定义。
///
/// 容器类组件。子组件通过 `case` 属性标识所属分支；容器根据 `condition`
/// 求值结果决定渲染哪个分支。
/// - mode == single：仅渲染 `condition` 匹配的那个 case。
/// - mode == firstMatch：按子组件顺序，渲染第一个匹配的 case。
///
/// `condition` 支持 `#` 引用变量。触发 onCaseChange 事件。
const ComponentDef conditionalContainerComponentDef = ComponentDef(
  type: 'conditional_container',
  label: '条件容器',
  category: ComponentCategory.container,
  icon: Icons.alt_route,
  isContainer: true,
  props: [
    PropSpec(
      key: 'condition',
      label: '条件',
      type: PropType.text,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'mode',
      label: '匹配模式',
      type: PropType.select,
      defaultValue: 'single',
      options: ['single', 'firstMatch'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'backgroundColor',
      label: '背景色',
      type: StyleType.color,
      defaultValue: 'transparent',
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 0,
    ),
    StyleSpec(
      key: 'borderWidth',
      label: '边框宽度',
      type: StyleType.number,
      defaultValue: 0,
    ),
    StyleSpec(
      key: 'borderColor',
      label: '边框颜色',
      type: StyleType.color,
      defaultValue: '#000000',
    ),
    StyleSpec(
      key: 'padding',
      label: '内边距',
      type: StyleType.spacing,
      defaultValue: 0,
    ),
  ],
  events: [
    EventSpec(name: 'onCaseChange', label: '分支切换'),
  ],
  defaultStyle: {
    'backgroundColor': 'transparent',
    'borderRadius': 0,
    'borderWidth': 0,
    'borderColor': '#000000',
    'padding': 0,
  },
);
