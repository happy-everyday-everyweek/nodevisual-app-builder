import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 按钮组组件定义。
///
/// 一组按钮，支持单选 / 多选（由 `exclusive` 决定）。
/// 触发 onSelect 事件。
const ComponentDef buttonGroupComponentDef = ComponentDef(
  type: 'button_group',
  label: '按钮组',
  category: ComponentCategory.interactive,
  icon: Icons.view_week,
  isContainer: false,
  props: [
    PropSpec(
      key: 'options',
      label: '选项',
      type: PropType.list,
      defaultValue: <String>['选项1', '选项2', '选项3'],
    ),
    PropSpec(
      key: 'selectedIndex',
      label: '选中索引',
      type: PropType.number,
      defaultValue: 0,
      supportsBinding: true,
    ),
    PropSpec(
      key: 'exclusive',
      label: '单选模式',
      type: PropType.boolean,
      defaultValue: true,
    ),
  ],
  styles: [
    StyleSpec(
      key: 'backgroundColor',
      label: '背景色',
      type: StyleType.color,
      defaultValue: '#F5F5F5',
    ),
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
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 8,
    ),
  ],
  events: [
    EventSpec(name: 'onSelect', label: '选择'),
  ],
  defaultStyle: {
    'backgroundColor': '#F5F5F5',
    'selectedColor': '#1976D2',
    'textColor': '#000000',
    'borderRadius': 8,
  },
);
