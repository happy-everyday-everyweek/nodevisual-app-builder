import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ui_tree.dart';
import '../layout/layout_container.dart';
import '../layout/move_mode_handler.dart';
import '../ui_editor_providers.dart';

/// 画布渲染器：渲染当前选中 Page 节点及其子组件树。
///
/// 使用 [LayoutContainer] 进行 9 宫格 + 绝对布局渲染，每个子组件按其
/// [UiNode.layout] 配置定位（通过 [LayoutChild] 注入）。
///
/// 交互：
/// - 点击组件 → 选中（[UiMutator.selectComponent]）
/// - 长按组件 → 进入移动模式（[MoveModeHandler]）拖动改变布局
/// - 选中态：高亮边框 + 角标
///
/// 无 Page 时显示"请先创建页面"引导提示。
class CanvasRenderer extends ConsumerStatefulWidget {
  const CanvasRenderer({
    super.key,
    required this.page,
    this.canvasSize = const Size(360, 640),
  });

  /// 被渲染的 Page 节点（特殊 UiNode，type=='page'）。
  final UiNode page;

  /// 画布逻辑尺寸（用于百分比换算与 MoveModeHandler 的 parentSize）。
  final Size canvasSize;

  @override
  ConsumerState<CanvasRenderer> createState() => _CanvasRendererState();
}

class _CanvasRendererState extends ConsumerState<CanvasRenderer> {
  /// 父 [LayoutContainer] 的 GlobalKey，供 [MoveModeHandler] 坐标转换。
  final GlobalKey _layoutContainerKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final page = widget.page;
    final selectedId = ref.watch(selectedUiNodeIdProvider);

    // Page 节点的 children 即该页面的 UI 根节点树。
    final children = page.children;

