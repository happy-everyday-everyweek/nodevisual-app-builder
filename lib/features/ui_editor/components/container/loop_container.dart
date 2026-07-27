import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 循环渲染容器组件定义。
///
/// 容器类组件。`items` 为数据数组（支持 `#` 引用），容器为每个 item
/// 渲染一份子组件；子组件可通过组件上下文变量引用 `item` / `index`。
/// 触发 onItemTap 事件。
const ComponentDef loopContainerComponentDef = ComponentDef(
  type: 'loop_container',
  label: '循环容器',
  category: ComponentCategory.container,
  icon: Icons.repeat,
  isContainer: true,
  props: [
    PropSpec(
      key: 'items',
      label: '数据源',
      type: PropType.list,
      defaultValue: <Object>[],
      supportsBinding: true,
    ),
    PropSpec(
      key: 'direction',
      label: '排列方向',
      type: PropType.select,
      defaultValue: 'vertical',
      options: ['vertical', 'horizontal'],
    ),
    PropSpec(
      key: 'itemKey',
      label: '项键名',
      type: PropType.text,
      defaultValue: 'id',
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
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 0,
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
      defaultValue: 8,
    ),
  ],
  events: [
    EventSpec(name: 'onItemTap', label: '点击项'),
  ],
  defaultStyle: {
    'backgroundColor': 'transparent',
    'borderRadius': 0,
    'padding': 0,
    'itemSpacing': 8,
  },
);
