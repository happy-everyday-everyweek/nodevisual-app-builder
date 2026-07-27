import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 标签页切换组件定义。
///
/// `activeIndex` 支持 `#` 引用变量。触发 onTabChange 事件。
const ComponentDef tabsComponentDef = ComponentDef(
  type: 'tabs',
  label: '标签页',
  category: ComponentCategory.interactive,
  icon: Icons.tab,
  isContainer: false,
  props: [
    PropSpec(
      key: 'tabs',
      label: '标签列表',
      type: PropType.list,
      defaultValue: <String>['标签1', '标签2', '标签3'],
    ),
    PropSpec(
      key: 'activeIndex',
      label: '当前标签',
      type: PropType.number,
      defaultValue: 0,
      supportsBinding: true,
    ),
    PropSpec(
      key: 'position',
      label: '标签位置',
      type: PropType.select,
      defaultValue: 'top',
      options: ['top', 'bottom', 'left', 'right'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'indicatorColor',
      label: '指示器颜色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'labelColor',
      label: '标签颜色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'unselectedLabelColor',
      label: '未选标签颜色',
      type: StyleType.color,
      defaultValue: '#757575',
    ),
    StyleSpec(
      key: 'fontSize',
      label: '字号',
      type: StyleType.number,
      defaultValue: 14,
    ),
    StyleSpec(
      key: 'backgroundColor',
      label: '背景色',
      type: StyleType.color,
      defaultValue: 'transparent',
    ),
  ],
  events: [
    EventSpec(name: 'onTabChange', label: '切换标签'),
  ],
  defaultStyle: {
    'indicatorColor': '#1976D2',
    'labelColor': '#1976D2',
    'unselectedLabelColor': '#757575',
    'fontSize': 14,
    'backgroundColor': 'transparent',
  },
);
