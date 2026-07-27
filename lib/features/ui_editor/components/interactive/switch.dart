import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 开关组件定义。
///
/// `value` 支持 `#` 引用变量。触发 onToggle 事件。
const ComponentDef switchComponentDef = ComponentDef(
  type: 'switch',
  label: '开关',
  category: ComponentCategory.interactive,
  icon: Icons.toggle_on,
  isContainer: false,
  props: [
    PropSpec(
      key: 'value',
      label: '状态',
      type: PropType.boolean,
      defaultValue: false,
      supportsBinding: true,
    ),
  ],
  styles: [
    StyleSpec(
      key: 'activeColor',
      label: '开启色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'inactiveColor',
      label: '关闭色',
      type: StyleType.color,
      defaultValue: '#BDBDBD',
    ),
    StyleSpec(
      key: 'thumbColor',
      label: '滑块色',
      type: StyleType.color,
      defaultValue: '#FFFFFF',
    ),
    StyleSpec(
      key: 'size',
      label: '尺寸',
      type: StyleType.number,
      defaultValue: 24,
    ),
  ],
  events: [
    EventSpec(name: 'onToggle', label: '切换'),
  ],
  defaultStyle: {
    'activeColor': '#1976D2',
    'inactiveColor': '#BDBDBD',
    'thumbColor': '#FFFFFF',
    'size': 24,
  },
);
