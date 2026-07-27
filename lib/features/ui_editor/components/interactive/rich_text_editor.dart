import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 富文本编辑器组件定义。
///
/// `content` 支持 `#` 引用变量。触发 onChanged 事件。
const ComponentDef richTextEditorComponentDef = ComponentDef(
  type: 'rich_text_editor',
  label: '富文本编辑器',
  category: ComponentCategory.interactive,
  icon: Icons.edit_note,
  isContainer: false,
  props: [
    PropSpec(
      key: 'content',
      label: '内容',
      type: PropType.multiline,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'placeholder',
      label: '占位文字',
      type: PropType.text,
      defaultValue: '请输入内容',
    ),
    PropSpec(
      key: 'readonly',
      label: '只读',
      type: PropType.boolean,
      defaultValue: false,
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
    StyleSpec(
      key: 'minHeight',
      label: '最小高度',
      type: StyleType.number,
      defaultValue: 160,
    ),
  ],
  events: [
    EventSpec(name: 'onChanged', label: '内容变更'),
  ],
  defaultStyle: {
    'backgroundColor': '#FFFFFF',
    'textColor': '#000000',
    'borderColor': '#BDBDBD',
    'borderRadius': 8,
    'fontSize': 14,
    'padding': 12,
    'minHeight': 160,
  },
);
