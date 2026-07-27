import 'package:flutter/material.dart';

import '../../../data/models/ui_tree.dart';

/// 9宫格各 cell 的中文名。
const Map<int, String> kGrid9CellName = {
  1: '左上',
  2: '上中',
  3: '右上',
  4: '左中',
  5: '中心',
  6: '右中',
  7: '左下',
  8: '下中',
  9: '右下',
};

/// 9宫格各 cell 的堆叠方向说明。
///
/// 与 `RelativeLayoutEngine` 的排序/对齐逻辑一一对应，作为用户可见的说明文字。
const Map<int, String> kGrid9CellStackingDescription = {
  1: '从上往下，水平靠左，垂直从上开始',
  2: '从上往下，水平居中，垂直从上开始',
  3: '从上往下，水平靠右，垂直从上开始',
  4: '从左往右，水平从左开始，垂直上下居中',
  5: '从中心往上或往下（取决于 distance.edge），水平居中',
  6: '从右往左，水平从右开始，垂直上下居中',
  7: '从下往上，水平靠左，垂直从下开始',
  8: '从下往上，水平居中，垂直从下开始',
  9: '从下往上，水平靠右，垂直从下开始',
};

/// 9宫格布局选择器：3×3 可点击网格，用于为相对布局组件选择归属 cell。
///
/// 布局：
/// ```
/// 1=左上  2=上中  3=右上
/// 4=左中  5=中心  6=右中
/// 7=左下  8=下中  9=右下
/// ```
///
/// 选中态高亮当前 [selectedCell]；悬停 / 长按某格显示该格的堆叠方向说明
/// tooltip（[kGrid9CellStackingDescription]）。
class Grid9Selector extends StatelessWidget {
  const Grid9Selector({
    super.key,
    required this.selectedCell,
    required this.onCellSelected,
    this.cellSize = 36.0,
    this.spacing = 4.0,
  });

  /// 当前选中的 cell（1-9）；null 表示未选中。
  final int? selectedCell;

  /// 点击 cell 的回调。
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
                _Grid9Cell(
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

/// 单个宫格。
class _Grid9Cell extends StatelessWidget {
  const _Grid9Cell({
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
    final name = kGrid9CellName[cell] ?? '';
    final desc = kGrid9CellStackingDescription[cell] ?? '';
    final tooltip = '$cell · $name\n$desc';
    return Tooltip(
      message: tooltip,
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
            child: Center(
              child: Text(
                '$cell',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
