import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../data/models/ui_tree.dart';

/// 9宫格相对布局渲染引擎：纯函数实现分组、排序、定位算法。
///
/// 本类仅依赖 dart:ui 几何类型与 [EdgeInsets]，不耦合 RenderObject，
/// 便于单测。真正的渲染由 [RelativeLayoutRenderObject] 调用本引擎完成。
///
/// 相对布局无"距边距离"概念，cell 决定对齐与排列方式：
/// - 列决定水平对齐：1/4/7=左对齐，2/5/8=居中，3/6/9=右对齐
/// - 行决定排列方向：
///   - cell 1/2/3（第一行）：从上往下，垂直从顶部开始
///   - cell 4（左中）：从左往右；cell 6（右中）：从右往左
///   - cell 5（中心）：从中心向下堆叠
///   - cell 7/8/9（第三行）：从下往上，垂直从底部开始
class RelativeLayoutEngine {
  RelativeLayoutEngine._();

  /// 默认 cell（未指定时归 2 号=上中）。
  static const int defaultCell = 2;

  /// 将子组件按 [LayoutConfig.cell] 分组到 9 个队列。
  ///
  /// 仅处理 [LayoutMode.relative] 模式且 [LayoutConfig.cell] 非空的子组件。
  /// 未指定 cell 的相对组件归入 [defaultCell]（2 号=上中）。
  static Map<int, List<UiNode>> groupChildrenByCell(
    List<UiNode> children,
  ) {
    final groups = <int, List<UiNode>>{};
    for (final child in children) {
      final layout = child.layout;
      if (layout == null || layout.mode != LayoutMode.relative) continue;
      final cell = layout.cell?.cell ?? defaultCell;
      groups.putIfAbsent(cell, () => []).add(child);
    }
    return groups;
  }

  /// 返回 cell 内的堆叠队列（保持 `children` 列表顺序）。
  ///
  /// 队列顺序由父组件 `children` 列表顺序决定，用户通过长按移动模式
  /// （`MoveModeHandler`）拖动组件来调整顺序。
  static List<UiNode> sortCellQueue(int cell, List<UiNode> children) {
    return List<UiNode>.of(children);
  }

  // ---- 单位解析工具（供 RenderObject 复用）----

  /// 解析 [PositionSpec] 为像素值。
  static double resolvePosition(PositionSpec spec, double parentExtent) {
    switch (spec.unit) {
      case SizeUnit.px:
        return spec.value;
      case SizeUnit.percent:
        return parentExtent * (spec.value / 100);
    }
  }

  /// 解析 [SizeSpec] 为像素值，应用 minPx/maxPx clamp（仅 percent 时生效）。
  static double resolveSize(SizeSpec spec, double parentExtent) {
    switch (spec.unit) {
      case SizeUnit.px:
        return spec.value;
      case SizeUnit.percent:
        var v = parentExtent * (spec.value / 100);
        if (spec.minPx != null) {
          v = math.max(v, spec.minPx!);
        }
        if (spec.maxPx != null) {
          v = math.min(v, spec.maxPx!);
        }
        return v;
    }
  }

  /// 解析 [EdgeValue] 为像素值。
  static double resolveEdge(EdgeValue edge, double parentExtent) {
    switch (edge.unit) {
      case SizeUnit.px:
        return edge.value;
      case SizeUnit.percent:
        return parentExtent * (edge.value / 100);
    }
  }

  /// 解析 4 方向外间距为像素 [EdgeInsets]。
  static EdgeInsets resolveMargin(MarginSpec margin, Size parentSize) {
    return EdgeInsets.fromLTRB(
      resolveEdge(margin.left, parentSize.width),
      resolveEdge(margin.top, parentSize.height),
      resolveEdge(margin.right, parentSize.width),
      resolveEdge(margin.bottom, parentSize.height),
    );
  }

  // ---- 几何定位算法 ----

