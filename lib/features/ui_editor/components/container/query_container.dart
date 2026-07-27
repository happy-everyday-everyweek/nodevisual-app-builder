import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 查询容器组件定义。
///
/// 容器类组件。绑定数据源 + 查询条件，子组件可引用查询结果
/// （通过组件上下文变量 `data` / `loading` / `error`）。
/// `query` 支持 `#` 引用变量。触发 onItemTap / onScroll / onLoad 事件。
const ComponentDef queryContainerComponentDef = ComponentDef(
  type: 'query_container',
  label: '查询容器',
  category: ComponentCategory.container,
  icon: Icons.cloud_download_outlined,
  isContainer: true,
  props: [
    PropSpec(
      key: 'dataSource',
      label: '数据源',
      type: PropType.text,
      defaultValue: '',
    ),
    PropSpec(
      key: 'query',
      label: '查询条件',
      type: PropType.multiline,
      defaultValue: '',
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
      key: 'pageSize',
      label: '每页条数',
      type: PropType.number,
      defaultValue: 20,
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
    EventSpec(name: 'onScroll', label: '滚动'),
    EventSpec(name: 'onLoad', label: '加载完成'),
  ],
  defaultStyle: {
    'backgroundColor': 'transparent',
    'borderRadius': 0,
    'padding': 0,
    'itemSpacing': 8,
  },
);
