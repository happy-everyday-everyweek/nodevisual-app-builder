import 'package:flutter/material.dart';

import '../../../data/models/ui_tree.dart';

/// 相对布局各位置的对齐与排列说明（用户可见，不含数字编号）。
///
/// 列决定水平对齐：第一列=左对齐，第二列=居中，第三列=右对齐。
/// 行决定排列方向：第一行=从上往下，第二行=水平（左→右 / 右→左 / 中心），
/// 第三行=从下往上。
const Map<int, String> kRelativeCellDescription = {
  1: '左对齐 · 从上往下排列',
  2: '居中对齐 · 从上往下排列',
  3: '右对齐 · 从上往下排列',
  4: '左对齐 · 从左往右排列',
  5: '居中对齐 · 从中心向下排列',
  6: '右对齐 · 从右往左排列',
  7: '左对齐 · 从下往上排列',
  8: '居中对齐 · 从下往上排列',
  9: '右对齐 · 从下往上排列',
};

/// 相对布局位置选择器：3×3 可点击网格，为相对布局组件选择对齐与排列方式。
///
/// 每格用 3 个点表示该位置的对齐（列：左/中/右）与排列方向
/// （行：上→下 / 水平 / 下→上）。不标注数字编号，悬停 / 长按显示文字说明。
///
/// 布局：
/// ```
/// 左上  上中  右上
/// 左中  中心  右中
/// 左下  下中  右下
/// ```
class Grid9Selector extends StatelessWidget {
  const Grid9Selector({
    super.key,
    required this.selectedCell,
    required this.onCellSelected,
    this.cellSize = 40.0,
    this.spacing = 4.0,
  });

  /// 当前选中的位置（1-9）；null 表示未选中。
  final int? selectedCell;

  /// 点击格子的回调。
  final ValueChanged<GridCell> onCellSelected;

  /// 单个格子的尺寸。
  final double cellSize;

  /// 格子间距。
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int row = 0; row < 3; row++) ...[
          if (row > 0) SizedBox(height: spacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int col = 0; col < 3; col++) ...[
                if (col > 0) SizedBox(width: spacing),
                _RelativeCell(
                  cell: row * 3 + col + 1,
                  selected: selectedCell == row * 3 + col + 1,
                  size: cellSize,
                  onTap: () => onCellSelected(GridCell(row * 3 + col + 1)),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// 单个位置格：用 3 个点表示对齐与排列方式。
class _RelativeCell extends StatelessWidget {
  const _RelativeCell({
    required this.cell,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  final int cell;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final desc = kRelativeCellDescription[cell] ?? '';
    return Tooltip(
      message: desc,
      triggerMode: TooltipTriggerMode.longPress,
      waitDuration: const Duration(milliseconds: 200),
      showDuration: const Duration(seconds: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary
                  : cs.surfaceContainerHigh.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 1.5 : 0.75,
              ),
            ),
            child: CustomPaint(
              size: Size.square(size),
              painter: _CellDotsPainter(
                cell: cell,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 用 3 个点绘制各位置的对齐与排列方式。
///
/// - 行 1（cell 1/2/3）：3 点竖排（从上往下），水平对齐由列决定。
/// - 行 3（cell 7/8/9）：3 点竖排（从下往上），水平对齐由列决定。
/// - cell 4：3 点横排靠左；cell 6：3 点横排靠右。
/// - cell 5：3 点竖排居中（从中心向下）。
class _CellDotsPainter extends CustomPainter {
  _CellDotsPainter({required this.cell, required this.color});

  final int cell;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final dotR = size.width * 0.09;
    final paint = Paint()..color = color;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final gap = size.width * 0.22;

    // 水平对齐位置（列：1/4/7=左, 2/5/8=中, 3/6/9=右）
    final double hPos;
    switch (cell) {
      case 1:
      case 4:
      case 7:
        hPos = size.width * 0.3;
        break;
      case 3:
      case 6:
      case 9:
        hPos = size.width * 0.7;
        break;
      default:
        hPos = cx;
    }

    // 行 2（cell 4/5/6）：水平排列
    final isHorizontal = cell == 4 || cell == 6;

    if (isHorizontal) {
      // 3 点横排，垂直居中
      final baseX = cell == 4 ? size.width * 0.3 : size.width * 0.7;
      final dir = cell == 4 ? 1.0 : -1.0;
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(baseX + dir * gap * i, cy),
          dotR,
          paint,
        );
      }
    } else {
      // 3 点竖排，水平对齐由 hPos 决定
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(hPos, cy - gap + i * gap),
          dotR,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CellDotsPainter oldDelegate) =>
      oldDelegate.cell != cell || oldDelegate.color != color;
}
