import 'package:flutter/material.dart';

import '../../data/models/node.dart';
import '../../data/models/port.dart';
import 'node_layout.dart';

/// 节点卡片渲染（双平面模型的"控制平面 + 数据输出展示"）。
///
/// 视觉布局（与 [NodeLayout] 常量对齐，端口位置由画布层反推）：
/// ```
/// ●  kind · name                <- 头部 (36px)，左侧入口端口
///        outName1            ●→ <- 控制流输出端口行 (24px each)
///        outName2            ●→
/// ─────────────────────────
/// result  [number]              <- 数据输出展示行 (20px each, 只读)
/// rows    [list]
/// ```
///
/// 动画：
/// - 出现：从 0.96 缩放 + 淡入（220ms，easeOutCubic），消失原路反向。
/// - 选中：边框宽度与阴影强度过渡（200ms），反向恢复。
class NodeCard extends StatefulWidget {
  const NodeCard({
    super.key,
    required this.node,
    required this.selected,
    this.onSelect,
    this.onOpenEditor,
    this.onDelete,
    this.onDragUpdate,
    this.onConnectionDragStart,
    this.onConnectionDragUpdate,
    this.onConnectionDragEnd,
    this.onConnectionDragCancel,
  });

  /// 节点数据。
  final Node node;

  /// 是否选中。
  final bool selected;

  /// 长按选中回调。
  final VoidCallback? onSelect;

  /// 单击打开节点编辑页回调（数据平面入口）。
  final VoidCallback? onOpenEditor;

  /// 删除节点回调（通过节点详情菜单触发）。
  final VoidCallback? onDelete;

  /// 节点拖拽更新回调（[DragUpdateDetails] 来自内部 GestureDetector）。
  final ValueChanged<DragUpdateDetails>? onDragUpdate;

  /// 从某个控制流输出端口开始拖拽连线（参数：端口名）。
  final ValueChanged<String>? onConnectionDragStart;

  /// 拖拽连线过程中（参数：当前指针全局坐标）。
  final ValueChanged<Offset>? onConnectionDragUpdate;

  /// 拖拽连线结束（参数：当前指针全局坐标，可空）。
  final ValueChanged<Offset?>? onConnectionDragEnd;

  /// 拖拽连线取消。
  final VoidCallback? onConnectionDragCancel;

