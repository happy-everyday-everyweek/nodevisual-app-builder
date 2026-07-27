import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 文本组件定义。
///
/// 单行 / 多行 / 富文本三种模式。`content` 支持 `#` 引用变量。
/// 展示类组件，不触发用户事件。
const ComponentDef textComponentDef = ComponentDef(
  type: 'text',
  label: '文本',
  category: ComponentCategory.display,
  icon: Icons.text_fields,
  isContainer: false,
  props: [
    PropSpec(
      key: 'content',
      label: '内容',
      type: PropType.multiline,
      defaultValue: '文本',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'mode',
      label: '模式',
      type: PropType.select,
      defaultValue: 'single',
      options: ['single', 'multi', 'rich'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'fontFamily',
      label: '字体',
      type: StyleType.text,
      defaultValue: 'Roboto',
    ),
    StyleSpec(
      key: 'fontSize',
      label: '字号',
      type: StyleType.number,
      defaultValue: 14,
    ),
    StyleSpec(
      key: 'fontColor',
      label: '颜色',
      type: StyleType.color,
      defaultValue: '#000000',
    ),
    StyleSpec(
      key: 'fontWeight',
      label: '字重',
      type: StyleType.select,
      defaultValue: 'normal',
      options: ['thin', 'light', 'normal', 'medium', 'bold', 'w900'],
    ),
    StyleSpec(
      key: 'textAlign',
      label: '对齐方式',
      type: StyleType.select,
      defaultValue: 'left',
      options: ['left', 'center', 'right', 'justify'],
    ),
    StyleSpec(
      key: 'lineHeight',
      label: '行高',
      type: StyleType.number,
      defaultValue: 1.4,
    ),
    StyleSpec(
      key: 'letterSpacing',
      label: '字间距',
      type: StyleType.number,
      defaultValue: 0,
    ),
  ],
  events: [],
  defaultStyle: {
    'fontFamily': 'Roboto',
    'fontSize': 14,
    'fontColor': '#000000',
    'fontWeight': 'normal',
    'textAlign': 'left',
    'lineHeight': 1.4,
    'letterSpacing': 0,
  },
);