  /// 单个 cell 内子组件的定位结果。
  static List<CellPlacement> layoutCell({
    required int cell,
    required List<UiNode> children,
    required Size parentSize,
    required Map<UiNode, Size> childSizes,
  }) {
    if (children.isEmpty) return const [];

    final queue = sortCellQueue(cell, children);

    // 水平对齐方式：0=left, 0.5=center, 1=right
    final double hAlign;
    switch (cell) {
      case 1:
      case 4:
      case 7:
        hAlign = 0; // 靠左
        break;
      case 2:
      case 5:
      case 8:
        hAlign = 0.5; // 居中
        break;
      case 3:
      case 6:
      case 9:
        hAlign = 1; // 靠右
        break;
      default:
        hAlign = 0.5;
        break;
    }

    // 垂直对齐方式：0=top, 0.5=center, 1=bottom
    final double vAlign;
    switch (cell) {
      case 1:
      case 2:
      case 3:
        vAlign = 0; // 顶部
        break;
      case 4:
      case 5:
      case 6:
        vAlign = 0.5; // 中部
        break;
      case 7:
      case 8:
      case 9:
        vAlign = 1; // 底部
        break;
      default:
        vAlign = 0.5;
        break;
    }

    final placements = <CellPlacement>[];

    // 垂直堆叠方向（top→down / bottom→up / 中心向上向下）
    // - cell 1/2/3：从顶部往下堆叠
    // - cell 7/8/9：从底部往上堆叠
    // - cell 4/6：水平堆叠（不走此分支）
    // - cell 5：根据 distance.edge 决定向上/向下
    switch (cell) {
      case 1:
      case 2:
      case 3:
        _stackVerticalTopDown(
          queue: queue,
          parentSize: parentSize,
          childSizes: childSizes,
          hAlign: hAlign,
          placements: placements,
        );
        break;
      case 7:
      case 8:
      case 9:
        _stackVerticalBottomUp(
          queue: queue,
          parentSize: parentSize,
          childSizes: childSizes,
          hAlign: hAlign,
          placements: placements,
        );
        break;
      case 4:
        _stackHorizontalLeftToRight(
          queue: queue,
          parentSize: parentSize,
          childSizes: childSizes,
          vAlign: vAlign,
          placements: placements,
        );
        break;
      case 6:
        _stackHorizontalRightToLeft(
          queue: queue,
          parentSize: parentSize,
          childSizes: childSizes,
          vAlign: vAlign,
          placements: placements,
        );
        break;
      case 5:
        _stackCenterCell(
          queue: queue,
          parentSize: parentSize,
          childSizes: childSizes,
          placements: placements,
        );
        break;
    }

    return placements;
  }