    // Page 自身可能被选中（Page 选中态：浅色描边）。
    final isPageSelected = selectedId == page.id;

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: widget.canvasSize.width,
        height: widget.canvasSize.height,
        decoration: BoxDecoration(
          color: _pageBackground(page, theme),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPageSelected
                ? cs.primary.withValues(alpha: 0.8)
                : cs.outlineVariant,
            width: isPageSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点击 Page 空白区域 → 选中 Page 本身。
            onTap: () =>
                ref.read(uiMutatorProvider.notifier).selectComponent(page.id),
            child: children.isEmpty
                ? _buildEmptyHint(theme)
                : _buildLayoutContainer(children, selectedId, theme),
          ),
        ),
      ),
    );
  }

  /// 渲染 [LayoutContainer] 与其所有子组件。
  ///
  /// 模式取自第一个有 layout 的子组件；若全部无 layout，默认 relative。
  Widget _buildLayoutContainer(
    List<UiNode> children,
    String? selectedId,
    ThemeData theme,
  ) {
    final mode = _detectLayoutMode(children);
    return LayoutContainer(
      key: _layoutContainerKey,
      mode: mode,
      children: [
        for (final child in children)
          _renderChildNode(child, selectedId, theme, mode),
      ],
    );
  }

  /// 检测子组件集合的主导布局模式。
  ///
  /// 取第一个有 [LayoutConfig] 的子组件的模式；都无 layout 时返回 relative。
  LayoutMode _detectLayoutMode(List<UiNode> children) {
    for (final c in children) {
      final layout = c.layout;
      if (layout != null) return layout.mode;
    }
    return LayoutMode.relative;
  }

  /// 渲染单个子节点：[LayoutChild] 注入布局 + [MoveModeHandler] 长按移动
  /// + 选中态边框 + 真实内容。
  Widget _renderChildNode(
    UiNode node,
    String? selectedId,
    ThemeData theme,
    LayoutMode parentMode,
  ) {
    final layout = node.layout ?? _defaultChildLayout(parentMode);
    final selected = node.id == selectedId;
    final cs = theme.colorScheme;

    final content = _SelectionBorder(
      selected: selected,
      child: _NodeContentRenderer(node: node),
    );

    return LayoutChild(
      layout: layout,
      child: MoveModeHandler(
        nodeId: node.id,
        parentKey: _layoutContainerKey,
        parentSize: widget.canvasSize,
        enabled: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref
              .read(uiMutatorProvider.notifier)
              .selectComponent(node.id),
          child: content,
        ),
      ),
    );
  }

  /// 默认子组件布局（未配置 layout 时使用）。
  ///
  /// 跟随父容器模式：relative → 中心 9 宫格 + 自适应尺寸；
  /// absolute → (0, 0) 坐标 + 自适应尺寸。
  LayoutConfig _defaultChildLayout(LayoutMode parentMode) {
    if (parentMode == LayoutMode.absolute) {
      return const LayoutConfig(
        mode: LayoutMode.absolute,
        x: PositionSpec(value: 0),
        y: PositionSpec(value: 0),
        width: SizeSpec(value: 100, unit: SizeUnit.px),
        height: SizeSpec(value: 40, unit: SizeUnit.px),
      );
    }
    return const LayoutConfig(
      mode: LayoutMode.relative,
      cell: GridCell.center(),
      width: SizeSpec(value: 80, unit: SizeUnit.px),
      height: SizeSpec(value: 40, unit: SizeUnit.px),
    );
  }

  /// Page 空状态提示。
  Widget _buildEmptyHint(ThemeData theme) {
    final cs = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined,
              size: 36, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text(
            '页面为空',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '从左侧组件面板添加组件',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 解析 Page 背景色（从 props[PagePropsKeys.background]）。
  ///
  /// 仅支持 hex 颜色字符串；未设置或非法时使用 theme 的 surface。
  Color _pageBackground(UiNode page, ThemeData theme) {
    final bg = page.props['background'];
    if (bg is String && bg.startsWith('#')) {
      final hex = bg.replaceFirst('#', '');
      if (hex.length == 6 || hex.length == 8) {
        try {
          final rgba = int.parse(hex, radix: 16);
          if (hex.length == 6) return Color(0xFF000000 | rgba);
          return Color(rgba);
        } catch (_) {
          // 忽略非法颜色
        }
      }
    }
    return theme.colorScheme.surface;
  }
}

/// 选中态边框：选中时绘制高亮边框 + 角标。
class _SelectionBorder extends StatelessWidget {
  const _SelectionBorder({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? cs.primary : Colors.transparent,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}

/// 节点内容渲染器：按 [UiNode.type] 输出真实 Widget（所见即所得预览）。
///
/// 与 segment_view 中的渲染逻辑保持简洁一致；v2 仅覆盖常见类型，
/// 未覆盖的类型回退为占位卡片（图标 + 类型名）。
class _NodeContentRenderer extends StatelessWidget {
  const _NodeContentRenderer({required this.node});

  final UiNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (node.type) {
      case 'text':
        return Text(
          (node.props['content'] as String?) ?? '文本',
          style: theme.textTheme.bodyMedium,
        );
      case 'button':
        return IgnorePointer(
          child: ElevatedButton(
            onPressed: () {},
            child: Text((node.props['label'] as String?) ?? '按钮'),
          ),
        );
      case 'text_input':
        return IgnorePointer(
          child: SizedBox(
            width: 160,
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                hintText: (node.props['hint'] as String?) ?? '请输入',
                labelText: (node.props['label'] as String?)?.isNotEmpty == true
                    ? node.props['label'] as String
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        );
      case 'image':
        return Container(
          width: 80,
          height: 80,
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.image_outlined, size: 32),
        );
      case 'video':
        return Container(
          width: 120,
          height: 80,
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.play_circle_outline, size: 32),
        );
      case 'icon':
        final name = (node.props['name'] as String?) ?? 'star';
        final size = (node.props['size'] as num?)?.toDouble() ?? 24;
        return Icon(_iconFromName(name), size: size);
      case 'switch':
        return IgnorePointer(
          child: Switch(
            value: (node.props['value'] as bool?) ?? false,
            onChanged: (_) {},
          ),
        );
      case 'slider':
        return IgnorePointer(
          child: SizedBox(
            width: 160,
            child: Slider(
              value: ((node.props['value'] as num?)?.toDouble() ?? 0.5)
                  .clamp(
                    (node.props['min'] as num?)?.toDouble() ?? 0,
                    (node.props['max'] as num?)?.toDouble() ?? 1,
                  ),
              min: (node.props['min'] as num?)?.toDouble() ?? 0,
              max: (node.props['max'] as num?)?.toDouble() ?? 1,
              onChanged: (_) {},
            ),
          ),
        );
      case 'checkbox':
        return IgnorePointer(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: (node.props['value'] as bool?) ?? false,
                onChanged: (_) {},
              ),
              Text((node.props['label'] as String?) ?? '选项'),
            ],
          ),
        );
      case 'divider':
        return Divider(
          thickness: (node.props['thickness'] as num?)?.toDouble() ?? 1,
        );
      case 'progress':
        return SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            value: (node.props['value'] as num?)?.toDouble(),
          ),
        );
      case 'container':
        return Container(
          width: 120,
          height: 60,
          alignment: Alignment.center,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Text(
            '容器',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );
      case 'card':
        return Card(
          elevation: (node.props['elevation'] as num?)?.toDouble() ?? 1,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Text('卡片'),
          ),
        );
      default:
        return _Placeholder(type: node.type);
    }
  }

  IconData _iconFromName(String name) {
    const map = <String, IconData>{
      'star': Icons.star,
      'heart': Icons.favorite,
      'home': Icons.home,
      'person': Icons.person,
      'settings': Icons.settings,
      'search': Icons.search,
      'add': Icons.add,
      'close': Icons.close,
      'check': Icons.check,
      'menu': Icons.menu,
    };
    return map[name] ?? Icons.star;
  }
}

/// 未识别类型节点的占位卡片。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.35),
          width: 0.75,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.widgets_outlined, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            type,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
