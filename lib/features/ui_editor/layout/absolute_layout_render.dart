import 'package:flutter/rendering.dart';

import '../../../data/models/ui_tree.dart';
import 'relative_layout_engine.dart';
import 'relative_layout_render.dart';

/// 绝对布局 RenderObject：按 [LayoutConfig.x] / [LayoutConfig.y] 坐标定位子组件。
///
/// 支持两种单位：
/// - [SizeUnit.px]：直接像素值
/// - [SizeUnit.percent]：相对父容器宽/高的百分比
///
/// 尺寸解析（[SizeSpec] → 像素）与外间距（[MarginSpec] → [EdgeInsets]）
/// 委托给 [RelativeLayoutEngine] 的静态工具，确保与相对布局行为一致。
///
/// 与 [RelativeLayoutRenderObject] 不同，本类不做分组/排序，仅按 x/y
/// 坐标定位；适合需要精确像素控制的场景（PPT 式自由布局）。
class AbsoluteLayoutRenderObject extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, LayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, LayoutParentData> {
  /// 父组件未给尺寸时的默认宽度。
  static const double _defaultWidth = 400;

  /// 父组件未给尺寸时的默认高度。
  static const double _defaultHeight = 400;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! LayoutParentData) {
      child.parentData = LayoutParentData();
    }
  }

  @override
  void performLayout() {
    // 1. 确定本 RenderObject 自身尺寸。
    final w = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : _defaultWidth;
    final h = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : _defaultHeight;
    size = constraints.constrain(Size(w, h));

    // 2. 布局每个子组件并按 x/y 定位。
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData as LayoutParentData;
      final layout = pd.layout;
      if (layout != null && layout.mode == LayoutMode.absolute) {
        // 解析尺寸（应用 clamp）。
        final childW =
            RelativeLayoutEngine.resolveSize(layout.width, size.width);
        final childH =
            RelativeLayoutEngine.resolveSize(layout.height, size.height);
        final margin =
            RelativeLayoutEngine.resolveMargin(layout.margin, size);
        // 子组件实际可用尺寸 = 配置尺寸 - 两侧外间距（不小于 0）。
        final innerW =
            (childW - margin.horizontal).clamp(0.0, double.infinity);
        final innerH =
            (childH - margin.vertical).clamp(0.0, double.infinity);
        child.layout(
          BoxConstraints.tightFor(width: innerW, height: innerH),
          parentUsesSize: true,
        );

        // 解析 x/y 坐标（支持 px 与 %）。
        final x = layout.x != null
            ? RelativeLayoutEngine.resolvePosition(layout.x!, size.width)
            : margin.left;
        final y = layout.y != null
            ? RelativeLayoutEngine.resolvePosition(layout.y!, size.height)
            : margin.top;

        pd.offset = Offset(x + margin.left, y + margin.top);
      } else if (layout != null && layout.mode == LayoutMode.relative) {
        // 相对布局子组件在绝对布局容器中：退化为左上角定位（避免布局崩溃）。
        final childW =
            RelativeLayoutEngine.resolveSize(layout.width, size.width);
        final childH =
            RelativeLayoutEngine.resolveSize(layout.height, size.height);
        final margin =
            RelativeLayoutEngine.resolveMargin(layout.margin, size);
        final innerW =
            (childW - margin.horizontal).clamp(0.0, double.infinity);
        final innerH =
            (childH - margin.vertical).clamp(0.0, double.infinity);
        child.layout(
          BoxConstraints.tightFor(width: innerW, height: innerH),
          parentUsesSize: true,
        );
        pd.offset = Offset(margin.left, margin.top);
      } else {
        // 无 LayoutConfig：退化为 loose 布局，定位在 (0,0)。
        child.layout(constraints.loosen(), parentUsesSize: true);
        pd.offset = Offset.zero;
      }
      child = pd.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
