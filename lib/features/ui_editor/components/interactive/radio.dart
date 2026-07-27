import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 单选按钮组件定义。
///
/// `value` 支持 `#` 引用变量。触发 onChanged 事件。
const ComponentDef radioComponentDef = ComponentDef(
  type: 'radio',
  label: '单选按钮',
  category: ComponentCategory.interactive,
  icon: Icons.radio_button_checked,
  isContainer: false,
  props: [
    PropSpec(
      key: 'options',
      label: '选项',
      type: PropType.list,
      defaultValue: <String>['选项1', '选项2', '选项3'],
    ),
    PropSpec(
      key: 'value',
      label: '当前值',
      type: PropType.text,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'direction',
      label: '排列方向',
      type: PropType.select,
      defaultValue: 'vertical',
      options: ['vertical', 'horizontal'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'selectedColor',
      label: '选中色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'textColor',
      label: '文本颜色',
      type: StyleType.color,
      defaultValue: '#000000',
    ),
    StyleSpec(
      key: 'fontSize',
      label: '字号',
      type: StyleType.number,
      defaultValue: 14,
    ),
  ],
  events: [
    EventSpec(name: 'onChanged', label: '变更'),
  ],
  defaultStyle: {
    'selectedColor': '#1976D2',
    'textColor': '#000000',
    'fontSize': 14,
  },
);
