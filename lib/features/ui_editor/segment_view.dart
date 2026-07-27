import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/page.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/ui_tree.dart';
import '../../data/models/variable_ref.dart';
import '../marketplace/ui_component_def.dart';
import '../variables/scope_resolver.dart';
import '../variables/variable_picker_sheet.dart';
import 'component_registry.dart';
import 'ui_editor_providers.dart';

/// UI 段视图：可视化 UI 编辑器。
///
/// 布局：
/// - 宽屏（>720dp）：左侧组件面板（可折叠）+ 中间画布 + 右侧属性面板。
/// - 窄屏（移动端竖屏）：画布占满，FAB 打开组件面板 BottomSheet，
///   选中组件后属性面板以 BottomSheet 弹出。
///
/// 画布递归渲染 [Project.ui] 的 [UiNode] 树（column→Column 等），
/// 所见即所得。支持选中、长按菜单（删除/复制/移动）、属性编辑、
/// 属性 `#` 绑定、组件触发点 → 函数绑定、定时器 entry。
class UiEditorSegmentView extends ConsumerStatefulWidget {
  const UiEditorSegmentView({super.key});

  @override
  ConsumerState<UiEditorSegmentView> createState() =>
      _UiEditorSegmentViewState();
}

class _UiEditorSegmentViewState extends ConsumerState<UiEditorSegmentView> {
  /// 宽屏下组件面板是否折叠。
  bool _panelCollapsed = false;

  static const double _wideBreakpoint = 720;

  bool get _isWide => MediaQuery.sizeOf(context).width >= _wideBreakpoint;

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(uiMutatorProvider);
    final theme = Theme.of(context);

    if (project == null) {
      return const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: Text('未打开项目')),
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
                  ? _buildWideLayout(theme, project, selectedId, selectedNode)
                  : _buildNarrowLayout(theme, project, selectedId, selectedNode),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 顶部标题栏 ----

