import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 图表组件定义。
///
/// 支持 7 种图表类型：柱状 / 面积 / 饼图 / 散点 / 雷达 / 热力 / 漏斗。
/// `dataSource` 支持 `#` 引用变量（数组或聚合数据）。
/// 展示类组件，不触发用户事件。
const ComponentDef chartComponentDef = ComponentDef(
  type: 'chart',
  label: '图表',
  category: ComponentCategory.display,
  icon: Icons.bar_chart,
  isContainer: false,
  props: [
    PropSpec(
      key: 'chartType',
      label: '图表类型',
      type: PropType.select,
      defaultValue: 'bar',
      options: ['bar', 'area', 'pie', 'scatter', 'radar', 'heatmap', 'funnel'],
    ),
    PropSpec(
      key: 'dataSource',
      label: '数据源',
      type: PropType.list,
      defaultValue: <Object>[],
      supportsBinding: true,
    ),
  ],
  styles: [
    StyleSpec(
      key: 'palette',
      label: '调色板',
      type: StyleType.select,
      defaultValue: 'default',
      options: ['default', 'warm', 'cool', 'pastel', 'vivid', 'mono'],
    ),
    StyleSpec(
      key: 'showAxis',
      label: '显示坐标轴',
      type: StyleType.boolean,
      defaultValue: true,
    ),
    StyleSpec(
      key: 'showLegend',
      label: '显示图例',
      type: StyleType.boolean,
      defaultValue: true,
    ),
    StyleSpec(
      key: 'showTooltip',
      label: '显示提示',
      type: StyleType.boolean,
      defaultValue: true,
    ),
  ],
  events: [],
  defaultStyle: {
    'palette': 'default',
    'showAxis': true,
    'showLegend': true,
    'showTooltip': true,
  },
);
