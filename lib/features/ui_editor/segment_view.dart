import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/page.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/ui_tree.dart';
import '../../data/models/variable_ref.dart';
import '../variables/scope_resolver.dart';
import '../variables/variable_picker_sheet.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(Icons.widgets_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('UI', style: theme.textTheme.titleMedium),
          const Spacer(),
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
              // 组件添加 FAB（右下）
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'ui_component_fab',
                  onPressed: () => _showComponentSheet(selectedId),
                  child: const Icon(Icons.add),
                ),
              ),
              // 页面管理 FAB（左下）：竖屏下也能管理页面
              Positioned(
                left: 16,
                bottom: 16,
                child: FloatingActionButton.small(
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
        builder: (ctx, controller) => PagePanel(project: project),
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
    final content = _buildNodeContent(theme, node, selectedId);
    return _SelectionWrapper(
      nodeId: node.id,
      selected: node.id == selectedId,
      onTap: () =>
          ref.read(uiMutatorProvider.notifier).selectComponent(node.id),
      onLongPress: () => _showNodeMenu(node),
      child: content,
    );
  }

  Widget _buildNodeContent(ThemeData theme, UiNode node, String? selectedId) {
    switch (node.type) {
      case 'column':
        return IntrinsicHeight(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: _parseMainAxis(node.props['mainAxisAlignment']),
            crossAxisAlignment:
                _parseCrossAxis(node.props['crossAxisAlignment']),
            children: node.children
                .map((c) => _renderNode(theme, c, selectedId))
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
                .map((c) => _renderNode(theme, c, selectedId))
                .toList(growable: false),
          ),
        );
      case 'text':
        return Text(_displayValue(node, 'content', '文本'));
      case 'button':
        return ElevatedButton(
          onPressed: null,
          child: Text(_displayValue(node, 'label', '按钮')),
        );
      case 'text_field':
        return TextField(
          enabled: false,
          decoration: InputDecoration(
            isDense: true,
            hintText: (node.props['hint'] as String?) ?? '请输入',
            labelText: (node.props['label'] as String?)?.isNotEmpty == true
                ? node.props['label'] as String
                : null,
            border: const OutlineInputBorder(),
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
                      .map((c) => _renderNode(theme, c, selectedId))
                      .toList(growable: false),
                ),
        );
      case 'container':
        final color = _parseColor(node.props['color']);
        final padding = (node.props['padding'] as num?)?.toDouble() ?? 0;
        return Container(
          color: color,
          padding: EdgeInsets.all(padding),
          child: node.children.isEmpty
              ? const SizedBox(width: 64, height: 32)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: node.children
                      .map((c) => _renderNode(theme, c, selectedId))
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
                      .map((c) => _renderNode(theme, c, selectedId))
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
        return Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: null,
        );
      case 'switch':
        final value = (node.props['value'] as bool?) ?? false;
        return Switch(value: value, onChanged: null);
      case 'checkbox':
        final value = (node.props['value'] as bool?) ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: value, onChanged: null),
            Text(_displayValue(node, 'label', '')),
          ],
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
                      .map((c) => _renderNode(theme, c, selectedId))
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
                      .map((c) => _renderNode(theme, c, selectedId))
                      .toList(growable: false),
                ),
        );
      case 'tab_container':
        return Container(
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: node.children.isEmpty
              ? const Center(child: Text('Tab 容器（子节点为各 Tab 内容）'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      tabs: node.children
                          .map((c) => Tab(
                              text: (c.props['label'] as String?) ?? 'Tab'))
                          .toList(),
                    ),
                    const SizedBox(height: 40),
                  ],
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
                        .map((c) => _renderNode(theme, c, selectedId))
                        .toList(growable: false),
                  ),
          ),
        );
      default:
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

  /// 取属性展示值；若该属性已绑定，显示 `{来源.名}` 占位。
  String _displayValue(UiNode node, String prop, String fallback) {
    final binding = node.bindings[prop];
    if (binding != null) {
      final project = ref.read(uiMutatorProvider);
      return _describeBinding(binding.ref, project);
    }
    return (node.props[prop] as String?) ?? fallback;
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
    }
  }

  // ---- 添加组件 ----

  void _addComponent(String type, String? selectedId) {
    final mutator = ref.read(uiMutatorProvider.notifier);
    // 若选中了可容纳子节点的组件，添加为其子节点；否则添加为根节点。
    String? parentId;
    if (selectedId != null) {
      final found = mutator.findNode(selectedId);
      if (found != null && _canHaveChildren(found.node.type)) {
        parentId = selectedId;
      }
    }
    mutator.addComponent(type, parentId: parentId);
  }

  // ---- 组件面板 BottomSheet（窄屏）----

  void _showComponentSheet(String? selectedId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ComponentPanel(
        onPick: (type) {
          Navigator.pop(ctx);
          _addComponent(type, selectedId);
        },
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
    // 收集所有可作父的容器节点（排除自身及子树）。
    final candidates = <UiNode>[];
    void collect(UiNode n) {
      if (n.id == node.id) return;
      if (!_isInSubtree(n, node.id) && _canHaveChildren(n.type)) {
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
  // 指示器
  _ComponentDef('progress', '进度条', Icons.refresh, false, ComponentCategory.indicator),
];

/// 该类型是否可容纳子节点。
bool _canHaveChildren(String type) {
  return _componentDefs
      .where((d) => d.type == type)
      .any((d) => d.canHaveChildren);
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

/// 组件面板：列出可添加组件，按分类分组。
class ComponentPanel extends StatelessWidget {
  const ComponentPanel({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('组件', style: theme.textTheme.titleSmall),
          ),
          for (final cat in ComponentCategory.values)
            if (_componentDefs.any((d) => d.category == cat)) ...[
              _CategoryHeader(label: cat.label, theme: theme),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final def in _componentDefs)
                    if (def.category == cat)
                      _ComponentChip(def: def, onTap: () => onPick(def.type)),
                ],
              ),
              const SizedBox(height: 4),
            ],
        ],
      ),
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
    default:
      return [...lifecycle];
  }
}