  Widget _buildHeader(ThemeData theme) {
    // Tab 名称"UI"已在顶部 CapsuleTopBar 指明，这里保留宽屏折叠按钮与全屏预览按钮。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            onPressed: () => _showFullscreenPreview(),
            icon: const Icon(Icons.fullscreen),
            tooltip: '全屏预览',
          ),
          if (_isWide)
            IconButton(
              onPressed: () =>
                  setState(() => _panelCollapsed = !_panelCollapsed),
              icon: Icon(_panelCollapsed
                  ? Icons.chevron_right
                  : Icons.chevron_left,),
              tooltip: _panelCollapsed ? '展开组件面板' : '折叠组件面板',
            ),
        ],
      ),
    );
  }

  // ---- 宽屏布局 ----

  Widget _buildWideLayout(
    ThemeData theme,
    Project project,
    String? selectedId,
    UiNode? selectedNode,
  ) {
    return Row(
      children: [
        if (!_panelCollapsed)
          SizedBox(
            width: 220,
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: ComponentPanel(
                onPick: (type) => _addComponent(type, selectedId),
              ),
            ),
          ),
        Expanded(
          child: _buildCanvas(theme, project, selectedId),
        ),
        SizedBox(
          width: 300,
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: selectedNode != null
                ? PropertiesPanel(node: selectedNode)
                : PagePanel(project: project),
          ),
        ),
      ],
    );
  }

  // ---- 窄屏布局 ----

  Widget _buildNarrowLayout(
    ThemeData theme,
    Project project,
    String? selectedId,
    UiNode? selectedNode,
  ) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref
                    .read(uiMutatorProvider.notifier)
                    .selectComponent(null),
                child: _buildCanvas(theme, project, selectedId),
              ),
              // 组件添加 FAB（右下）—— 与左下页面管理 FAB 大小一致。
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'ui_component_fab',
                  tooltip: '添加组件',
                  onPressed: () => _showComponentSheet(selectedId),
                  child: const Icon(Icons.add),
                ),
              ),
              // 页面管理 FAB（左下）：竖屏下也能管理页面，大小与右下统一。
              Positioned(
                left: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'ui_page_fab',
                  tooltip: '页面管理',
                  onPressed: () => _showPageSheet(project),
                  child: const Icon(Icons.article_outlined),
                ),
              ),
            ],
          ),
        ),
        // 选中组件后底部弹出属性面板（避免挤占画布）。
        if (selectedNode != null)
          Material(
            elevation: 8,
            color: theme.colorScheme.surfaceContainerHigh,
            child: SizedBox(
              height: 280,
              child: PropertiesPanel(node: selectedNode),
            ),
          ),
      ],
    );
  }

  /// 竖屏下页面管理 BottomSheet。
  ///
  /// 与组件添加面板保持一致的交互：使用 `DraggableScrollableSheet` 提供
  /// 可拖拽高度，`showDragHandle` 提供拖拽指示器，`isScrollControlled`
  /// 允许面板占据更多屏幕空间。
  void _showPageSheet(Project project) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, controller) => PagePanel(
          project: project,
          scrollController: controller,
        ),
      ),
    );
  }

  // ---- 画布 ----

  Widget _buildCanvas(ThemeData theme, Project project, String? selectedId) {
    if (project.ui.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.widgets_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant,),
            const SizedBox(height: 12),
            Text(
              '画布为空，点击 + 添加组件',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 240),
            reverseDuration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: Container(
                key: ValueKey(project.ui.length),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: project.ui
                      .map((n) => _renderNode(theme, n, selectedId))
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 递归渲染 UiNode 为真实 Widget（所见即所得）。
  Widget _renderNode(ThemeData theme, UiNode node, String? selectedId) {
    final content = _buildNodeContent(
      theme,
      node,
      (t, c) => _renderNode(t, c, selectedId),
    );
    return _SelectionWrapper(
      nodeId: node.id,
      selected: node.id == selectedId,
      onTap: () =>
          ref.read(uiMutatorProvider.notifier).selectComponent(node.id),
      onLongPress: () => _showNodeMenu(node),
      child: content,
    );
  }

  /// 全屏预览模式递归渲染 UiNode（不带选择器与编辑器提示）。
  Widget _buildPreviewNode(ThemeData theme, UiNode node) {
    return _buildNodeContent(theme, node, _buildPreviewNode);
  }

  Widget _buildNodeContent(
    ThemeData theme,
    UiNode node,
    Widget Function(ThemeData, UiNode) renderChild,
  ) {
    switch (node.type) {
      case 'column':
        return IntrinsicHeight(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: _parseMainAxis(node.props['mainAxisAlignment']),
            crossAxisAlignment:
                _parseCrossAxis(node.props['crossAxisAlignment']),
            children: node.children
                .map((c) => renderChild(theme, c))
                .toList(growable: false),
          ),
        );
      case 'row':
        return IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: _parseMainAxis(node.props['mainAxisAlignment']),
            crossAxisAlignment:
                _parseCrossAxis(node.props['crossAxisAlignment']),
            children: node.children
                .map((c) => renderChild(theme, c))
                .toList(growable: false),
          ),
        );
      case 'text':
        return Text(_displayValue(node, 'content', '文本'));
      case 'button':
        // IgnorePointer 阻止交互，onPressed 非 null 保持正常配色（不灰）。
        return IgnorePointer(
          child: ElevatedButton(
            onPressed: () {},
            child: Text(_displayValue(node, 'label', '按钮')),
          ),
        );
      case 'text_field':
        return IgnorePointer(
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
        );
      case 'image':
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80),
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.image_outlined, size: 40),
        );
      case 'list_view':
        return Container(
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: node.children.isEmpty
              ? const Center(child: Text('ListView（空）'))
              : ListView(
                  shrinkWrap: true,
                  children: node.children
                      .map((c) => renderChild(theme, c))
                      .toList(growable: false),
                ),
        );
      case 'container':
        final color = _parseColor(node.props['color']);
        final padding = (node.props['padding'] as num?)?.toDouble() ?? 0;
        // 未设置颜色时在编辑器中给容器一个浅灰背景，便于在画布上识别边界；
        // 用户显式设置颜色后仍优先使用用户颜色。
        final effectiveColor = color == Colors.transparent
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : color;
        return Container(
          color: effectiveColor,
          padding: EdgeInsets.all(padding),
          child: node.children.isEmpty
              ? SizedBox(
                  width: 64,
                  height: 32,
                  child: Center(
                    child: Text(
                      '容器',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: node.children
                      .map((c) => renderChild(theme, c))
                      .toList(growable: false),
                ),
        );
      case 'scaffold':
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            border: Border.all(
                color: theme.colorScheme.outlineVariant, width: 1,),
          ),
          child: node.children.isEmpty
              ? const Center(child: Text('Scaffold'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: node.children
                      .map((c) => renderChild(theme, c))
                      .toList(growable: false),
                ),
        );
      case 'rich_text':
        return Text(
          _displayValue(node, 'content', '富文本内容'),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        );
      case 'icon':
        final iconName = (node.props['name'] as String?) ?? 'star';
        final iconSize = (node.props['size'] as num?)?.toDouble() ?? 24;
        return Icon(_iconFromName(iconName), size: iconSize);
      case 'badge':
        final count = _displayValue(node, 'count', '0');
        return Badge(
          label: Text(count),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.notifications_none, size: 24),
          ),
        );
      case 'divider':
        return Divider(
          height: 1,
          thickness: (node.props['thickness'] as num?)?.toDouble() ?? 1,
          color: theme.colorScheme.outlineVariant,
        );
      case 'spacer':
        final flex = (node.props['flex'] as num?)?.toInt() ?? 1;
        return SizedBox(
          height: 8.0 * flex,
          child: const Center(
            child: Text('· · ·',
                style: TextStyle(color: Colors.grey, fontSize: 10)),
          ),
        );
      case 'video':
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 100),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_outline, size: 40),
              SizedBox(height: 4),
              Text('视频', style: TextStyle(fontSize: 12)),
            ],
          ),
        );
      case 'slider':
        final value = (node.props['value'] as num?)?.toDouble() ?? 0.5;
        final min = (node.props['min'] as num?)?.toDouble() ?? 0;
        final max = (node.props['max'] as num?)?.toDouble() ?? 1;
        return IgnorePointer(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (_) {},
          ),
        );
      case 'switch':
        final value = (node.props['value'] as bool?) ?? false;
        return IgnorePointer(
          child: Switch(value: value, onChanged: (_) {}),
        );
      case 'checkbox':
        final value = (node.props['value'] as bool?) ?? false;
        return IgnorePointer(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(value: value, onChanged: (_) {}),
              Text(_displayValue(node, 'label', '')),
            ],
          ),
        );
      case 'progress':
        final value = (node.props['value'] as num?)?.toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(value: value),
        );
      case 'list_vertical':
        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: node.children.isEmpty
              ? const Center(child: Text('纵向列表（绑定 items 数据）'))
              : ListView(
                  shrinkWrap: true,
                  children: node.children
                      .map((c) => renderChild(theme, c))
                      .toList(growable: false),
                ),
        );
      case 'list_horizontal':
        return Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: node.children.isEmpty
              ? const Center(child: Text('横向列表（绑定 items 数据）'))
              : ListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  children: node.children
                      .map((c) => renderChild(theme, c))
                      .toList(growable: false),
                ),
        );
      case 'tab_container':
        if (node.children.isEmpty) {
          return Container(
            constraints: const BoxConstraints(minHeight: 80),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Text('Tab 容器（子节点为各 Tab 内容）')),
          );
        }
        // 用 DefaultTabController 提供 TabController，避免抛
        // "No TabController for TabBar" 异常导致灰色 ErrorWidget。
        // 同时补上 TabBarView 真正渲染子节点内容。
        return DefaultTabController(
          length: node.children.length,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TabBar(
                  tabs: node.children
                      .map((c) => Tab(
                          text: (c.props['label'] as String?) ?? 'Tab'))
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: node.children
                        .map((c) => renderChild(theme, c))
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'card':
        final elevation = (node.props['elevation'] as num?)?.toDouble() ?? 1;
        return Card(
          elevation: elevation,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: node.children.isEmpty
                ? const Text('卡片')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: node.children
                        .map((c) => renderChild(theme, c))
                        .toList(growable: false),
                  ),
          ),
        );
      case 'conditional_container':
        // 选择式容器：当满足某一条件时，展示对应 case 的子容器内容。
        //
        // props:
        // - condition: 当前生效的 case 名（用户可在属性面板切换；也可绑定变量）
        // - mode: 'single'（默认，单选）/ 'firstMatch'（按顺序首匹配）
        // - cases: 子节点列表（每个子节点的 props['case'] = case 名）
        //
        // 在编辑器中预览：展示当前 condition 对应 case 的子节点；同时展示
        // 一个浅色边框 + "选择式: <condition>" 标签，便于识别。
        // 若 condition 未匹配任何 case，展示第一个 case 作为占位预览。
        final condition = _displayValue(node, 'condition', '');
        final mode = (node.props['mode'] as String?) ?? 'single';
        // 找到匹配的子节点（按 props['case'] 匹配 condition）。
        UiNode? matched;
        if (node.children.isNotEmpty) {
          if (condition.isNotEmpty) {
            for (final c in node.children) {
              final caseName = (c.props['case'] as String?) ?? '';
              if (caseName == condition) {
                matched = c;
                break;
              }
            }
          }
          // 未匹配 → 展示第一个 case 作为预览。
          matched ??= node.children.first;
        }
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.alt_route, size: 14,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    '选择式容器 · $mode'
                    '${condition.isNotEmpty ? ' · 当前: $condition' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text('${node.children.length} 个分支',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
              const SizedBox(height: 6),
              if (matched != null)
                renderChild(theme, matched)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '无子分支。添加子组件并设置其「case」属性来定义各分支内容。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        );
      default:
        // 插件提供的 UI 组件：从 ComponentRegistry 查询并占位渲染。
        //
        // v1 不实际执行 manifest 中的 renderFn（函数 IR 解释执行需异步，
        // 不适合在 build 中同步渲染）。此处显示一个占位卡片：插件名 + 类型 +
        // props 摘要，让用户感知组件存在并能在属性面板配置 props。
        // 真正的 renderFn 渲染发生在端侧运行时（Web 模板生成）。
        final pluginEntry = ref
            .read(componentRegistryProvider)
            .registry
            .get(node.type);
        if (pluginEntry != null) {
          return _PluginComponentPlaceholder(
            entry: pluginEntry,
            node: node,
          );
        }
        return const SizedBox.shrink();
    }
  }

  /// 按名称映射图标（简化版；未知名称回退为 star）。
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
      'arrow_back': Icons.arrow_back,
      'arrow_forward': Icons.arrow_forward,
      'menu': Icons.menu,
      'share': Icons.share,
      'edit': Icons.edit,
      'delete': Icons.delete,
      'info': Icons.info,
      'warning': Icons.warning,
      'error': Icons.error,
    };
    return map[name] ?? Icons.star;
  }

  /// 取属性展示值；若该属性已绑定，显示「前缀文字 + {变量}」。
  ///
  /// **自然变量引用语义**：用户在输入框中输入的文字作为「前缀文字」，
  /// 绑定的变量作为「后缀变量」。运行时展示值 = 前缀文字 + 变量值。
  /// 编辑器预览也按此语义显示，让用户直观感知最终效果。
  String _displayValue(UiNode node, String prop, String fallback) {
    final binding = node.bindings[prop];
    final prefix = (node.props[prop] as String?) ?? fallback;
    if (binding != null) {
      final project = ref.read(uiMutatorProvider);
      final varDesc = _describeBinding(binding.ref, project);
      // 前缀为空时只显示变量；非空时显示「前缀 + {变量}」。
      if (prefix.isEmpty || prefix == fallback) {
        return varDesc;
      }
      return '$prefix$varDesc';
    }
    return prefix;
  }

  /// 生成绑定的可读占位描述。
  String _describeBinding(VariableRef r, Project? project) {
    switch (r.source) {
      case VariableSource.upstream:
        final fn = project?.functions
            .where((f) => f.id == r.nodeId)
            .firstOrNull;
        return '{${fn?.name ?? r.nodeId ?? '?'}.${r.outputName ?? '?'}}';
      case VariableSource.funcVar:
        if (r.isPageFunc) {
          final fn = project?.functions
              .where((f) => f.id == r.funcId)
              .firstOrNull;
          return '{${fn?.name ?? r.funcId}.${r.outputName}}';
        }
        return '{func:${r.varId}}';
      case VariableSource.projVar:
        final v = project?.projectVars
            .where((p) => p.id == r.varId)
            .firstOrNull;
        return '{proj:${v?.name ?? r.varId}}';
      case VariableSource.component:
        return '{#:${r.fieldName}}';
      case VariableSource.device:
        return '{device:${DeviceProperty.labelOf(r.property ?? '')}}';
    }
  }

  // ---- 全屏预览 ----

  /// 打开全屏 UI 预览，移除编辑器面板、选中框与 FAB 等控件，
  /// 以接近生产环境的样式展示当前项目 UI。
  void _showFullscreenPreview() {
    final project = ref.read(uiMutatorProvider);
    if (project == null) return;
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: '关闭预览',
                onPressed: () => Navigator.pop(ctx),
              ),
              title: const Text('UI 全屏预览'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.fullscreen_exit),
                  tooltip: '退出全屏',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            body: project.ui.isEmpty
                ? Center(
                    child: Text(
                      '画布为空，无内容可预览',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: project.ui
                          .map((n) => _buildPreviewNode(theme, n))
                          .toList(growable: false),
                    ),
                  ),
          ),
        );
      },
    );
  }

  // ---- 添加组件 ----

  void _addComponent(String type, String? selectedId) {
    final mutator = ref.read(uiMutatorProvider.notifier);
    // 若选中了可容纳子节点的组件，添加为其子节点；否则添加为根节点。
    String? parentId;
    if (selectedId != null) {
      final found = mutator.findNode(selectedId);
      final pluginEntries = ref.read(componentRegistryProvider).registry.all();
      if (found != null &&
          _canHaveChildrenWithPlugins(found.node.type, pluginEntries)) {
        parentId = selectedId;
      }
    }
    mutator.addComponent(type, parentId: parentId);
  }

  // ---- 组件面板 BottomSheet（窄屏）----

  /// 竖屏下组件添加面板：与页面管理面板保持一致的交互（可拖拽高度 +
  /// 拖拽指示器 + isScrollControlled），避免突兀的小卡片。
  void _showComponentSheet(String? selectedId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, controller) => ComponentPanel(
          onPick: (type) {
            Navigator.pop(ctx);
            _addComponent(type, selectedId);
          },
          scrollController: controller,
        ),
      ),
    );
  }

  // ---- 节点长按菜单 ----

  void _showNodeMenu(UiNode node) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(uiMutatorProvider.notifier).duplicateComponent(node.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('移动到…'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMovePicker(node);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(ctx).colorScheme.error,),
                title: Text('删除',
                    style:
                        TextStyle(color: Theme.of(ctx).colorScheme.error),),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(uiMutatorProvider.notifier).removeComponent(node.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 移动组件：选择新父节点（容器类组件或根）。
  void _showMovePicker(UiNode node) {
    final project = ref.read(uiMutatorProvider);
    if (project == null) return;
    final pluginEntries = ref.read(componentRegistryProvider).registry.all();
    // 收集所有可作父的容器节点（排除自身及子树）。
    final candidates = <UiNode>[];
    void collect(UiNode n) {
      if (n.id == node.id) return;
      if (!_isInSubtree(n, node.id) &&
          _canHaveChildrenWithPlugins(n.type, pluginEntries)) {
        candidates.add(n);
      }
      for (final c in n.children) {
        collect(c);
      }
    }
    for (final root in project.ui) {
      collect(root);
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('根节点'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(uiMutatorProvider.notifier)
                      .moveComponent(node.id, '__root__');
                },
              ),
              for (final c in candidates)
                ListTile(
                  leading: const Icon(Icons.crop_square),
                  title: Text('${c.type} · ${c.id.substring(0, 6)}'),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref
                        .read(uiMutatorProvider.notifier)
                        .moveComponent(node.id, c.id);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// 判断 [node] 是否在 [subtreeRootId] 的子树内。
  bool _isInSubtree(UiNode node, String subtreeRootId) {
    if (node.id == subtreeRootId) return true;
    return node.children.any((c) => _isInSubtree(c, subtreeRootId));
  }

  // ---- 解析工具 ----

  MainAxisAlignment _parseMainAxis(Object? value) {
    switch (value) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      case 'spaceBetween':
        return MainAxisAlignment.spaceBetween;
      case 'spaceAround':
        return MainAxisAlignment.spaceAround;
      case 'spaceEvenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return MainAxisAlignment.start;
    }
  }

  CrossAxisAlignment _parseCrossAxis(Object? value) {
    switch (value) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      default:
        return CrossAxisAlignment.center;
    }
  }

  Color _parseColor(Object? value) {
    if (value is String) {
      final hex = value.replaceFirst('#', '');
      if (hex.length == 6 || hex.length == 8) {
        try {
          final rgba = int.parse(hex, radix: 16);
          if (hex.length == 6) {
            return Color(0xFF000000 | rgba);
          }
          return Color(rgba);
        } catch (_) {
          // 忽略非法颜色值
        }
      }
    }
    return Colors.transparent;
  }
}

/// 选中包裹器：渲染子节点，选中时加高亮边框，处理点击/长按。
class _SelectionWrapper extends StatelessWidget {
  const _SelectionWrapper({
    required this.nodeId,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });

  final String nodeId;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? color.primary : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      ),
    );
  }
}

