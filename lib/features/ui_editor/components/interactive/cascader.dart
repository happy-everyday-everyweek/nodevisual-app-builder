import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 级联选择组件定义。
///
/// 多级下拉，`options` 为树形结构（每项含 label / value / children）。
/// `value` 支持 `#` 引用变量。触发 onSelect 事件。
const ComponentDef cascaderComponentDef = ComponentDef(
  type: 'cascader',
  label: '级联选择',
  category: ComponentCategory.interactive,
  icon: Icons.account_tree,
  isContainer: false,
  props: [
    PropSpec(
      key: 'options',
      label: '选项（树形）',
      type: PropType.tree,
      defaultValue: <Object>[],
    ),
    PropSpec(
      key: 'value',
      label: '当前值',
      type: PropType.list,
      defaultValue: <Object>[],
      supportsBinding: true,
    ),
    PropSpec(
      key: 'placeholder',
      label: '占位文字',
      type: PropType.text,
      defaultValue: '请选择',
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
