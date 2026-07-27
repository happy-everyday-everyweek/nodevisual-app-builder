import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 日期选择器组件定义。
///
/// 精度（year/month/day/hour/minute/second）+ 模式（single/range）。
/// `value` 支持 `#` 引用变量。触发 onSelect 事件。
const ComponentDef datePickerComponentDef = ComponentDef(
  type: 'date_picker',
  label: '日期选择器',
  category: ComponentCategory.interactive,
  icon: Icons.calendar_today_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'value',
      label: '当前值',
      type: PropType.text,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'precision',
      label: '精度',
      type: PropType.select,
      defaultValue: 'day',
      options: ['year', 'month', 'day', 'hour', 'minute', 'second'],
    ),
    PropSpec(
      key: 'mode',
      label: '模式',
      type: PropType.select,
      defaultValue: 'single',
      options: ['single', 'range'],
    ),
    PropSpec(
      key: 'placeholder',
      label: '占位文字',
      type: PropType.text,
      defaultValue: '请选择日期',
    ),
  ],
  styles: [
    StyleSpec(
      key: 'backgroundColor',
      label: '背景色',
      type: StyleType.color,
      defaultValue: '#FFFFFF',
    ),
    StyleSpec(
      key: 'textColor',
      label: '文本颜色',
      type: StyleType.color,
      defaultValue: '#000000',
    ),
    StyleSpec(
      key: 'borderColor',
      label: '边框颜色',
      type: StyleType.color,
      defaultValue: '#BDBDBD',
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 8,
    ),
    StyleSpec(
      key: 'fontSize',
      label: '字号',
      type: StyleType.number,
      defaultValue: 14,
    ),
  ],
  events: [
    EventSpec(name: 'onSelect', label: '选择'),
  ],
  defaultStyle: {
    'backgroundColor': '#FFFFFF',
    'textColor': '#000000',
    'borderColor': '#BDBDBD',
    'borderRadius': 8,
    'fontSize': 14,
  },
);
