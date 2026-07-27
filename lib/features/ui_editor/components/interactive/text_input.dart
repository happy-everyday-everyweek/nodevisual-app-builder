import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 文本输入组件定义。
///
/// 4 种模式：单行 / 多行 / 数字 / 密码。`value` 支持 `#` 引用变量。
/// 触发 onChanged / onSubmitted / onFocus / onBlur 事件。
const ComponentDef textInputComponentDef = ComponentDef(
  type: 'text_input',
  label: '文本输入',
  category: ComponentCategory.interactive,
  icon: Icons.keyboard_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'value',
      label: '内容',
      type: PropType.text,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'hint',
      label: '占位文字',
      type: PropType.text,
      defaultValue: '请输入',
    ),
    PropSpec(
      key: 'mode',
      label: '模式',
      type: PropType.select,
      defaultValue: 'single',
      options: ['single', 'multi', 'number', 'password'],
    ),
    PropSpec(
      key: 'clearable',
      label: '可清空',
      type: PropType.boolean,
      defaultValue: true,
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
    StyleSpec(
      key: 'padding',
      label: '内边距',
      type: StyleType.spacing,
      defaultValue: 12,
    ),
  ],
  events: [
    EventSpec(name: 'onChanged', label: '内容变更'),
    EventSpec(name: 'onSubmitted', label: '提交'),
    EventSpec(name: 'onFocus', label: '获得焦点'),
    EventSpec(name: 'onBlur', label: '失去焦点'),
  ],
  defaultStyle: {
    'backgroundColor': '#FFFFFF',
    'textColor': '#000000',
    'borderColor': '#BDBDBD',
    'borderRadius': 8,
    'fontSize': 14,
    'padding': 12,
  },
);
