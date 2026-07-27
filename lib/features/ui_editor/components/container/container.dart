import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 通用容器组件定义。
///
/// 容器类组件（可容纳 children）。子组件按 9 宫格 + 绝对布局组织
/// （由 LayoutContainer 渲染，mode 由用户切换）。
const ComponentDef containerComponentDef = ComponentDef(
  type: 'container',
  label: '容器',
  category: ComponentCategory.container,
  icon: Icons.crop_square,
  isContainer: true,
  props: [
    PropSpec(
      key: 'layoutMode',
      label: '布局模式',
      type: PropType.select,
      defaultValue: 'relative',
      options: ['relative', 'absolute'],
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
  events: [],
  defaultStyle: {
    'backgroundColor': 'transparent',
    'borderRadius': 0,
    'borderWidth': 0,
    'borderColor': '#000000',
    'padding': 0,
  },
);
