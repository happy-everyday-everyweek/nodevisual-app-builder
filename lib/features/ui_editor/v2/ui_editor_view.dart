import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/page.dart';
import '../../../data/models/ui_tree.dart';
import '../ui_editor_providers.dart';
import 'canvas_renderer.dart';
import 'component_panel.dart';
import 'page_panel.dart';
import 'property_panel.dart';

/// UI 编辑器主视图（Phase 4 v2）。
///
/// 三栏布局：
/// - 左侧（宽屏）：[PagePanel]（上）+ [ComponentPanel]（下），可折叠。
/// - 中间：[CanvasRenderer] 渲染当前选中 Page。
/// - 右侧（宽屏）：[PropertyPanel] 编辑选中节点。
///
/// 窄屏（< [_wideBreakpoint]）：
/// - 画布占满；左下 FAB 打开页面管理 BottomSheet，右下 FAB 打开组件 BottomSheet。
/// - 选中组件后底部固定高度展示 [PropertyPanel]。
///
/// 嵌入约定：本视图被 [EditorShellScreen] 通过 IndexedStack 承载，
/// 顶部有悬浮 [CapsuleTopBar]，故本视图使用 `SafeArea(bottom: false)` +
/// `Padding(top: 72)` 为顶栏让位（与 v1 [UiEditorSegmentView] 一致）。
///
/// Page-组件强绑定：无选中 Page 时画布显示引导提示，组件面板内的添加功能
/// 自动禁用（由 [ComponentPanel] 内部根据 [selectedPageIdProvider] 判断）。
class UiEditorView extends ConsumerStatefulWidget {
  const UiEditorView({super.key});

  @override
  ConsumerState<UiEditorView> createState() => _UiEditorViewState();
}

class _UiEditorViewState extends ConsumerState<UiEditorView> {
  /// 宽屏下左侧面板是否折叠。
  bool _leftCollapsed = false;

  /// 三栏布局所需的最小宽度（左 240 + 画布 ≥400 + 右 320）。
  static const double _wideBreakpoint = 960;

  bool get _isWide => MediaQuery.sizeOf(context).width >= _wideBreakpoint;

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(uiMutatorProvider);
    final theme = Theme.of(context);

    if (project == null) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 72),
          child: Center(
            child: Text(
              '未打开项目',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final selectedId = ref.watch(selectedUiNodeIdProvider);
    final selectedNode = selectedId == null
        ? null
        : ref.read(uiMutatorProvider.notifier).findNode(selectedId)?.node;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 72),
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: _isWide
                  ? _buildWide(theme, selectedNode)
                  : _buildNarrow(theme, selectedNode),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 顶部标题栏 ----

  Widget _buildHeader(ThemeData theme) {
    // "UI" 段标签已在顶部 CapsuleTopBar 指明，此处仅保留左侧面板折叠按钮。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          const Spacer(),
          if (_isWide)
            IconButton(
              onPressed: () =>
                  setState(() => _leftCollapsed = !_leftCollapsed),
              icon: Icon(_leftCollapsed
                  ? Icons.chevron_right
                  : Icons.chevron_left,),
              tooltip: _leftCollapsed ? '展开左侧面板' : '折叠左侧面板',
            ),
        ],
      ),
    );
  }

  // ---- 宽屏三栏布局 ----

  Widget _buildWide(ThemeData theme, UiNode? selectedNode) {
    return Row(
      children: [
        if (!_leftCollapsed)
          SizedBox(
            width: 240,
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  const Expanded(
                    flex: 2,
                    child: PagePanel(),
                  ),
                  const Divider(height: 1),
                  const Expanded(
                    flex: 3,
                    child: ComponentPanel(),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: _buildCanvasArea(theme)),
        SizedBox(
          width: 320,
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: selectedNode != null
                ? PropertyPanel(node: selectedNode)
                : _EmptyRightPanel(theme: theme),
          ),
        ),
      ],
    );
  }

  // ---- 窄屏布局 ----

  Widget _buildNarrow(ThemeData theme, UiNode? selectedNode) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 点击画布空白区域取消选中组件（不影响 Page 选中态）。
                onTap: () =>
                    ref.read(uiMutatorProvider.notifier).selectComponent(null),
                child: _buildCanvasArea(theme),
              ),
              // 页面管理 FAB（左下）。
              Positioned(
                left: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'ui_v2_page_fab',
                  tooltip: '页面管理',
                  onPressed: _showPageSheet,
                  child: const Icon(Icons.article_outlined),
                ),
              ),
              // 组件添加 FAB（右下）。
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'ui_v2_component_fab',
                  tooltip: '添加组件',
                  onPressed: _showComponentSheet,
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
        // 选中节点后底部固定高度展示属性面板。
        if (selectedNode != null)
          Material(
            elevation: 8,
            color: theme.colorScheme.surfaceContainerHigh,
            child: SizedBox(
              height: 300,
              child: PropertyPanel(node: selectedNode),
            ),
          ),
      ],
    );
  }

  // ---- 画布区 ----

  /// 解析当前应渲染的 Page：
  /// 优先 [selectedPageIdProvider]；若未选中但项目存在页面，
  /// 在下一帧自动选中首页（或第一个页面），避免画布长期空载。
  Widget _buildCanvasArea(ThemeData theme) {
    final project = ref.watch(uiMutatorProvider);
    if (project == null) return const SizedBox.shrink();

    final selectedPageId = ref.watch(selectedPageIdProvider);
    final pages = project.ui.where((n) => n.isPage).toList(growable: false);

    UiNode? page;
    if (selectedPageId != null) {
      for (final p in pages) {
        if (p.id == selectedPageId) {
          page = p;
          break;
        }
      }
    }

    // 自动选中首页/第一个页面（guarded，仅在 selectedPageId 仍为 null 时写回）。
    if (page == null && pages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(selectedPageIdProvider) != null) return;
        final home = pages.firstWhere(
          (p) => p.isHomePage,
          orElse: () => pages.first,
        );
        ref.read(selectedPageIdProvider.notifier).state = home.id;
      });
    }

    if (page == null) {
      return _buildCanvasEmpty(theme, pages.isEmpty);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: CanvasRenderer(page: page),
      ),
    );
  }

  /// 画布空状态提示。
  Widget _buildCanvasEmpty(ThemeData theme, bool noPages) {
    final cs = theme.colorScheme;
    final hint = _isWide
        ? (noPages ? '点击左侧"新建"按钮添加第一个页面' : '在左侧页面列表中点击一个页面')
        : (noPages ? '点击左下角"页面"按钮添加第一个页面' : '点击左下角"页面"按钮选择');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            noPages ? Icons.layers_clear_outlined : Icons.touch_app_outlined,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            noPages ? '请先创建页面' : '请选择页面',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---- 窄屏 BottomSheet ----

  /// 竖屏下页面管理 BottomSheet（可拖拽高度 + 滚动同步）。
  void _showPageSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, controller) => PagePanel(scrollController: controller),
      ),
    );
  }

  /// 竖屏下组件添加 BottomSheet。
  void _showComponentSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, controller) =>
            ComponentPanel(scrollController: controller),
      ),
    );
  }
}

/// 宽屏右侧未选中时的空状态提示。
class _EmptyRightPanel extends StatelessWidget {
  const _EmptyRightPanel({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune,
                size: 36, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text(
              '未选中组件',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '在画布中点击组件以编辑其属性',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