  /// 从顶部往下堆叠（cell 1/2/3）。
  static void _stackVerticalTopDown({
    required List<UiNode> queue,
    required Size parentSize,
    required Map<UiNode, Size> childSizes,
    required double hAlign,
    required List<CellPlacement> placements,
  }) {
    var cursorY = 0.0;
    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      final size = childSizes[node] ?? Size.zero;
      final margin = node.layout?.margin ?? const MarginSpec();
      final edgeInsets = resolveMargin(margin, parentSize);
      // 第一个组件从 margin.top 开始；后续组件紧接前一个堆叠。
      if (i == 0) {
        cursorY = edgeInsets.top;
      }
      final x = _alignHorizontal(
        hAlign: hAlign,
        childWidth: size.width,
        parentWidth: parentSize.width,
        margin: edgeInsets,
      );
      placements.add(CellPlacement(node: node, offset: Offset(x, cursorY)));
      cursorY += size.height + edgeInsets.bottom;
      // 后续组件的 margin.top 也累加（保证间距）。
      if (i < queue.length - 1) {
        cursorY += edgeInsets.top;
      }
    }
  }

  /// 从底部往上堆叠（cell 7/8/9）。
  static void _stackVerticalBottomUp({
    required List<UiNode> queue,
    required Size parentSize,
    required Map<UiNode, Size> childSizes,
    required double hAlign,
    required List<CellPlacement> placements,
  }) {
    var cursorY = parentSize.height;
    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      final size = childSizes[node] ?? Size.zero;
      final margin = node.layout?.margin ?? const MarginSpec();
      final edgeInsets = resolveMargin(margin, parentSize);
      if (i == 0) {
        cursorY = parentSize.height - edgeInsets.bottom - size.height;
      } else {
        cursorY -= size.height + edgeInsets.top;
      }
      final x = _alignHorizontal(
        hAlign: hAlign,
        childWidth: size.width,
        parentWidth: parentSize.width,
        margin: edgeInsets,
      );
      placements.add(CellPlacement(node: node, offset: Offset(x, cursorY)));
      // 后续组件紧贴上一个的上方（无额外间距，外间距已计入）。
      if (i < queue.length - 1) {
        cursorY -= edgeInsets.bottom;
      }
    }
  }

  /// 从左往右堆叠（cell 4）。
  static void _stackHorizontalLeftToRight({
    required List<UiNode> queue,
    required Size parentSize,
    required Map<UiNode, Size> childSizes,
    required double vAlign,
    required List<CellPlacement> placements,
  }) {
    var cursorX = 0.0;
    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      final size = childSizes[node] ?? Size.zero;
      final margin = node.layout?.margin ?? const MarginSpec();
      final edgeInsets = resolveMargin(margin, parentSize);
      if (i == 0) {
        cursorX = edgeInsets.left;
      }
      final y = _alignVertical(
        vAlign: vAlign,
        childHeight: size.height,
        parentHeight: parentSize.height,
        margin: edgeInsets,
      );
      placements.add(CellPlacement(node: node, offset: Offset(cursorX, y)));
      cursorX += size.width + edgeInsets.right;
      if (i < queue.length - 1) {
        cursorX += edgeInsets.left;
      }
    }
  }

  /// 从右往左堆叠（cell 6）。
  static void _stackHorizontalRightToLeft({
    required List<UiNode> queue,
    required Size parentSize,
    required Map<UiNode, Size> childSizes,
    required double vAlign,
    required List<CellPlacement> placements,
  }) {
    var cursorX = parentSize.width;
    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      final size = childSizes[node] ?? Size.zero;
      final margin = node.layout?.margin ?? const MarginSpec();
      final edgeInsets = resolveMargin(margin, parentSize);
      if (i == 0) {
        cursorX = parentSize.width - edgeInsets.right - size.width;
      } else {
        cursorX -= size.width + edgeInsets.left;
      }
      final y = _alignVertical(
        vAlign: vAlign,
        childHeight: size.height,
        parentHeight: parentSize.height,
        margin: edgeInsets,
      );
      placements.add(CellPlacement(node: node, offset: Offset(cursorX, y)));
      if (i < queue.length - 1) {
        cursorX -= edgeInsets.right;
      }
    }
  }

  /// 中心格（cell 5）：从中心向下堆叠。
  ///
  /// 第一个组件从父容器垂直中心开始，后续组件紧接下方。
  static void _stackCenterCell({
    required List<UiNode> queue,
    required Size parentSize,
    required Map<UiNode, Size> childSizes,
    required List<CellPlacement> placements,
  }) {
    final centerOffset = parentSize.height / 2;
    var cursorY = centerOffset;
    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      final size = childSizes[node] ?? Size.zero;
      final margin = node.layout?.margin ?? const MarginSpec();
      final edgeInsets = resolveMargin(margin, parentSize);
      if (i == 0) {
        cursorY += edgeInsets.top;
      }
      final x = (parentSize.width - size.width) / 2;
      placements.add(CellPlacement(node: node, offset: Offset(x, cursorY)));
      cursorY += size.height + edgeInsets.bottom;
      if (i < queue.length - 1) {
        cursorY += edgeInsets.top;
      }
    }
  }

  /// 水平对齐计算（返回 x 坐标）。
  static double _alignHorizontal({
    required double hAlign,
    required double childWidth,
    required double parentWidth,
    required EdgeInsets margin,
  }) {
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
  static double _alignVertical({
    required double vAlign,
    required double childHeight,
    required double parentHeight,
    required EdgeInsets margin,
  }) {
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
}

/// 单个组件在某 cell 内的定位结果。
class CellPlacement {
  const CellPlacement({required this.node, required this.offset});

  final UiNode node;
  final Offset offset;
}
