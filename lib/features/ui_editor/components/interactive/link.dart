import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 链接组件定义。
///
/// `url` 支持 `#` 引用变量。触发 onTap 事件。
const ComponentDef linkComponentDef = ComponentDef(
  type: 'link',
  label: '链接',
  category: ComponentCategory.interactive,
  icon: Icons.link,
  isContainer: false,
  props: [
    PropSpec(
      key: 'text',
      label: '显示文本',
      type: PropType.text,
      defaultValue: '链接',
    ),
    PropSpec(
      key: 'url',
      label: '链接地址',
      type: PropType.url,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'target',
      label: '打开方式',
      type: PropType.select,
      defaultValue: 'self',
      options: ['self', 'blank'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'color',
      label: '颜色',
      type: StyleType.color,
      defaultValue: '#1976D2',
    ),
    StyleSpec(
      key: 'fontSize',
      label: '字号',
      type: StyleType.number,
      defaultValue: 14,
    ),
    StyleSpec(
      key: 'fontWeight',
      label: '字重',
      type: StyleType.select,
      defaultValue: 'normal',
      options: ['thin', 'light', 'normal', 'medium', 'bold', 'w900'],
    ),
    StyleSpec(
      key: 'underline',
      label: '下划线',
      type: StyleType.boolean,
      defaultValue: true,
    ),
  ],
  events: [
    EventSpec(name: 'onTap', label: '点击'),
  ],
  defaultStyle: {
    'color': '#1976D2',
    'fontSize': 14,
    'fontWeight': 'normal',
    'underline': true,
  },
);
