import 'package:flutter/rendering.dart';

import '../../../data/models/ui_tree.dart';
import 'relative_layout_engine.dart';

/// 布局父数据：持有子组件的 [LayoutConfig]，供 [RelativeLayoutRenderObject]
/// 与 [AbsoluteLayoutRenderObject] 在 layout/paint 时读取。
///
/// 通过 [LayoutChild] ParentDataWidget 注入；详见 `layout_container.dart`。
class LayoutParentData extends ContainerBoxParentData<RenderBox> {
  LayoutConfig? layout;
}

/// 相对布局 RenderObject：按 9 宫格分组、排序、定位子组件。
///
/// 使用 [RelativeLayoutEngine] 的静态算法完成位置计算：
/// - 按 [LayoutConfig.cell] 分 9 个队列
/// - 队列保持父组件 `children` 列表顺序（用户通过移动模式调整顺序）
/// - 按 cell 的堆叠方向（上→下 / 下→上 / 左→右 / 右→左 / 中心向下）定位
///
/// 尺寸解析（[SizeSpec] → 像素）与外间距（[MarginSpec] → [EdgeInsets]）
/// 委托给 [RelativeLayoutEngine] 的静态工具，确保与引擎行为一致。
///
/// **尺寸 clamp**：当 [SizeSpec.unit] == [SizeUnit.percent] 时，
/// 用 [SizeSpec.minPx] / [SizeSpec.maxPx] 限制换算后的像素值范围。
///
/// **外间距**：4 方向独立（[MarginSpec.top/bottom/left/right]），
/// 各方向独立解析为像素（px 或 %），从子组件占据的空间中扣除。
class RelativeLayoutRenderObject extends RenderBox
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

    // 2. 布局每个子组件，记录其尺寸。
    final childSizes = <RenderBox, Size>{};
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData as LayoutParentData;
      final layout = pd.layout;
      if (layout != null) {
        final childW =
            RelativeLayoutEngine.resolveSize(layout.width, size.width);
        final childH =
            RelativeLayoutEngine.resolveSize(layout.height, size.height);
        final margin =
            RelativeLayoutEngine.resolveMargin(layout.margin, size);
        // 子组件实际可用尺寸 = 配置尺寸 - 两侧外间距（不小于 0）。
        final innerW = (childW - margin.horizontal).clamp(0.0, double.infinity);
        final innerH = (childH - margin.vertical).clamp(0.0, double.infinity);
        child.layout(
          BoxConstraints.tightFor(width: innerW, height: innerH),
          parentUsesSize: true,
        );
        childSizes[child] = child.size;
      } else {
        // 无 LayoutConfig 时退化为 loose 布局。
        child.layout(constraints.loosen(), parentUsesSize: true);
        childSizes[child] = child.size;
      }
      child = pd.nextSibling;
    }

    // 3. 按 cell 分组（仅 relative 模式）。
    final groups = <int, List<RenderBox>>{};
    child = firstChild;
    while (child != null) {
      final pd = child.parentData as LayoutParentData;
      final layout = pd.layout;
      if (layout != null && layout.mode == LayoutMode.relative) {
        final cell = layout.cell?.cell ?? RelativeLayoutEngine.defaultCell;
        groups.putIfAbsent(cell, () => []).add(child);
      }
      child = pd.nextSibling;
    }

    // 4. 每个 cell 内按 children 列表顺序定位（不按 distance 排序）。
    groups.forEach((cell, children) {
      _positionCell(cell, children, childSizes, size);
    });
  }

  /// 为指定 cell 的子组件计算并设置 [LayoutParentData.offset]。
  void _positionCell(
    int cell,
    List<RenderBox> children,
    Map<RenderBox, Size> childSizes,
    Size parentSize,
  ) {
    if (children.isEmpty) return;

    // 水平对齐：0=left, 0.5=center, 1=right
    final double hAlign;
    switch (cell) {
      case 1:
      case 4:
      case 7:
        hAlign = 0;
        break;
      case 2:
      case 5:
      case 8:
        hAlign = 0.5;
        break;
      case 3:
      case 6:
      case 9:
        hAlign = 1;
        break;
      default:
        hAlign = 0.5;
        break;
    }

    // 垂直对齐：0=top, 0.5=center, 1=bottom
    final double vAlign;
    switch (cell) {
      case 1:
      case 2:
      case 3:
        vAlign = 0;
        break;
      case 4:
      case 5:
      case 6:
        vAlign = 0.5;
        break;
      case 7:
      case 8:
      case 9:
        vAlign = 1;
        break;
      default:
        vAlign = 0.5;
        break;
    }

    switch (cell) {
      case 1:
      case 2:
      case 3:
        _stackVerticalTopDown(
          children,
          childSizes,
          parentSize,
          hAlign,
        );
        break;
      case 7:
      case 8:
      case 9:
        _stackVerticalBottomUp(
          children,
          childSizes,
          parentSize,
          hAlign,
        );
        break;
      case 4:
        _stackHorizontalLeftToRight(
          children,
          childSizes,
          parentSize,
          vAlign,
        );
        break;
      case 6:
        _stackHorizontalRightToLeft(
          children,
          childSizes,
          parentSize,
          vAlign,
        );
        break;
      case 5:
        _stackCenterCell(children, childSizes, parentSize);
        break;
    }
  }

  /// 从顶部往下堆叠（cell 1/2/3）。
  void _stackVerticalTopDown(
    List<RenderBox> children,
    Map<RenderBox, Size> childSizes,
    Size parentSize,
    double hAlign,
  ) {
    var cursorY = 0.0;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final size = childSizes[child] ?? Size.zero;
      final layout = (child.parentData as LayoutParentData).layout;
      final margin = RelativeLayoutEngine.resolveMargin(
        layout?.margin ?? const MarginSpec(),
        parentSize,
      );
      if (i == 0) {
        cursorY = margin.top;
      }
      final x = _alignHorizontal(hAlign, size.width, parentSize.width, margin);
      (child.parentData as LayoutParentData).offset = Offset(x, cursorY);
      cursorY += size.height + margin.bottom;
      if (i < children.length - 1) {
        cursorY += margin.top;
      }
    }
  }

  /// 从底部往上堆叠（cell 7/8/9）。
  void _stackVerticalBottomUp(
    List<RenderBox> children,
    Map<RenderBox, Size> childSizes,
    Size parentSize,
    double hAlign,
  ) {
    var cursorY = parentSize.height;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final size = childSizes[child] ?? Size.zero;
      final layout = (child.parentData as LayoutParentData).layout;
      final margin = RelativeLayoutEngine.resolveMargin(
        layout?.margin ?? const MarginSpec(),
        parentSize,
      );
      if (i == 0) {
        cursorY = parentSize.height - margin.bottom - size.height;
      } else {
        cursorY -= size.height + margin.top;
      }
      final x = _alignHorizontal(hAlign, size.width, parentSize.width, margin);
      (child.parentData as LayoutParentData).offset = Offset(x, cursorY);
      if (i < children.length - 1) {
        cursorY -= margin.bottom;
      }
    }
  }

  /// 从左往右堆叠（cell 4）。
  void _stackHorizontalLeftToRight(
    List<RenderBox> children,
    Map<RenderBox, Size> childSizes,
    Size parentSize,
    double vAlign,
  ) {
    var cursorX = 0.0;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final size = childSizes[child] ?? Size.zero;
      final layout = (child.parentData as LayoutParentData).layout;
      final margin = RelativeLayoutEngine.resolveMargin(
        layout?.margin ?? const MarginSpec(),
        parentSize,
      );
      if (i == 0) {
        cursorX = margin.left;
      }
      final y = _alignVertical(vAlign, size.height, parentSize.height, margin);
      (child.parentData as LayoutParentData).offset = Offset(cursorX, y);
      cursorX += size.width + margin.right;
      if (i < children.length - 1) {
        cursorX += margin.left;
      }
    }
  }

  /// 从右往左堆叠（cell 6）。
  void _stackHorizontalRightToLeft(
    List<RenderBox> children,
    Map<RenderBox, Size> childSizes,
    Size parentSize,
    double vAlign,
  ) {
    var cursorX = parentSize.width;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final size = childSizes[child] ?? Size.zero;
      final layout = (child.parentData as LayoutParentData).layout;
      final margin = RelativeLayoutEngine.resolveMargin(
        layout?.margin ?? const MarginSpec(),
        parentSize,
      );
      if (i == 0) {
        cursorX = parentSize.width - margin.right - size.width;
      } else {
        cursorX -= size.width + margin.left;
      }
      final y = _alignVertical(vAlign, size.height, parentSize.height, margin);
      (child.parentData as LayoutParentData).offset = Offset(cursorX, y);
      if (i < children.length - 1) {
        cursorX -= margin.right;
      }
    }
  }

  /// 中心格（cell 5）：从中心向下堆叠。
  void _stackCenterCell(
    List<RenderBox> children,
    Map<RenderBox, Size> childSizes,
    Size parentSize,
  ) {
    final centerOffset = parentSize.height / 2;
    var cursorY = centerOffset;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final size = childSizes[child] ?? Size.zero;
      final layout = (child.parentData as LayoutParentData).layout;
      final margin = RelativeLayoutEngine.resolveMargin(
        layout?.margin ?? const MarginSpec(),
        parentSize,
      );
      if (i == 0) {
        cursorY += margin.top;
      }
      final x = (parentSize.width - size.width) / 2;
      (child.parentData as LayoutParentData).offset = Offset(x, cursorY);
      cursorY += size.height + margin.bottom;
      if (i < children.length - 1) {
        cursorY += margin.top;
      }
    }
  }

  /// 水平对齐计算（返回 x 坐标）。
  static double _alignHorizontal(
    double hAlign,
    double childWidth,
    double parentWidth,
    EdgeInsets margin,
  ) {
    switch (hAlign) {
      case 0:
        return margin.left;
      case 1:
        return parentWidth - childWidth - margin.right;
      case 0.5:
      default:
        return (parentWidth - childWidth) / 2 + (margin.left - margin.right);
    }
  }

  /// 垂直对齐计算（返回 y 坐标）。
  static double _alignVertical(
    double vAlign,
    double childHeight,
    double parentHeight,
    EdgeInsets margin,
  ) {
    switch (vAlign) {
      case 0:
        return margin.top;
      case 1:
        return parentHeight - childHeight - margin.bottom;
      case 0.5:
      default:
        return (parentHeight - childHeight) / 2 + (margin.top - margin.bottom);
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
