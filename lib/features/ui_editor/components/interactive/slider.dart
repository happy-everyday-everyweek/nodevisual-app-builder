import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 滑块组件定义。
///
/// 单值 / 范围两种模式。`value` 支持 `#` 引用变量。
/// 触发 onChanged / onChangeEnd 事件。
const ComponentDef sliderComponentDef = ComponentDef(
  type: 'slider',
  label: '滑块',
  category: ComponentCategory.interactive,
  icon: Icons.linear_scale,
  isContainer: false,
  props: [
    PropSpec(
      key: 'value',
      label: '当前值',
      type: PropType.number,
      defaultValue: 0,
      supportsBinding: true,
    ),
    PropSpec(
      key: 'min',
      label: '最小值',
      type: PropType.number,
      defaultValue: 0,
    ),
    PropSpec(
      key: 'max',
      label: '最大值',
      type: PropType.number,
      defaultValue: 100,
    ),
    PropSpec(
      key: 'step',
      label: '步长',
      type: PropType.number,
      defaultValue: 1,
    ),
    PropSpec(
      key: 'mode',
      label: '模式',
      type: PropType.select,
      defaultValue: 'single',
      options: ['single', 'range'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'activeColor',
      label: '已选色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'inactiveColor',
      label: '未选色',
      type: StyleType.color,
      defaultValue: '#BDBDBD',
    ),
    StyleSpec(
      key: 'thumbColor',
      label: '滑块色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'height',
      label: '高度',
      type: StyleType.number,
      defaultValue: 36,
    ),
  ],
  events: [
    EventSpec(name: 'onChanged', label: '拖动'),
    EventSpec(name: 'onChangeEnd', label: '拖动结束'),
  ],
  defaultStyle: {
    'activeColor': '#1976D2',
    'inactiveColor': '#BDBDBD',
    'thumbColor': '#1976D2',
    'height': 36,
  },
);
