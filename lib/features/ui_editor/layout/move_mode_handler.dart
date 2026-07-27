import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ui_tree.dart';
import '../ui_editor_providers.dart';
import 'relative_layout_engine.dart';

/// 长按移动模式处理器：长按子组件进入"移动模式"，拖动到新位置后
/// 松手提交布局变更。
///
/// 专为 9 宫格布局系统设计：
/// - **绝对布局**：根据落点更新 [LayoutConfig.x] / [LayoutConfig.y] 坐标
///   （保留原单位：px 直接传像素，% 换算为百分比）。
/// - **相对布局**：根据落点判断新 [GridCell]（1-9），并用
///   [RelativeLayoutEngine.computeDistance] 计算距最近边的距离。
///
/// 拖动期间显示半透明指示器跟随手指；松手时提交变更并退出移动模式。
///
/// **坐标转换**：本 Widget 的手势回调给出的是相对自身的局部坐标。
/// 通过 [parentKey] 指向父 [LayoutContainer] 的 [GlobalKey]，在提交时把
/// 局部坐标转换为父容器相对坐标，确保 cell / distance / x-y 计算正确。
///
/// 用法：
/// ```dart
/// final parentKey = GlobalKey();
/// LayoutContainer(
///   key: parentKey,
///   mode: LayoutMode.relative,
///   children: [
///     MoveModeHandler(
///       nodeId: node.id,
///       parentKey: parentKey,
///       parentSize: canvasSize,
///       child: SomeWidget(),
///     ),
///   ],
/// )
/// ```
class MoveModeHandler extends ConsumerStatefulWidget {
  const MoveModeHandler({
    super.key,
    required this.nodeId,
    required this.parentKey,
    required this.parentSize,
    required this.child,
    this.enabled = true,
  });

  /// 被移动组件的节点 id。
  final String nodeId;

  /// 父 [LayoutContainer] 的 [GlobalKey]，用于坐标转换。
  final GlobalKey parentKey;

  /// 父容器的尺寸（用于计算相对坐标与限制落点范围）。
  final Size parentSize;

  /// 被包裹的子组件。
  final Widget child;

  /// 是否启用移动模式；false 时不响应长按。
  final bool enabled;

  @override
  ConsumerState<MoveModeHandler> createState() => _MoveModeHandlerState();
}

class _MoveModeHandlerState extends ConsumerState<MoveModeHandler> {
  /// 当前拖动位置（相对本 Widget）；null 表示未在移动模式。
  Offset? _dragPosition;

