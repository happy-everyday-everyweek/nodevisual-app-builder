import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ui_tree.dart';
import '../ui_editor_providers.dart';
import 'relative_layout_engine.dart';

/// 长按移动模式处理器：长按子组件进入"移动模式"，拖动到新位置后
/// 松手提交布局变更。
///
/// 移动模式的行为取决于**组件自身的布局方式**（组件级，非全局/页面级）：
/// - **绝对布局**：PPT 式自由移动，根据落点更新 [LayoutConfig.x] /
///   [LayoutConfig.y] 坐标（保留原单位：px 直接传像素，% 换算为百分比）。
/// - **相对布局**：拖动调整组件在堆叠队列中的顺序，通过 [UiMutator.reorderInCell]
///   更新父组件 `children` 列表顺序。落点相对同 cell 兄弟的位置决定插入位置。
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

  /// 父 [LayoutContainer] 的 [GlobalKey]，用于坐标转换与兄弟位置收集。
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

  /// 根据拖动落点提交布局变更。
  ///
  /// 行为由组件自身的 [LayoutConfig.mode] 决定：
  /// - [LayoutMode.absolute]：自由移动，更新 x/y
  /// - [LayoutMode.relative]：调整堆叠队列顺序（reorderInCell）
  void _commitMove(Offset localPosition) {
    final parentLocal = _toParentLocal(localPosition);
    if (parentLocal == null) return;

    final mutator = ref.read(uiMutatorProvider.notifier);
    final found = mutator.findNode(widget.nodeId);
    if (found == null) return;
    final node = found.node;
    final layout = node.layout;
    if (layout == null) return;

    if (layout.mode == LayoutMode.absolute) {
      _commitAbsoluteMove(layout, parentLocal);
    } else {
      _commitRelativeReorder(node, parentLocal);
    }
  }

  /// 绝对布局：用落点更新 x/y（保留原单位），PPT 式自由移动。
  void _commitAbsoluteMove(LayoutConfig layout, Offset parentLocal) {
    final parentSize = widget.parentSize;
    final clampedX = parentLocal.dx.clamp(0.0, parentSize.width);
    final clampedY = parentLocal.dy.clamp(0.0, parentSize.height);

    final xUnit = layout.x?.unit ?? SizeUnit.px;
    final yUnit = layout.y?.unit ?? SizeUnit.px;
    final newPos = PositionSpec(
      value: xUnit == SizeUnit.percent
          ? (parentSize.width > 0 ? (clampedX / parentSize.width) * 100 : 0)
          : clampedX,
      unit: xUnit,
    );
    final newY = PositionSpec(
      value: yUnit == SizeUnit.percent
          ? (parentSize.height > 0 ? (clampedY / parentSize.height) * 100 : 0)
          : clampedY,
      unit: yUnit,
    );
    final newLayout = layout.copyWith(x: newPos, y: newY);
    ref.read(uiMutatorProvider.notifier).updateLayout(widget.nodeId, newLayout);
  }

  /// 相对布局：根据落点在堆叠队列中的位置，调用 [UiMutator.reorderInCell]
  /// 调整组件在父组件 `children` 列表中的顺序。
  ///
  /// 算法：
  /// 1. 收集同 cell 兄弟节点的渲染位置（通过遍历父容器 widget 树）
  /// 2. 按堆叠轴（cell 4/6 水平，其他垂直）排序兄弟节点
  /// 3. 根据落点在兄弟中心位置中的插入点计算新 index
  /// 4. 映射到 `children` 列表 index 并调用 `reorderInCell`
  void _commitRelativeReorder(UiNode node, Offset parentLocal) {
    final mutator = ref.read(uiMutatorProvider.notifier);
    final found = mutator.findNode(node.id);
    if (found == null || found.parent == null) return;
    final parent = found.parent!;
    final cell =
        node.layout?.cell?.cell ?? RelativeLayoutEngine.defaultCell;

    // 同 cell 的兄弟节点（按 children 列表顺序，含拖动节点）
    final sameCellSiblings = <UiNode>[];
    for (final c in parent.children) {
      final l = c.layout;
      if (l != null &&
          l.mode == LayoutMode.relative &&
          (l.cell?.cell ?? RelativeLayoutEngine.defaultCell) == cell) {
        sameCellSiblings.add(c);
      }
    }
    if (sameCellSiblings.length <= 1) return;

    // 收集同 parent 的兄弟节点渲染位置
    final positions = _collectSiblingPositions();
    if (positions.isEmpty) return;

    // 堆叠轴：cell 4/6 = 水平；其他 = 垂直
    final isVertical = cell != 4 && cell != 6;

    // 按视觉位置排序兄弟节点（排除拖动节点）
    final others = sameCellSiblings.where((s) => s.id != node.id).toList();
    others.sort((a, b) {
      final pa = positions[a.id];
      final pb = positions[b.id];
      if (pa == null || pb == null) return 0;
      if (isVertical) {
        return pa.$1.dy.compareTo(pb.$1.dy);
      }
      return pa.$1.dx.compareTo(pb.$1.dx);
    });

    // 落点沿堆叠轴的坐标
    final dropAlong = isVertical ? parentLocal.dy : parentLocal.dx;

    // 找到插入位置（在 others 列表中的 index）
    // 若落点在某兄弟中心之前，则插入到该兄弟前面
    int insertIndex = others.length; // 默认插到最后
    for (var i = 0; i < others.length; i++) {
      final pos = positions[others[i].id];
      if (pos == null) continue;
      final center = isVertical
          ? pos.$1.dy + pos.$2.height / 2
          : pos.$1.dx + pos.$2.width / 2;
      if (dropAlong < center) {
        insertIndex = i;
        break;
      }
    }

    // 计算在 children 列表中的目标 index
    final oldIndex = parent.children.indexWhere((c) => c.id == node.id);
    if (oldIndex < 0) return;

    int newIndex;
    if (insertIndex == others.length) {
      // 插入到最后一个 same-cell sibling 之后
      final lastSibling = others.last;
      final lastIdx =
          parent.children.indexWhere((c) => c.id == lastSibling.id);
      newIndex = oldIndex < lastIdx ? lastIdx : lastIdx + 1;
    } else {
      // 插入到 others[insertIndex] 之前
      final targetSibling = others[insertIndex];
      final targetIdx =
          parent.children.indexWhere((c) => c.id == targetSibling.id);
      newIndex = oldIndex < targetIdx ? targetIdx - 1 : targetIdx;
    }

    if (newIndex == oldIndex) return;
    mutator.reorderInCell(node.id, newIndex);
  }

  /// 遍历父容器的 widget 树，收集同 parent 的 [MoveModeHandler] 兄弟位置。
  ///
  /// 返回 `nodeId → (相对父容器的左上角坐标, 尺寸)` 映射。
  /// 仅收集 [MoveModeHandler.parentKey] 与本 handler 相同的节点（即同父容器
  /// 的直接子组件），不递归进入嵌套容器的子组件。
  Map<String, (Offset, Size)> _collectSiblingPositions() {
    final parentCtx = widget.parentKey.currentContext;
    if (parentCtx == null) return const {};
    final parentBox = parentCtx.findRenderObject();
    if (parentBox is! RenderBox) return const {};

    final positions = <String, (Offset, Size)>{};
    void visit(Element element) {
      if (element.widget is MoveModeHandler) {
        final handler = element.widget as MoveModeHandler;
        // 仅收集同父容器的兄弟（过滤嵌套容器的子组件）
        if (handler.parentKey == widget.parentKey) {
          final ro = element.findRenderObject();
          if (ro is RenderBox && ro.hasSize) {
            final globalPos = ro.localToGlobal(Offset.zero);
            final localPos = parentBox.globalToLocal(globalPos);
            positions[handler.nodeId] = (localPos, ro.size);
          }
        }
        // 不递归进入 MoveModeHandler（其子树是组件内容，非兄弟）
        return;
      }
      element.visitChildElements(visit);
    }

    (parentCtx as Element).visitChildElements(visit);
    return positions;
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
}
