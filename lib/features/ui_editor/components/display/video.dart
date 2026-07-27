import 'package:flutter/material.dart';

import '../../component_registry_v2.dart';

/// 视频组件定义。
///
/// 支持 local / base64 / url 三种来源；`src` 支持 `#` 引用。
/// 提供播放控制（进度条 / 控制条 / 手势 / 自动播放 / 循环 / 静音）样式开关。
const ComponentDef videoComponentDef = ComponentDef(
  type: 'video',
  label: '视频',
  category: ComponentCategory.display,
  icon: Icons.smart_display,
  isContainer: false,
  props: [
    PropSpec(
      key: 'src',
      label: '资源',
      type: PropType.url,
      defaultValue: '',
      supportsBinding: true,
    ),
    PropSpec(
      key: 'sourceType',
      label: '来源类型',
      type: PropType.select,
      defaultValue: 'url',
      options: ['local', 'base64', 'url'],
    ),
  ],
  styles: [
    StyleSpec(
      key: 'objectFit',
      label: '填充方式',
      type: StyleType.select,
      defaultValue: 'contain',
      options: ['cover', 'contain', 'fill', 'none'],
    ),
    StyleSpec(
      key: 'showProgressBar',
      label: '显示进度条',
      type: StyleType.boolean,
      defaultValue: true,
    ),
    StyleSpec(
      key: 'showControls',
      label: '显示控制条',
      type: StyleType.boolean,
      defaultValue: true,
    ),
    StyleSpec(
      key: 'enableGestures',
      label: '启用手势',
      type: StyleType.boolean,
      defaultValue: true,
    ),
    StyleSpec(
      key: 'autoPlay',
      label: '自动播放',
      type: StyleType.boolean,
      defaultValue: false,
    ),
    StyleSpec(
      key: 'loop',
      label: '循环',
      type: StyleType.boolean,
      defaultValue: false,
    ),
    StyleSpec(
      key: 'muted',
      label: '静音',
      type: StyleType.boolean,
      defaultValue: false,
    ),
  ],
  events: [],
  defaultStyle: {
    'objectFit': 'contain',
    'showProgressBar': true,
    'showControls': true,
    'enableGestures': true,
    'autoPlay': false,
    'loop': false,
    'muted': false,
  },
);