/// 插件提供的 UI 组件占位渲染。
///
/// v1 不在编辑器中实际执行 manifest 中的 renderFn（需要异步函数解释器，
/// 不适合在 build 中同步调用）。此处给出占位：
/// - 顶部一行：图标 + 插件组件中文名 + "插件" 标签；
/// - 中间一行：组件 type（小字 monospace）；
/// - 底部一行：props 摘要（前 2 项 key=value）。
///
/// 用户可在属性面板配置 props，端侧运行时（Web 模板生成）会用 renderFn
/// 真正渲染该组件。
class _PluginComponentPlaceholder extends StatelessWidget {
  const _PluginComponentPlaceholder({
    required this.entry,
    required this.node,
  });

  final UiComponentEntry entry;
  final UiNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final props = entry.def.props;
    final summary = props.take(2).map((p) {
      final v = node.props[p.key];
      return '${p.label}=${v ?? ''}';
    }).join(' · ');
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minWidth: 120, minHeight: 56),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.4),
          width: 0.75,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(pluginIconFromName(entry.def.icon),
                  size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  entry.displayName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '插件',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.type,
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              summary,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 组件面板
// ============================================================================

/// 组件分类。
enum ComponentCategory {
  layout('布局'),
  display('展示'),
  media('媒体'),
  input('输入'),
  container('容器'),
  indicator('指示器');

  final String label;
  const ComponentCategory(this.label);
}

/// 组件类型定义。
class _ComponentDef {
  const _ComponentDef(
    this.type,
    this.name,
    this.icon,
    this.canHaveChildren,
    this.category,
  );

  final String type;
  final String name;
  final IconData icon;
  final bool canHaveChildren;
  final ComponentCategory category;
}

const List<_ComponentDef> _componentDefs = [
  // 布局
  _ComponentDef('column', '纵向布局', Icons.view_agenda, true, ComponentCategory.layout),
  _ComponentDef('row', '横向布局', Icons.view_column, true, ComponentCategory.layout),
  _ComponentDef('container', '容器', Icons.crop_square, true, ComponentCategory.layout),
  _ComponentDef('scaffold', '脚手架', Icons.web_asset, true, ComponentCategory.layout),
  _ComponentDef('divider', '分割线', Icons.horizontal_rule, false, ComponentCategory.layout),
  _ComponentDef('spacer', '占位空白', Icons.space_bar, false, ComponentCategory.layout),
  // 展示
  _ComponentDef('text', '文本', Icons.text_fields, false, ComponentCategory.display),
  _ComponentDef('rich_text', '富文本', Icons.text_snippet, false, ComponentCategory.display),
  _ComponentDef('icon', '图标', Icons.emoji_emotions, false, ComponentCategory.display),
  _ComponentDef('badge', '徽标', Icons.mark_chat_unread, false, ComponentCategory.display),
  // 媒体
  _ComponentDef('image', '图片', Icons.image_outlined, false, ComponentCategory.media),
  _ComponentDef('video', '视频', Icons.smart_display, false, ComponentCategory.media),
  // 输入
  _ComponentDef('text_field', '输入框', Icons.keyboard, false, ComponentCategory.input),
  _ComponentDef('slider', '滑块', Icons.linear_scale, false, ComponentCategory.input),
  _ComponentDef('switch', '开关', Icons.toggle_on, false, ComponentCategory.input),
  _ComponentDef('checkbox', '复选框', Icons.check_box, false, ComponentCategory.input),
  // 容器
  _ComponentDef('list_vertical', '纵向列表', Icons.view_list, true, ComponentCategory.container),
  _ComponentDef('list_horizontal', '横向列表', Icons.view_stream, true, ComponentCategory.container),
  _ComponentDef('tab_container', 'Tab 容器', Icons.tab, true, ComponentCategory.container),
  _ComponentDef('card', '卡片', Icons.credit_card, true, ComponentCategory.container),
  _ComponentDef('list_view', 'ListView', Icons.list, true, ComponentCategory.container),
  _ComponentDef('conditional_container', '选择式容器', Icons.alt_route, true, ComponentCategory.container),
  // 指示器
  _ComponentDef('progress', '进度条', Icons.refresh, false, ComponentCategory.indicator),
];

/// 该类型是否可容纳子节点（仅检查内置组件）。
bool _canHaveChildren(String type) {
  return _componentDefs
      .where((d) => d.type == type)
      .any((d) => d.canHaveChildren);
}

/// 该类型是否可容纳子节点（合并内置组件 + 插件组件）。
///
/// 调用方传入从 provider 读取的 [pluginEntries]，避免顶层函数访问 provider 树。
bool _canHaveChildrenWithPlugins(
  String type,
  List<UiComponentEntry> pluginEntries,
) {
  if (_canHaveChildren(type)) return true;
  for (final entry in pluginEntries) {
    if (entry.type == type && entry.canHaveChildren) return true;
  }
  return false;
}

/// 该类型是否为容器组件（向子组件注入组件上下文变量）。
bool _isContainerComponent(String type) {
  switch (type) {
    case 'list_vertical':
    case 'list_horizontal':
    case 'tab_container':
    case 'card':
    case 'slider':
    case 'switch':
      return true;
    default:
      return false;
  }
}

/// 组件面板：列出可添加组件，按分类分组（内置 + 插件提供）。
class ComponentPanel extends ConsumerWidget {
  const ComponentPanel({
    super.key,
    required this.onPick,
    this.scrollController,
  });

  final ValueChanged<String> onPick;

  /// 可选的滚动控制器（用于在 DraggableScrollableSheet 中同步滚动）。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pluginEntries =
        ref.watch(componentRegistryProvider).registry.all();
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('组件', style: theme.textTheme.titleSmall),
        ),
        for (final cat in ComponentCategory.values)
          if (_componentDefs.any((d) => d.category == cat) ||
              pluginEntries.any((e) => e.category.name == cat.name)) ...[
            _CategoryHeader(label: cat.label, theme: theme),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final def in _componentDefs)
                  if (def.category == cat)
                    _ComponentChip(def: def, onTap: () => onPick(def.type)),
                for (final entry in pluginEntries)
                  if (entry.category.name == cat.name)
                    _PluginComponentChip(
                      entry: entry,
                      onTap: () => onPick(entry.type),
                    ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        // 插件组件中分类不匹配任何内置分类的，归入「插件」分组。
        if (pluginEntries.any((e) =>
            !ComponentCategory.values.any((c) => c.name == e.category.name))) ...[
          _CategoryHeader(label: '插件', theme: theme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in pluginEntries)
                if (!ComponentCategory.values
                    .any((c) => c.name == entry.category.name))
                  _PluginComponentChip(
                    entry: entry,
                    onTap: () => onPick(entry.type),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4, left: 2),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ComponentChip extends StatelessWidget {
  const _ComponentChip({required this.def, required this.onTap});

  final _ComponentDef def;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant, width: 0.75),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(def.icon, color: cs.onSurfaceVariant, size: 22),
            const SizedBox(height: 6),
            Text(
              def.name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 插件提供的 UI 组件面板项。
///
/// 视觉与内置 [_ComponentChip] 对齐，但右上角加一个圆点提示「来自插件」，
/// 鼠标悬停（Semantics）也透露插件来源。
class _PluginComponentChip extends StatelessWidget {
  const _PluginComponentChip({required this.entry, required this.onTap});

  final UiComponentEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: '插件组件 · ${entry.pluginId}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.4),
              width: 0.75,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pluginIconFromName(entry.def.icon),
                    color: cs.primary,
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.displayName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              Positioned(
                top: 4,
                right: 6,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 属性面板
// ============================================================================

/// 属性编辑类型。
enum _PropKind { text, number, color, dropdown }

class _PropDescriptor {
  const _PropDescriptor(
    this.key,
    this.label,
    this.kind, {
    this.options,
    this.bindable = false,
  });

  final String key;
  final String label;
  final _PropKind kind;
  final List<String>? options;
  final bool bindable;
}

List<_PropDescriptor> _propsForType(String type) {
  switch (type) {
    case 'text':
      return const [_PropDescriptor('content', '内容', _PropKind.text, bindable: true)];
    case 'rich_text':
      return const [_PropDescriptor('content', '内容', _PropKind.text, bindable: true)];
    case 'button':
      return const [_PropDescriptor('label', '标签', _PropKind.text, bindable: true)];
    case 'text_field':
      return const [
        _PropDescriptor('hint', '提示', _PropKind.text, bindable: true),
        _PropDescriptor('label', '标签', _PropKind.text, bindable: true),
      ];
    case 'image':
      return const [_PropDescriptor('src', '图片地址', _PropKind.text, bindable: true)];
    case 'video':
      return const [_PropDescriptor('src', '视频地址', _PropKind.text, bindable: true)];
    case 'icon':
      return const [
        _PropDescriptor('name', '图标名', _PropKind.text),
        _PropDescriptor('size', '尺寸', _PropKind.number),
      ];
    case 'badge':
      return const [_PropDescriptor('count', '数量', _PropKind.text, bindable: true)];
    case 'divider':
      return const [_PropDescriptor('thickness', '粗细', _PropKind.number)];
    case 'spacer':
      return const [_PropDescriptor('flex', '倍数', _PropKind.number)];
    case 'progress':
      return const [_PropDescriptor('value', '进度(0-1)', _PropKind.number, bindable: true)];
    case 'slider':
      return const [
        _PropDescriptor('value', '当前值', _PropKind.number, bindable: true),
        _PropDescriptor('min', '最小值', _PropKind.number),
        _PropDescriptor('max', '最大值', _PropKind.number),
      ];
    case 'switch':
      return const [_PropDescriptor('value', '开/关', _PropKind.dropdown, options: ['true', 'false'], bindable: true)];
    case 'checkbox':
      return const [
        _PropDescriptor('value', '勾选', _PropKind.dropdown, options: ['true', 'false'], bindable: true),
        _PropDescriptor('label', '标签', _PropKind.text, bindable: true),
      ];
    case 'container':
      return const [
        _PropDescriptor('color', '颜色', _PropKind.color),
        _PropDescriptor('padding', '内边距', _PropKind.number),
      ];
    case 'card':
      return const [_PropDescriptor('elevation', '阴影', _PropKind.number)];
    case 'conditional_container':
      // 选择式容器：condition 决定展示哪个 case 子节点；mode 为匹配策略。
      // condition 可绑定变量（如列表项字段、函数输出等）实现动态切换。
      return const [
        _PropDescriptor('condition', '当前条件', _PropKind.text, bindable: true),
        _PropDescriptor('mode', '匹配策略', _PropKind.dropdown,
            options: ['single', 'firstMatch']),
      ];
    case 'tab_container':
      return const [];
    case 'list_vertical':
    case 'list_horizontal':
      return const [
        _PropDescriptor('items', '数据源', _PropKind.text, bindable: true),
      ];
    case 'column':
    case 'row':
      return const [
        _PropDescriptor('mainAxisAlignment', '主轴对齐', _PropKind.dropdown,
            options: [
              'start',
              'center',
              'end',
              'spaceBetween',
              'spaceAround',
              'spaceEvenly',
            ],),
        _PropDescriptor('crossAxisAlignment', '交叉轴对齐', _PropKind.dropdown,
            options: ['start', 'center', 'end', 'stretch'],),
      ];
    default:
      return const [];
  }
}

/// 插件组件的属性描述列表（从 [UiComponentDef.props] 映射为 _PropDescriptor）。
List<_PropDescriptor> _pluginPropsFor(UiComponentEntry entry) {
  return entry.def.props.map((p) {
    _PropKind kind;
    switch (p.kind) {
      case 'number':
        kind = _PropKind.number;
      case 'color':
        kind = _PropKind.color;
      case 'dropdown':
        kind = _PropKind.dropdown;
      case 'text':
      default:
        kind = _PropKind.text;
    }
    return _PropDescriptor(
      p.key,
      p.label,
      kind,
      options: p.options,
      bindable: p.bindable,
    );
  }).toList(growable: false);
}

/// 合并内置组件 + 插件组件的属性描述。
List<_PropDescriptor> _propsForTypeWithPlugins(
  String type,
  List<UiComponentEntry> pluginEntries,
) {
  final builtin = _propsForType(type);
  if (builtin.isNotEmpty) return builtin;
  for (final entry in pluginEntries) {
    if (entry.type == type) {
      return _pluginPropsFor(entry);
    }
  }
  return const [];
}

/// 判断 [node] 的父节点是否为 conditional_container。
///
/// 用于在属性面板中决定是否前置「case」属性编辑器。
bool _parentIsConditional(UiNode node, Project project) {
  for (final root in project.ui) {
    final result = _findParent(root, node.id);
    if (result != null) {
      return result.type == 'conditional_container';
    }
  }
  return false;
}

/// 在 [root] 子树中查找 [childId] 的父节点；找不到返回 null。
UiNode? _findParent(UiNode root, String childId) {
  for (final c in root.children) {
    if (c.id == childId) return root;
    final deeper = _findParent(c, childId);
    if (deeper != null) return deeper;
  }
  return null;
}

/// 组件支持的触发事件。
List<String> _eventsForType(String type) {
  const lifecycle = ['onLoad', 'onUnload'];
  switch (type) {
    case 'button':
      return ['onTap', 'onLongPress', ...lifecycle];
    case 'text_field':
      return ['onChanged', 'onSubmitted', 'onFocus', 'onBlur', ...lifecycle];
    case 'slider':
      return ['onChanged', 'onChangeEnd', ...lifecycle];
    case 'switch':
    case 'checkbox':
      return ['onToggle', ...lifecycle];
    case 'list_vertical':
    case 'list_horizontal':
    case 'list_view':
      return ['onItemTap', 'onScroll', ...lifecycle];
    case 'tab_container':
      return ['onTabChange', ...lifecycle];
    case 'image':
    case 'video':
      return ['onTap', ...lifecycle];
    case 'conditional_container':
      // 选择式容器：条件变化时触发（用于联动其他组件或记录日志）。
      return ['onCaseChange', ...lifecycle];
    case 'container':
    case 'card':
      return ['onTap', ...lifecycle];
    case 'icon':
    case 'badge':
      return ['onTap', ...lifecycle];
    default:
      return [...lifecycle];
  }
}

/// 合并内置组件 + 插件组件的触发事件列表。
///
/// 插件组件的事件来自 manifest 的 [UiComponentDef.events]，并追加
/// `onLoad` / `onUnload` 生命周期事件（与内置组件一致）。
List<String> _eventsForTypeWithPlugins(
  String type,
  List<UiComponentEntry> pluginEntries,
) {
  // 内置组件：直接返回。
  if (_componentDefs.any((d) => d.type == type)) {
    return _eventsForType(type);
  }
  // 插件组件：取 manifest 声明的事件 + 生命周期。
  for (final entry in pluginEntries) {
    if (entry.type == type) {
      return [...entry.events, 'onLoad', 'onUnload'];
    }
  }
  return _eventsForType(type);
}

/// 触发事件英文标识 → 中文显示名。
///
/// 存储仍使用英文标识（保持数据稳定性），仅在 UI 显示时映射为中文。
String _eventLabel(String eventName) {
  const map = <String, String>{
    'onTap': '点击',
    'onLongPress': '长按',
    'onChanged': '值变更',
    'onSubmitted': '提交',
    'onFocus': '获得焦点',
    'onBlur': '失去焦点',
    'onChangeEnd': '变更结束',
    'onToggle': '切换',
    'onItemTap': '点击列表项',
    'onScroll': '滚动',
    'onTabChange': 'Tab 切换',
    'onCaseChange': '条件变更',
    'onLoad': '加载',
    'onUnload': '卸载',
    'onDispose': '页面销毁',
    'onResume': '恢复',
    'onPause': '暂停',
  };
  return map[eventName] ?? eventName;
}

/// 属性面板：选中组件后显示属性编辑 + 绑定 + 触发点。
class PropertiesPanel extends ConsumerWidget {
  const PropertiesPanel({super.key, required this.node});

  final UiNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final project = ref.watch(uiMutatorProvider);
    final pluginEntries =
        ref.watch(componentRegistryProvider).registry.all();
    final props = _propsForTypeWithPlugins(node.type, pluginEntries);
    final events = _eventsForTypeWithPlugins(node.type, pluginEntries);
    // 插件组件的中文展示名（若是插件组件）。
    final pluginEntry = pluginEntries
        .where((e) => e.type == node.type)
        .firstOrNull;
    final titleText = pluginEntry != null
        ? '${pluginEntry.displayName} · ${node.id.substring(0, 6)}'
        : '${node.type} · ${node.id.substring(0, 6)}';

    // 若该节点的父节点是 conditional_container，前置一个「case 名」属性
    // 编辑器（用于在选择式容器中标识该子节点对应的分支名）。
    final List<_PropDescriptor> effectiveProps;
    if (project != null && _parentIsConditional(node, project)) {
      effectiveProps = [
        _PropDescriptor('case', '分支名(case)', _PropKind.text),
        ...props,
      ];
    } else {
      effectiveProps = props;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titleText,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: '取消选中',
                visualDensity: VisualDensity.compact,
                onPressed: () => ref
                    .read(uiMutatorProvider.notifier)
                    .selectComponent(null),
              ),
            ],
          ),
          const Divider(),
          // 属性编辑
          for (final desc in effectiveProps) ...[
            _PropEditor(
              key: ValueKey('${node.id}:${desc.key}'),
              node: node,
              desc: desc,
            ),
            const SizedBox(height: 8),
          ],
          if (effectiveProps.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '该组件无可编辑属性',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const Divider(),
          // 触发事件
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('触发事件', style: theme.textTheme.titleSmall),
          ),
          if (project != null)
            for (final event in events)
              _TriggerEditor(
                key: ValueKey('${node.id}:$event'),
                node: node,
                eventName: event,
                project: project,
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 单个属性编辑器（自然变量引用）。
///
/// **自然变量引用**：任何文本/数值/颜色输入框都可直接插入变量，无需开关切换。
/// 输入框右侧常驻 `#` 按钮，点击弹出变量选择面板。绑定后：
/// - 输入框仍可继续编辑文本（作为「前缀文字」）
/// - 输入框下方显示变量引用 chip（含变量名 + 移除按钮）
/// - 运行时展示值 = 前缀文字 + 变量值（字符串拼接运算）
///
/// 这样用户可以在任意输入框中混合「字面量 + 变量」，无需打开工作流配置。
class _PropEditor extends ConsumerStatefulWidget {
  const _PropEditor({super.key, required this.node, required this.desc});

  final UiNode node;
  final _PropDescriptor desc;

  @override
  ConsumerState<_PropEditor> createState() => _PropEditorState();
}

class _PropEditorState extends ConsumerState<_PropEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: '${widget.node.props[widget.desc.key] ?? ''}',
    );
  }

  @override
  void didUpdateWidget(covariant _PropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = '${widget.node.props[widget.desc.key] ?? ''}';
    if (_controller.text != current) {
      _controller.text = current;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 该属性是否支持变量引用（文本/数值/颜色均可；下拉框不支持）。
  bool get _supportsBinding =>
      widget.desc.kind == _PropKind.text ||
      widget.desc.kind == _PropKind.number ||
      widget.desc.kind == _PropKind.color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final desc = widget.desc;
    final node = widget.node;
    final binding = node.bindings[desc.key];
    final isBound = binding != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签行：属性名 + 绑定状态指示（如有）
        Row(
          children: [
            Expanded(child: Text(desc.label, style: theme.textTheme.labelMedium)),
            if (isBound)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '已绑定变量',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // 输入框 + # 按钮（文本/数值/颜色类型常驻 # 按钮）
        if (_supportsBinding)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildField()),
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: isBound ? '更换变量' : '插入变量',
                icon: Icon(Icons.tag, size: 18, color: cs.primary),
                onPressed: () => _pickVariable(),
              ),
            ],
          )
        else
          _buildField(),
        // 绑定信息（变量引用 chip + 加载态策略）
        if (isBound && _supportsBinding) ...[
          const SizedBox(height: 6),
          _BindingEditor(
            key: ValueKey('${node.id}:${desc.key}'),
            node: node,
            prop: desc.key,
            binding: binding,
          ),
        ],
      ],
    );
  }

  Widget _buildField() {
    final desc = widget.desc;
    switch (desc.kind) {
      case _PropKind.text:
        return TextField(
          controller: _controller,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: desc.bindable ? '输入文字，可点 # 插入变量' : null,
          ),
          onChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(widget.node.id, desc.key, v),
        );
      case _PropKind.number:
        return TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) {
              ref
                  .read(uiMutatorProvider.notifier)
                  .updateProp(widget.node.id, desc.key, n);
            }
          },
        );
      case _PropKind.color:
        return TextField(
          controller: _controller,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '#RRGGBB',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(widget.node.id, desc.key, v),
        );
      case _PropKind.dropdown:
        final current = '${widget.node.props[desc.key] ?? desc.options?.first}';
        return DropdownButtonFormField<String>(
          value:
              desc.options!.contains(current) ? current : desc.options!.first,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final o in desc.options!)
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) {
            if (v != null) {
              ref
                  .read(uiMutatorProvider.notifier)
                  .updateProp(widget.node.id, desc.key, v);
            }
          },
        );
    }
  }

  /// 弹出变量选择面板；选中后设置绑定（保留当前输入框文本作为前缀）。
  Future<void> _pickVariable() async {
    final project = ref.read(uiMutatorProvider);
    if (project == null) return;
    final node = widget.node;
    final componentVars = _inferComponentContext(node, project);
    final result = await VariablePickerSheet.show(
      context,
      functionId: '',
      nodeId: '',
      componentVars: componentVars,
      pageFuncOutputs: const [],
    );
    if (result == null) return;
    ref.read(uiMutatorProvider.notifier).setBinding(
          node.id,
          widget.desc.key,
          Binding(
            ref: result.ref,
            loadingStrategy: result.loadingStrategy,
            placeholderText: result.placeholderText,
          ),
        );
  }

  /// 按 UI 节点类型推导其向子组件暴露的组件上下文字段（简化版）。
  List<ComponentContextVar> _inferComponentContext(UiNode n, Project project) {
    switch (n.type) {
      case 'list_vertical':
      case 'list_horizontal':
        return const [
          ComponentContextVar(
              componentId: '', componentLabel: '列表', fieldName: 'item', type: PortType.any),
          ComponentContextVar(
              componentId: '', componentLabel: '列表', fieldName: 'index', type: PortType.number),
        ];
      case 'slider':
      case 'switch':
        return const [
          ComponentContextVar(
              componentId: '', componentLabel: '输入', fieldName: 'value', type: PortType.any),
        ];
      case 'tab_container':
        return const [
          ComponentContextVar(
              componentId: '', componentLabel: 'Tab', fieldName: 'tab', type: PortType.number),
        ];
      default:
        return const [];
    }
  }
}

