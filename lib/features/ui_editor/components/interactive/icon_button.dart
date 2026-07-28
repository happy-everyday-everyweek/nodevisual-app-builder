import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 图标按钮组件定义。
///
/// 仅显示图标，触发 onTap / onLongPress 事件。
const ComponentDef iconButtonComponentDef = ComponentDef(
  type: 'icon_button',
  label: '图标按钮',
  category: ComponentCategory.interactive,
  icon: Icons.touch_app_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'iconName',
      label: '图标名',
      type: PropType.text,
      defaultValue: 'add',
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
      defaultValue: '#1976D2',
    ),
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
      defaultValue: 8,
    ),
  ],
  events: [
    EventSpec(name: 'onTap', label: '点击'),
    EventSpec(name: 'onLongPress', label: '长按'),
  ],
  defaultStyle: {
    'size': 24,
    'color': '#1976D2',
    'backgroundColor': 'transparent',
    'borderRadius': 8,
  },
);
