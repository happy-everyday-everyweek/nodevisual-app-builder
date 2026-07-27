import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 颜色选择器组件定义。
///
/// `value` 支持 `#` 引用变量。触发 onChanged 事件。
const ComponentDef colorPickerComponentDef = ComponentDef(
  type: 'color_picker',
  label: '颜色选择器',
  category: ComponentCategory.interactive,
  icon: Icons.color_lens_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'value',
      label: '颜色值',
      type: PropType.color,
      defaultValue: '#000000',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'showAlpha',
      label: '显示透明度',
      type: PropType.boolean,
      defaultValue: true,
    ),
    PropSpec(
      key: 'showHex',
      label: '显示 HEX',
      type: PropType.boolean,
      defaultValue: true,
    ),
  ],
  styles: [
    StyleSpec(
      key: 'size',
      label: '预览尺寸',
      type: StyleType.number,
      defaultValue: 32,
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 8,
    ),
    StyleSpec(
      key: 'borderColor',
      label: '边框颜色',
      type: StyleType.color,
      defaultValue: '#BDBDBD',
    ),
  ],
  events: [
    EventSpec(name: 'onChanged', label: '变更'),
  ],
  defaultStyle: {
    'size': 32,
    'borderRadius': 8,
    'borderColor': '#BDBDBD',
  },
);