/// 绑定信息展示器：显示已绑定的变量引用 + 移除按钮 + 加载态策略。
///
/// 变量选择由 [_PropEditor._pickVariable] 处理（输入框旁的 `#` 按钮），
/// 此组件仅负责展示绑定信息、提供移除按钮、以及含时间线引用时的加载态策略。
class _BindingEditor extends ConsumerWidget {
  const _BindingEditor({
    super.key,
    required this.node,
    required this.prop,
    required this.binding,
  });

  final UiNode node;
  final String prop;
  final Binding binding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final project = ref.watch(uiMutatorProvider);
    if (project == null) return const SizedBox.shrink();

    final refLabel = _describeBindingRef(binding.ref, project);
    final hasStrategy = binding.ref.isPageFunc ||
        binding.ref.source == VariableSource.component;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 变量引用 chip：图标 + 名称 + 移除按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: cs.primary.withValues(alpha: 0.4), width: 0.75),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '前缀文字 + $refLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => ref
                      .read(uiMutatorProvider.notifier)
                      .setBinding(node.id, prop, null),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        size: 14, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          if (hasStrategy) ...[
            const SizedBox(height: 6),
            _StrategyChip(
              strategy: binding.loadingStrategy,
              placeholder: binding.placeholderText,
              theme: theme,
              onChanged: (s, p) => ref.read(uiMutatorProvider.notifier).setBinding(
                node.id,
                prop,
                binding.copyWith(loadingStrategy: s, placeholderText: p),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 生成变量引用的可读描述（用于绑定信息展示）。
String _describeBindingRef(VariableRef r, Project project) {
  switch (r.source) {
    case VariableSource.upstream:
      final fn = project.functions
          .where((f) => f.id == r.nodeId)
          .firstOrNull;
      return '{${fn?.name ?? r.nodeId ?? '?'}.${r.outputName ?? '?'}}';
    case VariableSource.funcVar:
      if (r.isPageFunc) {
        final fn = project.functions
            .where((f) => f.id == r.funcId)
            .firstOrNull;
        return '{${fn?.name ?? r.funcId}.${r.outputName}}';
      }
      return '{func:${r.varId}}';
    case VariableSource.projVar:
      final v = project.projectVars
          .where((p) => p.id == r.varId)
          .firstOrNull;
      return '{proj:${v?.name ?? r.varId}}';
    case VariableSource.component:
      return '{#:${r.fieldName}}';
    case VariableSource.device:
      return '{device:${DeviceProperty.labelOf(r.property ?? '')}}';
  }
}

/// 加载态策略 chip（可点击切换）。
class _StrategyChip extends StatelessWidget {
  const _StrategyChip({
    required this.strategy,
    required this.placeholder,
    required this.theme,
    required this.onChanged,
  });

  final LoadingStrategy strategy;
  final String? placeholder;
  final ThemeData theme;
  final void Function(LoadingStrategy, String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPicker(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined,
                size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              '加载态：${_label(strategy)}'
              '${strategy == LoadingStrategy.placeholder && placeholder != null ? ' "$placeholder"' : ''}',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 14),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    LoadingStrategy s = strategy;
    String p = placeholder ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('加载态策略'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in LoadingStrategy.values)
                RadioListTile<LoadingStrategy>(
                  dense: true,
                  value: v,
                  groupValue: s,
                  title: Text(_label(v)),
                  onChanged: (nv) {
                    if (nv != null) setSt(() => s = nv);
                  },
                ),
              if (s == LoadingStrategy.placeholder)
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '占位文字',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => p = v,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                onChanged(
                  s,
                  s == LoadingStrategy.placeholder && p.trim().isNotEmpty
                      ? p.trim()
                      : null,
                );
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  String _label(LoadingStrategy s) {
    switch (s) {
      case LoadingStrategy.typeDefault:
        return '类型默认值';
      case LoadingStrategy.placeholder:
        return '占位文字';
      case LoadingStrategy.blank:
        return '留空';
    }
  }
}

/// 触发事件编辑器：选择触发的函数。
class _TriggerEditor extends ConsumerWidget {
  const _TriggerEditor({
    super.key,
    required this.node,
    required this.eventName,
    required this.project,
  });

  final UiNode node;
  final String eventName;
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mutator = ref.read(uiMutatorProvider.notifier);
    final currentFuncId = mutator.getTriggerFunctionId(node.id, eventName);
    final functions = project.functions;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(_eventLabel(eventName), style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: functions.any((f) => f.id == currentFuncId)
                  ? currentFuncId
                  : null,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              hint: const Text('未绑定'),
              items: [
                for (final f in functions)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) {
                ref
                    .read(uiMutatorProvider.notifier)
                    .setTrigger(node.id, eventName, v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 定时器 / 触发入口管理
// ============================================================================
//
// 注意：定时器（timer）与外部触发（external）触发器已迁移至函数编辑器中
// 编辑（每个函数声明自己的 entry）。UI 编辑器仅保留 uiEvent / pageEvent
// 两类与 UI 绑定的触发器编辑能力，故此处不再需要独立的触发入口管理 Sheet。
// 详见 lib/features/node_graph/function_editor_screen.dart 的 _FunctionTriggerSheet。

/// 小节标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(title, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

// ============================================================================
// 页面管理面板（T21-T22）
// ============================================================================

/// 页面管理面板：页面列表 + 页面事件绑定 + 组件层级树。
///
/// 在宽屏布局中，当未选中任何 UI 组件时显示在右侧面板。
/// 可新建页面、设置首页、绑定页面生命周期事件（onLoad/onDispose 等）到函数、
/// 查看每个页面下的组件层级树（点击组件可定位选中）。
class PagePanel extends ConsumerWidget {
  const PagePanel({
    super.key,
    required this.project,
    this.scrollController,
  });

  final Project project;

  /// 可选的滚动控制器（用于在 DraggableScrollableSheet 中同步滚动）。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pages = project.ui.where((n) => n.isPage).toList(growable: false);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Icon(Icons.pages, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('页面', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              tooltip: '新建页面',
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => _addPage(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '页面是 UI 的命名根，承载页面级触发（onLoad/onDispose）与页面作用域函数变量。'
          '点击页面卡片可展开组件层级树。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (pages.isEmpty)
          _EmptyHint(text: '暂无页面，点击 + 新建', theme: theme)
        else
          for (final pg in pages)
            _PageCard(page: pg, project: project),
      ],
    );
  }

  Future<void> _addPage(BuildContext context, WidgetRef ref) async {
    final name = await _promptString(context, title: '新建页面', hint: '页面名');
    if (name == null || name.trim().isEmpty) return;
    ref.read(uiMutatorProvider.notifier).addPage(name.trim());
  }
}

/// 单个页面卡片：展示页面信息 + 事件绑定 + 组件层级树。
///
/// 点击卡片头部右侧的展开按钮可折叠/展开「组件层级树」——递归展示该页面
/// 关联的 UI 根节点下的所有子组件，点击组件行可定位选中（画布会自动
/// 选中对应组件并展示属性面板）。
class _PageCard extends ConsumerStatefulWidget {
  const _PageCard({required this.page, required this.project});

  /// Page 节点（特殊 UiNode，type=='page'）。
  final UiNode page;
  final Project project;

  @override
  ConsumerState<_PageCard> createState() => _PageCardState();
}

class _PageCardState extends ConsumerState<_PageCard> {
  bool _treeExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutator = ref.read(uiMutatorProvider.notifier);
    final page = widget.page;
    final project = widget.project;

    // Page 节点的 children 即该页面的 UI 根节点树。
    final pageChildren = page.children;
    final hasRoots = pageChildren.isNotEmpty;
    // 统计所有根节点下的后代总数（不含根节点自身）。
    final childCount = pageChildren.fold<int>(
      0,
      (sum, n) => sum + _countDescendants(n),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Icon(page.isHomePage ? Icons.home : Icons.article_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    page.pageName ?? '未命名页面',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (page.isHomePage)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('首页',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                // 组件层级树展开按钮（仅有根节点时显示）。
                if (hasRoots)
                  IconButton(
                    tooltip: _treeExpanded ? '折叠组件树' : '展开组件树',
                    icon: Icon(
                      _treeExpanded
                          ? Icons.expand_less
                          : Icons.chevron_right,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _treeExpanded = !_treeExpanded),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (v) {
                    switch (v) {
                      case 'home':
                        mutator.updatePage(page.id, isHome: true);
                      case 'rename':
                        _rename();
                      case 'delete':
                        mutator.removePage(page.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'home', child: Text('设为首页')),
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 组件层级树概要 + 展开内容
                if (hasRoots) ...[
                  Row(
                    children: [
                      Icon(Icons.account_tree_outlined,
                          size: 13, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '$childCount 个组件 · ${pageChildren.length} 个根',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (_treeExpanded) ...[
                    const SizedBox(height: 6),
                    for (final root in pageChildren)
                      _ComponentTreeNode(
                        node: root,
                        depth: 0,
                        project: project,
                      ),
                    const SizedBox(height: 8),
                  ],
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '提示：在画布中添加组件到此页面以启用页面级触发。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                Text('页面事件',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 4),
                for (final event in PageEventName.all)
                  _PageEventRow(
                    pageId: page.id,
                    event: event,
                    project: project,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final name = await _promptString(context,
        title: '重命名页面', hint: '页面名', initial: widget.page.pageName ?? '');
    if (name == null || name.trim().isEmpty) return;
    ref.read(uiMutatorProvider.notifier).updatePage(widget.page.id, name: name.trim());
  }
}

/// 递归统计节点后代数量（不含自身）。
int _countDescendants(UiNode node) {
  var count = node.children.length;
  for (final c in node.children) {
    count += _countDescendants(c);
  }
  return count;
}

/// 节点的简短显示标签。
String _nodeLabel(UiNode node) {
  final labelMap = <String, String>{
    'column': '纵向布局',
    'row': '横向布局',
    'container': '容器',
    'scaffold': '脚手架',
    'text': '文本',
    'button': '按钮',
    'text_field': '输入框',
    'image': '图片',
    'video': '视频',
    'icon': '图标',
    'badge': '徽标',
    'divider': '分割线',
    'spacer': '空白',
    'rich_text': '富文本',
    'list_view': '列表',
    'list_vertical': '纵向列表',
    'list_horizontal': '横向列表',
    'tab_container': 'Tab容器',
    'card': '卡片',
    'slider': '滑块',
    'switch': '开关',
    'checkbox': '复选框',
    'progress': '进度条',
    'conditional_container': '选择式容器',
  };
  final name = node.props['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  // 文本/按钮等组件展示其文本内容作为辅助识别。
  if (node.type == 'text' || node.type == 'button' ||
      node.type == 'rich_text') {
    final content = (node.props['content'] as String?) ??
        (node.props['label'] as String?) ??
        '';
    if (content.isNotEmpty) return '${labelMap[node.type] ?? node.type}($content)';
  }
  return labelMap[node.type] ?? node.type;
}

/// 组件树节点（递归渲染组件层级）。
///
/// 每行：缩进 + 图标 + 类型标签 + 后代数；点击行选中该组件（画布同步选中）。
class _ComponentTreeNode extends ConsumerWidget {
  const _ComponentTreeNode({
    required this.node,
    required this.depth,
    required this.project,
  });

  final UiNode node;
  final int depth;
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedId = ref.watch(selectedUiNodeIdProvider);
    final selected = node.id == selectedId;
    final hasChildren = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            ref.read(uiMutatorProvider.notifier).selectComponent(node.id);
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primaryContainer.withValues(alpha: 0.6)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                SizedBox(width: depth * 14.0),
                Icon(
                  hasChildren ? Icons.subdirectory_arrow_right : Icons.circle,
                  size: hasChildren ? 14 : 6,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Icon(_componentTypeIcon(node.type),
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _nodeLabel(node),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasChildren)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${node.children.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        for (final c in node.children)
          _ComponentTreeNode(node: c, depth: depth + 1, project: project),
      ],
    );
  }
}

/// 按组件类型返回对应图标（用于组件树展示）。
IconData _componentTypeIcon(String type) {
  const map = <String, IconData>{
    'column': Icons.view_agenda,
    'row': Icons.view_column,
    'container': Icons.crop_square,
    'scaffold': Icons.web_asset,
    'text': Icons.text_fields,
    'button': Icons.smart_button_outlined,
    'text_field': Icons.keyboard,
    'image': Icons.image_outlined,
    'video': Icons.smart_display,
    'icon': Icons.emoji_emotions,
    'badge': Icons.mark_chat_unread,
    'divider': Icons.horizontal_rule,
    'spacer': Icons.space_bar,
    'rich_text': Icons.text_snippet,
    'list_view': Icons.list,
    'list_vertical': Icons.view_list,
    'list_horizontal': Icons.view_stream,
    'tab_container': Icons.tab,
    'card': Icons.credit_card,
    'slider': Icons.linear_scale,
    'switch': Icons.toggle_on,
    'checkbox': Icons.check_box,
    'progress': Icons.refresh,
    'conditional_container': Icons.alt_route,
  };
  return map[type] ?? Icons.widgets_outlined;
}

/// 页面事件绑定行：选择触发的函数。
class _PageEventRow extends ConsumerWidget {
  const _PageEventRow({
    required this.pageId,
    required this.event,
    required this.project,
  });

  final String pageId;
  final String event;
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mutator = ref.read(uiMutatorProvider.notifier);
    final currentFuncId = mutator.getPageEventFunctionId(pageId, event);
    final functions = project.functions;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(_eventLabel(event), style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              isDense: true,
              value:
                  functions.any((f) => f.id == currentFuncId) ? currentFuncId : null,
              decoration: InputDecoration(
                isDense: true,
                hintText: '未绑定',
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              items: [
                for (final f in functions)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) =>
                  mutator.setPageEventFunction(pageId, event, v),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(text, style: TextStyle(color: theme.colorScheme.outline)),
      ),
    );
  }
}

/// 弹出输入框获取字符串。
Future<String?> _promptString(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
