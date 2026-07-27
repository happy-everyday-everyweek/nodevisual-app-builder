import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 浮动操作按钮（FAB）组件定义。
///
/// 圆形浮动按钮，常用于页面级主操作。触发 onTap 事件。
const ComponentDef fabComponentDef = ComponentDef(
  type: 'fab',
  label: '浮动按钮',
  category: ComponentCategory.interactive,
  icon: Icons.add_circle,
  isContainer: false,
  props: [
    PropSpec(
      key: 'icon',
      label: '图标名',
      type: PropType.text,
      defaultValue: 'add',
    ),
    PropSpec(
      key: 'label',
      label: '描述文字',
      type: PropType.text,
      defaultValue: '',
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
      key: 'foregroundColor',
      label: '前景色',
      type: StyleType.color,
      defaultValue: '#FFFFFF',
    ),
    StyleSpec(
      key: 'size',
      label: '尺寸',
      type: StyleType.select,
      defaultValue: 'regular',
      options: ['small', 'regular', 'large', 'extended'],
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 16,
    ),
  ],
  events: [
    EventSpec(name: 'onTap', label: '点击'),
  ],
  defaultStyle: {
    'backgroundColor': '#1976D2',
    'foregroundColor': '#FFFFFF',
    'size': 'regular',
    'borderRadius': 16,
  },
);