/// 属性面板：选中组件后显示属性编辑 + 绑定 + 触发点。
class PropertiesPanel extends ConsumerWidget {
  const PropertiesPanel({super.key, required this.node});

  final UiNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final project = ref.watch(uiMutatorProvider);
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
                  '${node.type} · ${node.id.substring(0, 6)}',
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
          for (final desc in _propsForType(node.type)) ...[
            _PropEditor(
              key: ValueKey('${node.id}:${desc.key}'),
              node: node,
              desc: desc,
            ),
            const SizedBox(height: 8),
          ],
          if (_propsForType(node.type).isEmpty)
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
            for (final event in _eventsForType(node.type))
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

/// 单个属性编辑器（含绑定开关）。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desc = widget.desc;
    final node = widget.node;
    final binding = node.bindings[desc.key];
    final isBound = binding != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(desc.label, style: theme.textTheme.labelMedium)),
            if (desc.bindable)
              Switch(
                value: isBound,
                onChanged: (v) {
                  final mutator = ref.read(uiMutatorProvider.notifier);
                  if (v) {
                    // 开启绑定：先不设置具体值，等用户选函数；用占位 Binding。
                    mutator.setBinding(
                      node.id,
                      desc.key,
                      const Binding(
                        ref: VariableRef.upstream(
                          nodeId: '',
                          outputName: '',
                        ),
                      ),
                    );
                  } else {
                    mutator.setBinding(node.id, desc.key, null);
                  }
                },
              ),
          ],
        ),
        if (desc.bindable && isBound)
          _BindingEditor(
            key: ValueKey('${node.id}:${desc.key}'),
            node: node,
            prop: desc.key,
            binding: binding,
          )
        else
          _buildField(),
      ],
    );
  }

  Widget _buildField() {
    final desc = widget.desc;
    switch (desc.kind) {
      case _PropKind.text:
        return TextField(
          controller: _controller,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
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
}

/// 绑定编辑器：`#` 引用变量（四源）。
///
/// 点 `# 选择变量` 按钮弹出 [VariablePickerSheet]，支持项目变量 /
/// 组件上下文变量 / 函数变量 / 上游节点输出四源统一引用。
/// 选中含时间线的引用（页面函数 outputs / 组件上下文）时，附带加载态策略。
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
    final project = ref.watch(uiMutatorProvider);
    if (project == null) return const SizedBox.shrink();

    final refLabel = _describeRef(binding.ref, project);
    final hasStrategy = binding.ref.isPageFunc ||
        binding.ref.source == VariableSource.component;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('变量引用 #',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8,),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant, width: 0.75,),
                  ),
                  child: Text(
                    refLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: '选择变量',
                icon: const Icon(Icons.tag, size: 18),
                onPressed: () => _pickVariable(context, ref, project),
              ),
            ],
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

  Future<void> _pickVariable(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) async {
    // UI 属性侧：解析当前组件所在容器链暴露的组件上下文变量。
    // v1：暂按组件类型推导已知字段（item/index/value 等），不做完整树遍历。
    final componentVars = _inferComponentContext(node, project);
    // 页面级函数 outputs：v1 暂不传入（需页面绑定 onLoad 后才有）。
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
          prop,
          Binding(
            ref: result.ref,
            loadingStrategy: result.loadingStrategy,
            placeholderText: result.placeholderText,
          ),
        );
  }

  /// 按 UI 节点类型推导其向子组件暴露的组件上下文字段（简化版）。
  ///
  /// 完整实现应在渲染时按组件树位置注入（T17）；此处用于属性面板的 `#`
  /// 引用预览，提供常见字段供选择。
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

  /// 生成引用的可读描述。
  String _describeRef(VariableRef r, Project project) {
    switch (r.source) {
      case VariableSource.upstream:
        final fn = project.functions
            .where((f) => f.id == r.nodeId)
            .firstOrNull;
        return '${fn?.name ?? r.nodeId ?? '?'}.${r.outputName ?? '?'}';
      case VariableSource.funcVar:
        if (r.isPageFunc) {
          final fn = project.functions
              .where((f) => f.id == r.funcId)
              .firstOrNull;
          return '${fn?.name ?? r.funcId}.${r.outputName}';
        }
        return '函数变量 ${r.varId}';
      case VariableSource.projVar:
        final v = project.projectVars
            .where((p) => p.id == r.varId)
            .firstOrNull;
        return '项目变量 ${v?.name ?? r.varId}';
      case VariableSource.component:
        return '组件 ${r.fieldName}';
    }
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
            child: Text(eventName, style: theme.textTheme.bodyMedium),
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

/// 页面管理面板：页面列表 + 页面事件绑定。
///
/// 在宽屏布局中，当未选中任何 UI 组件时显示在右侧面板。
/// 可新建页面、设置首页、绑定页面生命周期事件（onLoad/onDispose 等）到函数。
class PagePanel extends ConsumerWidget {
  const PagePanel({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pages = project.pages;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            '页面是 UI 的命名根，承载页面级触发（onLoad/onDispose）与页面作用域函数变量。',
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
      ),
    );
  }

  Future<void> _addPage(BuildContext context, WidgetRef ref) async {
    final name = await _promptString(context, title: '新建页面', hint: '页面名');
    if (name == null || name.trim().isEmpty) return;
    ref.read(uiMutatorProvider.notifier).addPage(name.trim());
  }
}

/// 单个页面卡片：展示页面信息 + 事件绑定。
class _PageCard extends ConsumerWidget {
  const _PageCard({required this.page, required this.project});

  final Page page;
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mutator = ref.read(uiMutatorProvider.notifier);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Icon(page.isHome ? Icons.home : Icons.article_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    page.name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (page.isHome)
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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (v) {
                    switch (v) {
                      case 'home':
                        mutator.updatePage(page.id, isHome: true);
                      case 'rename':
                        _rename(context, ref);
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
                if (page.rootUiNodeId == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '提示：将一个 UI 根节点关联到此页面以启用页面级触发。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await _promptString(context,
        title: '重命名页面', hint: '页面名', initial: page.name);
    if (name == null || name.trim().isEmpty) return;
    ref.read(uiMutatorProvider.notifier).updatePage(page.id, name: name.trim());
  }
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
            child: Text(event, style: theme.textTheme.bodySmall),
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