  @override
  State<NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<NodeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _appear;
  late final Animation<double> _appearAnim;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _appearAnim = CurvedAnimation(
      parent: _appear,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // 进入时正放；widget 销毁时（dispose）由框架自动移除，无需显式 reverse。
    _appear.forward();
  }

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  String get _displayName {
    final name = widget.node.params['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return widget.node.kind;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1.0).animate(_appearAnim),
      alignment: Alignment.center,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(_appearAnim),
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: NodeLayout.width,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.selected ? cs.primary : cs.outlineVariant,
                width: widget.selected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: widget.selected ? 0.10 : 0.04),
                  blurRadius: widget.selected ? 12 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 卡片主体：单击打开节点编辑页（同时选中）+ 长按选中 + 单指拖拽移动。
                // 端口在 Stack 上层，自身手势让位。
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onSelect?.call();
                    widget.onOpenEditor?.call();
                  },
                  onLongPress: widget.onSelect,
                  onPanUpdate: widget.onDragUpdate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(theme, cs),
                      for (var i = 0; i < widget.node.controlOutputs.length; i++)
                        _buildOutputRow(
                          theme,
                          cs,
                          widget.node.controlOutputs[i].name,
                        ),
                      if (widget.node.dataOutputs.isNotEmpty)
                        _buildDataSection(theme, cs),
                    ],
                  ),
                ),
                // 入口端口（左侧，头部中线）。
                Positioned(
                  left: -NodeLayout.portRadius,
                  top: NodeLayout.headerHeight / 2 - NodeLayout.portRadius,
                  child: _PortHit(
                    color: cs.primary,
                    onTap: widget.onSelect,
                    tooltip: '入口端口',
                  ),
                ),
                // 各控制流输出端口（右侧，对应行中线）。
                for (var i = 0; i < widget.node.controlOutputs.length; i++)
                  Positioned(
                    left: NodeLayout.width - NodeLayout.portRadius,
                    top: NodeLayout.headerHeight +
                        i * NodeLayout.outputRowHeight +
                        NodeLayout.outputRowHeight / 2 -
                        NodeLayout.portRadius,
                    child: _PortHit(
                      color: cs.onSurface,
                      onPanStart: widget.onConnectionDragStart != null
                          ? () => widget.onConnectionDragStart!(
                              widget.node.controlOutputs[i].name)
                          : null,
                      onPanUpdate: widget.onConnectionDragUpdate == null
                          ? null
                          : (details) => widget.onConnectionDragUpdate!(
                              details.globalPosition),
                      onPanEnd: widget.onConnectionDragEnd,
                      onPanCancel: widget.onConnectionDragCancel,
                      tooltip: '输出: ${widget.node.controlOutputs[i].name}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    return Container(
      height: NodeLayout.headerHeight,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(11),
          topRight: Radius.circular(11),
        ),
      ),
      child: Row(
        children: [
          Icon(_kindIcon(widget.node.kind), size: 14, color: cs.onSurface),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _displayName,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.node.kind,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(width: 4),
            // 触控目标 >= 28dp（节点内紧凑场景），用 IconButton 保证命中区
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                onPressed: widget.onDelete,
                icon: Icon(Icons.close, size: 14, color: cs.error),
                padding: EdgeInsets.zero,
                splashRadius: 16,
                tooltip: '删除节点',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOutputRow(
    ThemeData theme,
    ColorScheme cs,
    String name,
  ) {
    return Container(
      height: NodeLayout.outputRowHeight,
      padding: const EdgeInsets.only(left: 16, right: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSection(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final output in widget.node.dataOutputs)
            Container(
              height: NodeLayout.dataRowHeight,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.data_object,
                      size: 10, color: cs.onSurfaceVariant,),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      output.name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _TypeChip(type: output.type),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case 'variable_set':
      case 'variable_get':
        return Icons.label_outline;
      case 'arithmetic':
        return Icons.calculate_outlined;
      case 'logic':
        return Icons.account_tree_outlined;
      case 'string_op':
        return Icons.text_fields;
      case 'if':
        return Icons.call_split;
      case 'loop':
        return Icons.loop;
      case 'db_query':
      case 'db_insert':
      case 'db_update':
      case 'db_delete':
        return Icons.storage_outlined;
      case 'function_call':
        return Icons.functions;
      case 'plugin':
        return Icons.extension;
      default:
        return Icons.widgets_outlined;
    }
  }
}

/// 端口圆点 + 触控放大命中区。
///
/// 视觉圆点半径为 [NodeLayout.portRadius]，但命中区半径为
/// [NodeLayout.portHitRadius]（移动端触控友好）。
class _PortHit extends StatelessWidget {
  const _PortHit({
    required this.color,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.tooltip,
  });

  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onPanStart;
  final ValueChanged<DragUpdateDetails>? onPanUpdate;
  final ValueChanged<Offset?>? onPanEnd;
  final VoidCallback? onPanCancel;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    const hitSize = NodeLayout.portHitRadius * 2;
    final dot = Container(
      width: NodeLayout.portRadius * 2,
      height: NodeLayout.portRadius * 2,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
    final child = SizedBox(
      width: hitSize,
      height: hitSize,
      child: Center(child: dot),
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      onPanStart: onPanStart == null ? null : (_) => onPanStart!(),
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd == null
          ? null
          : (details) => onPanEnd!(details.globalPosition),
      onPanCancel: onPanCancel,
      child: tooltip == null
          ? child
          : Tooltip(message: tooltip!, child: child),
    );
  }
}

/// 数据输出类型小标签。
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final PortType type;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _typeColor(type, cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        type.toJson(),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontFamily: 'monospace',
          height: 1.2,
        ),
      ),
    );
  }

  Color _typeColor(PortType type, ColorScheme cs) {
    // 极简黑白灰：所有类型统一用 onSurfaceVariant，避免彩色噪点；
    // 通过文字标签区分，不靠颜色编码。
    return cs.onSurfaceVariant;
  }
}
