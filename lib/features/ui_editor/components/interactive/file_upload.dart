import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 文件上传组件定义。
///
/// 限定接受类型（image/video/doc/any）+ 是否多选。`value` 支持 `#` 引用。
/// 触发 onFileSelected 事件。
const ComponentDef fileUploadComponentDef = ComponentDef(
  type: 'file_upload',
  label: '文件上传',
  category: ComponentCategory.interactive,
  icon: Icons.upload_file_outlined,
  isContainer: false,
  props: [
    PropSpec(
      key: 'accept',
      label: '接受类型',
      type: PropType.select,
      defaultValue: 'any',
      options: ['image', 'video', 'doc', 'any'],
    ),
    PropSpec(
      key: 'multiple',
      label: '多选',
      type: PropType.boolean,
      defaultValue: false,
    ),
    PropSpec(
      key: 'value',
      label: '已选文件',
      type: PropType.list,
      defaultValue: <Object>[],
      supportsBinding: true,
    ),
    PropSpec(
      key: 'hint',
      label: '提示文字',
      type: PropType.text,
      defaultValue: '点击或拖拽文件到此处上传',
    ),
  ],
  styles: [
    StyleSpec(
      key: 'backgroundColor',
      label: '背景色',
      type: StyleType.color,
      defaultValue: '#F5F5F5',
    ),
    StyleSpec(
      key: 'borderColor',
      label: '边框颜色',
      type: StyleType.color,
      defaultValue: '#BDBDBD',
    ),
    StyleSpec(
      key: 'borderRadius',
      label: '圆角',
      type: StyleType.number,
      defaultValue: 12,
    ),
    StyleSpec(
      key: 'textColor',
      label: '文本颜色',
      type: StyleType.color,
      defaultValue: '#757575',
    ),
    StyleSpec(
      key: 'minHeight',
      label: '最小高度',
      type: StyleType.number,
      defaultValue: 120,
    ),
  ],
  events: [
    EventSpec(name: 'onFileSelected', label: '选择文件'),
  ],
  defaultStyle: {
    'backgroundColor': '#F5F5F5',
    'borderColor': '#BDBDBD',
    'borderRadius': 12,
    'textColor': '#757575',
    'minHeight': 120,
  },
);
