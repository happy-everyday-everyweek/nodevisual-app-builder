import 'package:flutter/material.dart';

import '../../data/models/node.dart';
import '../../data/models/port.dart';
import 'node_layout.dart';

/// 编辑器交互模式。
enum NodeEditorMode {
  /// 指针：移动节点 / 平移画布，节点拖到屏幕边缘时画布自动跟随。
  pointer,

  /// 连线：点击起始节点 → 点击终止节点建立控制流连线。
  ///
  /// 连线仅代表执行顺序，与参数传递无关。多输出母节点（if / loop 等）的
  /// 输出端口已在 [GraphMutator.addWithBranches] 时自动连到对应的 `branch`
  /// 子节点，因此连线起点应点击子节点，母节点本身不能作为起点。
  connect,

  /// 添加：打开节点面板。
  add,
}

/// 节点卡片渲染（双平面模型的"控制平面 + 数据输出展示"）。
///
/// 视觉布局（与 [NodeLayout] 常量对齐）：
/// ```
///  kind · name                   <- 头部 (36px)
///        outName1                  <- 控制流输出行 (24px each)
///        outName2
/// ─────────────────────────
/// result  [number]                <- 数据输出展示行 (20px each, 只读)
/// rows    [list]
/// ```
///
/// 无端口圆点：连线交互由 [NodeEditorMode.connect] 模式下两步点击完成
/// （先点击起始节点，再点击终止节点）。连线仅表达执行顺序，不参与参数传递。
class NodeCard extends StatefulWidget {
  const NodeCard({
    super.key,
    required this.node,
    required this.selected,
    required this.mode,
    this.onSelect,
    this.onOpenEditor,
    this.onDelete,
    this.onDragUpdate,
    this.onConnectTap,
    this.isConnectionSource = false,
  });

  /// 节点数据。
  final Node node;

  /// 是否选中。
  final bool selected;

  /// 当前编辑器模式。
  final NodeEditorMode mode;

  /// 长按选中回调。
  final VoidCallback? onSelect;

  /// 单击打开节点编辑页回调（数据平面入口）。
  final VoidCallback? onOpenEditor;

  /// 删除节点回调。
  final VoidCallback? onDelete;

  /// 节点拖拽更新回调（指针模式下移动节点）。
  final ValueChanged<DragUpdateDetails>? onDragUpdate;

  /// 连线模式：点击该节点（参数：节点 id）。
  ///
  /// 由父组件决定是"作为起始节点选中"还是"作为终止节点建立连线"。
  /// 多输出母节点（if / loop 等）由父组件拦截并提示用户改点对应的子节点。
  final ValueChanged<String>? onConnectTap;

  /// 连线模式下是否为当前选中的起始节点（高亮）。
  final bool isConnectionSource;

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
    final isConnect = widget.mode == NodeEditorMode.connect;
    final isSource = widget.isConnectionSource;

    // 连线模式下：起始节点用 tertiary；其余用 outline（选中态用 primary）。
    final borderColor = isSource
        ? cs.tertiary
        : (widget.selected ? cs.primary : cs.outlineVariant);
    final borderWidth = isSource || widget.selected ? 1.5 : 1;

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
                color: borderColor,
                width: borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: widget.selected ? 0.10 : 0.04,),
                  blurRadius: widget.selected ? 12 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildBody(theme, cs, isConnect),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs, bool isConnect) {
    // 连线模式：单击作为起始或终止节点（两步点击式连线）。
    // 多输出母节点（if / loop 等）由父组件 onConnectTap 拦截并提示用户
    // 改点对应的 branch 子节点作为起点。
    if (isConnect) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onConnectTap == null
            ? null
            : () => widget.onConnectTap!(widget.node.id),
        child: _buildColumn(theme, cs),
      );
    }

    // 指针模式：单击打开编辑器 + 长按选中 + 拖拽移动。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onSelect?.call();
        widget.onOpenEditor?.call();
      },
      onLongPress: widget.onSelect,
      onPanUpdate: widget.onDragUpdate,
      child: _buildColumn(theme, cs),
    );
  }

  Widget _buildColumn(ThemeData theme, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(theme, cs),
        for (var i = 0; i < widget.node.controlOutputs.length; i++)
          _buildOutputRow(theme, cs, widget.node.controlOutputs[i].name),
        if (widget.node.dataOutputs.isNotEmpty)
          _buildDataSection(theme, cs),
      ],
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

  Widget _buildOutputRow(ThemeData theme, ColorScheme cs, String name) {
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
      case 'branch':
        return Icons.subdirectory_arrow_right;
      case 'function_input':
        return Icons.input;
      case 'function_output':
        return Icons.output;
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
      case 'plugin_clipboard':
        return Icons.content_copy;
      case 'plugin_haptic':
        return Icons.vibration;
      case 'plugin_share':
        return Icons.share;
      case 'code_run':
        return Icons.code;
      default:
        return Icons.widgets_outlined;
    }
  }
}

/// 数据输出类型小标签。
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final PortType type;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurfaceVariant;
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
}
