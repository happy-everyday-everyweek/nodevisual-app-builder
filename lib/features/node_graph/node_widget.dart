import 'package:flutter/material.dart';

import '../../data/models/node.dart';
import 'node_kinds.dart';
import 'node_layout.dart';

/// 编辑器交互模式。
enum NodeEditorMode {
  /// 指针：长按节点放大后拖拽移动 / 单击平移画布，节点拖到屏幕边缘时画布自动跟随。
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

/// 节点卡片渲染（简化版）。
///
/// **显示简化**：节点卡片只渲染头部（图标 + 名称 + 关联标签 + 删除按钮）
/// 和可选注释行。不再渲染控制流输出行 / 数据输出行 / 类型 chip
/// （节点系统已统一为单输入单输出，多输出由子母节点表达）。
///
/// **中文名**：节点名称优先取 `params.name`，其次取 [NodeKindRegistry]
/// 中 [NodeKindSpec.displayName]（中文），最后回退到 `kind`。
///
/// **子母节点关联标签**：
/// - `branch` 子节点：显示所属母节点名称（"属于: 母节点名"）。
/// - 母节点（`controlOutputs.length >= 2`）：显示分支出口（"分支: 则、否则"）。
///
/// **指针模式长按拖拽**：长按节点后节点放大 1.05 倍 + 阴影增强，
/// 进入可拖拽状态，松手还原。单击仍打开节点编辑页。
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
    this.relatedLabel,
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
  ///
  /// 参数为视口坐标增量（已扣除缩放前的 raw delta）。
  final ValueChanged<Offset>? onDragUpdate;

  /// 连线模式：点击该节点（参数：节点 id）。
  final ValueChanged<String>? onConnectTap;

  /// 连线模式下是否为当前选中的起始节点（高亮）。
  final bool isConnectionSource;

  /// 子母节点关联标签（由父组件计算传入，如"属于: if判断"或"分支: 则、否则"）。
  final String? relatedLabel;

  @override
  State<NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<NodeCard>
    with TickerProviderStateMixin {
  late final AnimationController _appear;
  late final Animation<double> _appearAnim;

  /// 长按"抬起"动画：1.0 → 1.05 放大 + 阴影增强。
  late final AnimationController _lift;
  late final Animation<double> _liftAnim;

  /// 长按拖拽过程中累计的上一次触点位置（视口坐标），用于计算 delta。
  Offset? _lastLongPressPosition;

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

    _lift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _liftAnim = CurvedAnimation(
      parent: _lift,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _appear.dispose();
    _lift.dispose();
    super.dispose();
  }

  /// 节点显示名称：优先 params.name，其次 NodeKindRegistry displayName（中文），
  /// 最后回退到 kind。
  String get _displayName {
    final name = widget.node.params['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    final spec = NodeKindRegistry.getSpec(widget.node.kind);
    if (spec != null && spec.displayName.isNotEmpty) return spec.displayName;
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
        // 用 AnimatedBuilder 监听 _liftAnim，确保长按放大动画每一帧都重建，
        // 避免直接读取 _liftAnim.value 时动画不触发重绘的问题。
        child: AnimatedBuilder(
          animation: _liftAnim,
          builder: (context, child) {
            // 长按放大插值：1.0 → 1.05。
            final liftScale = 1.0 + 0.05 * _liftAnim.value;
            // 阴影强度：选中或长按时增强。
            final lifted = _liftAnim.value > 0.01;
            final shadowAlpha = widget.selected || lifted ? 0.12 : 0.04;
            final shadowBlur = widget.selected || lifted ? 14.0 : 6.0;
            return Transform.scale(
              scale: liftScale,
              alignment: Alignment.center,
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
                      width: borderWidth.toDouble(),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: shadowAlpha),
                        blurRadius: shadowBlur,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: _buildBody(theme, cs, isConnect),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs, bool isConnect) {
    // 连线模式：单击作为起始或终止节点（两步点击式连线）。
    if (isConnect) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onConnectTap == null
            ? null
            : () => widget.onConnectTap!(widget.node.id),
        child: _buildColumn(theme, cs),
      );
    }

    // 指针模式：单击打开编辑器；长按放大并进入拖拽，松手还原。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onSelect?.call();
        widget.onOpenEditor?.call();
      },
      onLongPressStart: (details) {
        widget.onSelect?.call();
        _lastLongPressPosition = details.globalPosition;
        _lift.forward();
      },
      onLongPressMoveUpdate: (details) {
        final last = _lastLongPressPosition;
        _lastLongPressPosition = details.globalPosition;
        if (last == null || widget.onDragUpdate == null) return;
        final delta = details.globalPosition - last;
        if (delta != Offset.zero) widget.onDragUpdate!(delta);
      },
      onLongPressEnd: (_) {
        _lastLongPressPosition = null;
        _lift.reverse();
      },
      child: _buildColumn(theme, cs),
    );
  }

  Widget _buildColumn(ThemeData theme, ColorScheme cs) {
    final hasAnnotation = widget.node.annotation.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(theme, cs),
        if (hasAnnotation) _buildAnnotation(theme, cs),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    final related = widget.relatedLabel;
    // function_input / function_output 是函数固有入口/出口，不允许删除，
    // 也不显示删除按钮（避免用户误以为可删除）。
    final isProtected = widget.node.kind == 'function_input' ||
        widget.node.kind == 'function_output';
    // 受保护节点（入参/出参）使用特殊背景色，便于识别。
    final headerColor = isProtected
        ? cs.tertiaryContainer.withValues(alpha: 0.6)
        : cs.surfaceContainerHigh;
    return Container(
      height: NodeLayout.headerHeight,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: headerColor,
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
          if (related != null && related.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                related,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: cs.onPrimaryContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          // 受保护节点不显示删除按钮；其余节点显示删除按钮。
          if (!isProtected && widget.onDelete != null)
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                onPressed: widget.onDelete,
                icon: Icon(Icons.close, size: 13, color: cs.error),
                padding: EdgeInsets.zero,
                splashRadius: 14,
                tooltip: '删除节点',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnnotation(ThemeData theme, ColorScheme cs) {
    return Container(
      height: NodeLayout.annotationRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(11),
          bottomRight: Radius.circular(11),
        ),
      ),
      child: Text(
        widget.node.annotation,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 11,
          color: cs.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
      case 'http_request':
        return Icons.cloud_download_outlined;
      case 'open_link':
        return Icons.open_in_browser;
      default:
        return Icons.widgets_outlined;
    }
  }
}
