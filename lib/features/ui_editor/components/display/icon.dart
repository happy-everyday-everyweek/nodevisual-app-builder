import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 图标组件定义。
///
/// 三种来源：本地上传 SVG / 直接粘贴 SVG 代码 / 图标库（material / lucide）。
/// 展示类组件，不触发用户事件。
const ComponentDef iconComponentDef = ComponentDef(
  type: 'icon',
  label: '图标',
  category: ComponentCategory.display,
  icon: Icons.emoji_emotions,
  isContainer: false,
  props: [
    PropSpec(
      key: 'sourceType',
      label: '来源类型',
      type: PropType.select,
      defaultValue: 'library',
      options: ['upload', 'svg', 'library'],
    ),
    PropSpec(
      key: 'svgCode',
      label: 'SVG 代码',
      type: PropType.multiline,
      defaultValue: '',
    ),
    PropSpec(
      key: 'iconName',
      label: '图标名',
      type: PropType.text,
      defaultValue: 'star',
    ),
    PropSpec(
      key: 'iconLibrary',
      label: '图标库',
      type: PropType.select,
      defaultValue: 'material',
      options: ['material', 'lucide'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'size',
      label: '尺寸',
      type: StyleType.number,
      defaultValue: 24,
    ),
    StyleSpec(
      key: 'color',
      label: '颜色',
      type: StyleType.color,
      defaultValue: '#000000',
    ),
  ],
  events: [],
  defaultStyle: {
    'size': 24,
    'color': '#000000',
  },
);
