import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 图片组件定义。
///
/// 支持本地 / base64 / url 三种来源；`src` 支持 `#` 引用。
/// 本地上传资源随项目保存（由编辑器层处理，此处仅声明类型）。
const ComponentDef imageComponentDef = ComponentDef(
  type: 'image',
  label: '图片',
  category: ComponentCategory.display,
  icon: Icons.image_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'src',
      label: '资源',
      type: PropType.image,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'sourceType',
      label: '来源类型',
      type: PropType.select,
      defaultValue: 'local',
      options: ['local', 'base64', 'url'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'objectFit',
      label: '填充方式',
      type: StyleType.select,
      defaultValue: 'cover',
      options: ['cover', 'contain', 'fill', 'none'],
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 0,
    ),
    StyleSpec(
      key: 'borderWidth',
      label: '边框宽度',
      type: StyleType.number,
      defaultValue: 0,
    ),
    StyleSpec(
      key: 'borderColor',
      label: '边框颜色',
      type: StyleType.color,
      defaultValue: '#000000',
    ),
  ],
  events: [],
  defaultStyle: {
    'objectFit': 'cover',
    'borderRadius': 0,
    'borderWidth': 0,
    'borderColor': '#000000',
  },
);
