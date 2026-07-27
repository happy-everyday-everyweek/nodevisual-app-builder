import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 分页器组件定义。
///
/// `currentPage` 支持 `#` 引用变量。触发 onPageChange 事件。
const ComponentDef paginationComponentDef = ComponentDef(
  type: 'pagination',
  label: '分页器',
  category: ComponentCategory.interactive,
  icon: Icons.pages_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'currentPage',
      label: '当前页',
      type: PropType.number,
      defaultValue: 1,
      supportsBinding: true,
    ),
    PropSpec(
      key: 'totalPage',
      label: '总页数',
      type: PropType.number,
      defaultValue: 1,
    ),
    PropSpec(
      key: 'pageSize',
      label: '每页条数',
      type: PropType.number,
      defaultValue: 10,
    ),
    PropSpec(
      key: 'showQuickJumper',
      label: '显示跳转',
      type: PropType.boolean,
      defaultValue: false,
    ),
  ],
  styles: [
    StyleSpec(
      key: 'activeColor',
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
      key: 'fontSize',
      label: '字号',
      type: StyleType.number,
      defaultValue: 14,
    ),
    StyleSpec(
      key: 'itemSpacing',
      label: '项间距',
      type: StyleType.number,
      defaultValue: 8,
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 4,
    ),
  ],
  events: [
    EventSpec(name: 'onPageChange', label: '翻页'),
  ],
  defaultStyle: {
    'activeColor': '#1976D2',
    'textColor': '#000000',
    'fontSize': 14,
    'itemSpacing': 8,
    'borderRadius': 4,
  },
);
