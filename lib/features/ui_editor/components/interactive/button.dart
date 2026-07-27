import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 按钮组件定义。
///
/// 5 种变体：primary / secondary / outline / text / danger。
/// `label` 支持 `#` 引用变量。触发 onTap / onLongPress 事件。
const ComponentDef buttonComponentDef = ComponentDef(
  type: 'button',
  label: '按钮',
  category: ComponentCategory.interactive,
  icon: Icons.smart_button_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'label',
      label: '文本',
      type: PropType.text,
      defaultValue: '按钮',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'variant',
      label: '变体',
      type: PropType.select,
      defaultValue: 'primary',
      options: ['primary', 'secondary', 'outline', 'text', 'danger'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'backgroundColor',
      label: '背景色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'textColor',
      label: '文本颜色',
      type: StyleType.color,
      defaultValue: '#FFFFFF',
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 8,
    ),
    StyleSpec(
      key: 'padding',
      label: '内边距',
      type: StyleType.spacing,
      defaultValue: 12,
    ),
  ],
  events: [
    EventSpec(name: 'onTap', label: '点击'),
    EventSpec(name: 'onLongPress', label: '长按'),
  ],
  defaultStyle: {
    'backgroundColor': '#1976D2',
    'textColor': '#FFFFFF',
    'borderRadius': 8,
    'padding': 12,
  },
);