  bool get _isMoving => _dragPosition != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: widget.enabled ? _onMoveStart : null,
      onLongPressMoveUpdate: widget.enabled ? _onMoveUpdate : null,
      onLongPressEnd: widget.enabled ? _onMoveEnd : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_isMoving && _dragPosition != null)
            Positioned(
              left: _dragPosition!.dx,
              top: _dragPosition!.dy,
              child: IgnorePointer(
                child: Transform.translate(
                  offset: const Offset(-14, -14),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.onPrimary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.open_with,
                      size: 16,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onMoveStart(LongPressStartDetails details) {
    setState(() {
      _dragPosition = details.localPosition;
    });
  }

  void _onMoveUpdate(LongPressMoveUpdateDetails details) {
    setState(() {
      _dragPosition = details.localPosition;
    });
  }

  void _onMoveEnd(LongPressEndDetails details) {
    final localPosition = details.localPosition;
    _commitMove(localPosition);
    setState(() {
      _dragPosition = null;
    });
  }

  /// 根据拖动落点计算并提交新的 [LayoutConfig]。
  void _commitMove(Offset localPosition) {
    final parentLocal = _toParentLocal(localPosition);
    if (parentLocal == null) return;

    final mutator = ref.read(uiMutatorProvider.notifier);
    final found = mutator.findNode(widget.nodeId);
    if (found == null) return;
    final node = found.node;
    final layout = node.layout;
    if (layout == null) return;

    final parentSize = widget.parentSize;
    // 将落点限制在父容器范围内。
    final clampedX = parentLocal.dx.clamp(0.0, parentSize.width);
    final clampedY = parentLocal.dy.clamp(0.0, parentSize.height);

    final LayoutConfig newLayout;
    if (layout.mode == LayoutMode.absolute) {
      newLayout = _computeAbsoluteLayout(layout, clampedX, clampedY);
    } else {
      newLayout = _computeRelativeLayout(
        node,
        layout,
        clampedX,
        clampedY,
        parentSize,
      );
    }
    mutator.updateLayout(widget.nodeId, newLayout);
  }

  /// 把本 Widget 局部坐标转为父容器相对坐标。
  Offset? _toParentLocal(Offset localPosition) {
    final childBox = context.findRenderObject();
    if (childBox is! RenderBox) return null;
    final globalPos = childBox.localToGlobal(localPosition);

    final parentCtx = widget.parentKey.currentContext;
    if (parentCtx == null) return null;
    final parentBox = parentCtx.findRenderObject();
    if (parentBox is! RenderBox) return null;
    return parentBox.globalToLocal(globalPos);
  }

  /// 绝对布局：用落点更新 x/y（保留原单位）。
  LayoutConfig _computeAbsoluteLayout(
    LayoutConfig layout,
    double x,
    double y,
  ) {
    final xUnit = layout.x?.unit ?? SizeUnit.px;
    final yUnit = layout.y?.unit ?? SizeUnit.px;
    final parentSize = widget.parentSize;
    final newPos = PositionSpec(
      value: xUnit == SizeUnit.percent
          ? (parentSize.width > 0 ? (x / parentSize.width) * 100 : 0)
          : x,
      unit: xUnit,
    );
    final newY = PositionSpec(
      value: yUnit == SizeUnit.percent
          ? (parentSize.height > 0 ? (y / parentSize.height) * 100 : 0)
          : y,
      unit: yUnit,
    );
    return layout.copyWith(x: newPos, y: newY);
  }

  /// 相对布局：根据落点判断新 cell，并计算距最近边的距离。
  LayoutConfig _computeRelativeLayout(
    UiNode node,
    LayoutConfig layout,
    double x,
    double y,
    Size parentSize,
  ) {
    final cell = _computeCell(x, y, parentSize);
    // 用 computeDistance 需要一个带 x/y 的 layout 来定位组件矩形；
    // 这里临时构造一个 absolute layout 来复用引擎的最近边计算逻辑。
    final tempLayout = layout.copyWith(
      cell: GridCell(cell),
      x: PositionSpec(value: x, unit: SizeUnit.px),
      y: PositionSpec(value: y, unit: SizeUnit.px),
    );
    final tempNode = node.copyWith(layout: tempLayout);
    final parentRect = Rect.fromLTWH(
      0,
      0,
      parentSize.width,
      parentSize.height,
    );
    final distance = RelativeLayoutEngine.computeDistance(
      tempNode,
      parentRect,
    );
    return layout.copyWith(cell: GridCell(cell), distance: distance);
  }

  /// 根据落点在父容器中的相对位置计算所属 cell（1-9）。
  ///
  /// ```
  /// 1=左上  2=上中  3=右上
  /// 4=左中  5=中心  6=右中
  /// 7=左下  8=下中  9=右下
  /// ```
  static int _computeCell(double x, double y, Size parentSize) {
    if (parentSize.width <= 0 || parentSize.height <= 0) return 5;
    final relX = x / parentSize.width;
    final relY = y / parentSize.height;
    final col = relX < 1 / 3 ? 0 : (relX < 2 / 3 ? 1 : 2);
    final row = relY < 1 / 3 ? 0 : (relY < 2 / 3 ? 1 : 2);
    return row * 3 + col + 1;
  }
}
