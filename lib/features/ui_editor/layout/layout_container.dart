import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../data/models/ui_tree.dart';
import 'absolute_layout_render.dart';
import 'relative_layout_render.dart';

/// ParentDataWidget：把 [LayoutConfig] 注入到子组件的 [LayoutParentData]，
/// 供布局 RenderObject（[RelativeLayoutRenderObject] /
/// [AbsoluteLayoutRenderObject]）在 performLayout 时读取。
///
/// 必须作为 [LayoutContainer] 的后代使用：
///
/// ```dart
/// LayoutContainer(
///   mode: LayoutMode.relative,
///   children: [
///     LayoutChild(
///       layout: LayoutConfig(...),
///       child: SomeWidget(),
///     ),
///   ],
/// )
/// ```
///
/// 当 [layout] 变更时，[applyParentData] 会写入新的 [LayoutConfig] 并
/// 标记父级 RenderObject 重新布局，从而触发位置/尺寸重算。
class LayoutChild extends ParentDataWidget<LayoutParentData> {
  const LayoutChild({
    super.key,
    required this.layout,
    required super.child,
  });

  /// 该子组件的布局配置。
  final LayoutConfig layout;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData;
    if (pd is LayoutParentData && pd.layout != layout) {
      pd.layout = layout;
      // 触发父级重新布局以应用新的 LayoutConfig。
      final parent = renderObject.parent;
      if (parent is RenderObject) {
        parent.markNeedsLayout();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => LayoutContainer;
}

/// 布局容器 Widget：根据 [mode] 创建对应的布局 RenderObject。
///
/// - [LayoutMode.relative]：创建 [RelativeLayoutRenderObject]，
///   按 9 宫格分组、排序、堆叠定位子组件。
/// - [LayoutMode.absolute]：创建 [AbsoluteLayoutRenderObject]，
///   按 [LayoutConfig.x] / [LayoutConfig.y] 坐标定位子组件。
///
/// 子组件应用 [LayoutChild] 包裹以注入 [LayoutConfig]；未包裹的子组件
/// 退化为 loose 布局，定位在 (0, 0)。
///
/// **混合模式**：容器创建的 RenderObject 会处理所有子组件的 layout；
/// 与容器 [mode] 一致的子组件获得精确布局，不一致的子组件由对应
/// RenderObject 按退化策略处理（详见各 RenderObject 文档）。
///
/// **运行时切换模式**：[mode] 在构造时决定 RenderObject 类型。
/// 由于 [RenderObject] 类型不可在 [updateRenderObject] 中变更，
/// 运行时切换 [mode] 需用 `ValueKey(mode)` 包裹本 Widget 以触发 remount。
class LayoutContainer extends MultiChildRenderObjectWidget {
  const LayoutContainer({
    super.key,
    this.mode = LayoutMode.relative,
    super.children,
  });

  /// 容器布局模式。
  final LayoutMode mode;

  @override
  RenderBox createRenderObject(BuildContext context) {
    return switch (mode) {
      LayoutMode.relative => RelativeLayoutRenderObject(),
      LayoutMode.absolute => AbsoluteLayoutRenderObject(),
    };
  }

  @override
  void updateRenderObject(BuildContext context, RenderBox renderObject) {
    // 模式在构造时确定；运行时切换需通过 ValueKey(mode) 触发 remount。
    // 此处无需更新：RenderObject 每次 performLayout 都从 LayoutParentData
    // 重新读取子组件的 LayoutConfig，无需容器级别的事件通知。
  }
}
