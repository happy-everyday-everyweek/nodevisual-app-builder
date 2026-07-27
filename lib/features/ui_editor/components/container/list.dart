import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 列表组件定义。
///
/// 容器类组件。静态可滚动列表（与 loop_container 区别：list 不绑定数据源，
/// 直接以 children 作为静态列表项）。`direction` 控制滚动方向。
/// 触发 onItemTap / onScroll 事件。
const ComponentDef listComponentDef = ComponentDef(
  type: 'list',
  label: '列表',
  category: ComponentCategory.container,
  icon: Icons.view_list,
  isContainer: true,
  props: [
    PropSpec(
      key: 'direction',
      label: '滚动方向',
      type: PropType.select,
      defaultValue: 'vertical',
      options: ['horizontal', 'vertical'],
    ),
    PropSpec(
      key: 'reverse',
      label: '反向',
      type: PropType.boolean,
      defaultValue: false,
    ),
    PropSpec(
      key: 'shrinkWrap',
      label: '收缩包裹',
      type: PropType.boolean,
      defaultValue: false,
    ),
  ],
  styles: [
    StyleSpec(
      key: 'backgroundColor',
      label: '背景色',
      type: StyleType.color,
      defaultValue: 'transparent',
    ),
    StyleSpec(
      key: 'padding',
      label: '内边距',
      type: StyleType.spacing,
      defaultValue: 0,
    ),
    StyleSpec(
      key: 'itemSpacing',
      label: '项间距',
      type: StyleType.number,
      defaultValue: 0,
    ),
  ],
  events: [
    EventSpec(name: 'onItemTap', label: '点击项'),
    EventSpec(name: 'onScroll', label: '滚动'),
  ],
  defaultStyle: {
    'backgroundColor': 'transparent',
    'padding': 0,
    'itemSpacing': 0,
  },
);
