import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/project.dart';
import '../../data/models/ui_tree.dart';
import '../../data/models/variable_ref.dart';
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
          IconButton(
            onPressed: _showTimerSheet,
            icon: const Icon(Icons.timer_outlined),
            tooltip: '定时器 / 触发入口',
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
        if (selectedNode != null)
          SizedBox(
            width: 300,
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: PropertiesPanel(node: selectedNode),
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
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'ui_component_fab',
                  onPressed: () => _showComponentSheet(selectedId),
                  child: const Icon(Icons.add),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 80,
                child: FloatingActionButton.small(
                  heroTag: 'ui_timer_fab',
                  onPressed: _showTimerSheet,
                  child: const Icon(Icons.timer_outlined),
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

  // ---- 画布 ----

  Widget _buildCanvas(ThemeData theme, Project project, String? selectedId) {
    if (project.ui.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.widgets_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant,),
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: project.ui
                  .map((n) => _renderNode(theme, n, selectedId))
                  .toList(growable: false),
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
      default:
        return const SizedBox.shrink();
    }
  }

  /// 取属性展示值；若该属性已绑定，显示 `{函数名.输出名}` 占位。
  String _displayValue(UiNode node, String prop, String fallback) {
    final binding = node.bindings[prop];
    if (binding != null) {
      final project = ref.read(uiMutatorProvider);
      final fn = project?.functions
          .where((f) => f.id == binding.ref.nodeId)
          .firstOrNull;
      final funcName = fn?.name ?? '?';
      final outputName = binding.ref.outputName ?? '?';
      return '{$funcName.$outputName}';
    }
    return (node.props[prop] as String?) ?? fallback;
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

  // ---- 定时器 / 触发入口管理 ----

  void _showTimerSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const _TimerEntrySheet(),
    );
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? color.primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        child: child,
      ),
    );
  }
}

// ============================================================================
// 组件面板
// ============================================================================

/// 组件类型定义。
class _ComponentDef {
  const _ComponentDef(this.type, this.name, this.icon, this.canHaveChildren);

  final String type;
  final String name;
  final IconData icon;
  final bool canHaveChildren;
}

const List<_ComponentDef> _componentDefs = [
  _ComponentDef('column', 'Column', Icons.view_agenda, true),
  _ComponentDef('row', 'Row', Icons.view_column, true),
  _ComponentDef('text', 'Text', Icons.text_fields, false),
  _ComponentDef('button', 'Button', Icons.smart_button, false),
  _ComponentDef('text_field', '输入框', Icons.keyboard, false),
  _ComponentDef('image', 'Image', Icons.image_outlined, false),
  _ComponentDef('list_view', 'ListView', Icons.list, true),
  _ComponentDef('container', 'Container', Icons.crop_square, true),
  _ComponentDef('scaffold', 'Scaffold', Icons.web_asset, true),
];

/// 该类型是否可容纳子节点。
bool _canHaveChildren(String type) {
  return _componentDefs
      .where((d) => d.type == type)
      .any((d) => d.canHaveChildren);
}

/// 组件面板：列出可添加组件。
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final def in _componentDefs)
                _ComponentChip(def: def, onTap: () => onPick(def.type)),
            ],
          ),
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(def.icon, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(def.name, style: theme.textTheme.labelSmall),
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
    case 'button':
      return const [_PropDescriptor('label', '标签', _PropKind.text, bindable: true)];
    case 'text_field':
      return const [
        _PropDescriptor('hint', '提示', _PropKind.text, bindable: true),
        _PropDescriptor('label', '标签', _PropKind.text, bindable: true),
      ];
    case 'image':
      return const [_PropDescriptor('src', '图片地址', _PropKind.text, bindable: true)];
    case 'container':
      return const [
        _PropDescriptor('color', '颜色', _PropKind.color),
        _PropDescriptor('padding', '内边距', _PropKind.number),
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
  const allEvents = ['onLoad', 'onUnload'];
  switch (type) {
    case 'button':
      return ['onTap', 'onLongPress', ...allEvents];
    case 'text_field':
      return ['onSubmit', 'onFocus', 'onBlur', ...allEvents];
    case 'list_view':
      return ['onItemVisible', ...allEvents];
    default:
      return [...allEvents];
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
          initialValue:
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

/// 绑定编辑器：函数选择 + 输出名选择。
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

    final functions = project.functions;
    final currentFuncId = binding.ref.nodeId;
    final currentOutput = binding.ref.outputName ?? '';

    final selectedFn = functions.where((f) => f.id == currentFuncId).firstOrNull;
    final outputNames =
        selectedFn == null ? const <String>[] : collectFunctionOutputNames(selectedFn);

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('绑定到函数输出',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue:
                functions.any((f) => f.id == currentFuncId) ? currentFuncId : null,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '函数',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final f in functions)
                DropdownMenuItem(value: f.id, child: Text(f.name)),
            ],
            onChanged: (v) {
              ref.read(uiMutatorProvider.notifier).setBinding(
                    node.id,
                    prop,
                    v == null
                        ? null
                        : Binding(
                            ref: VariableRef.upstream(
                              nodeId: v,
                              outputName: '',
                            ),
                          ),
                  );
            },
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue:
                outputNames.contains(currentOutput) ? currentOutput : null,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '输出名',
              border: OutlineInputBorder(),
            ),
            hint: outputNames.isEmpty ? const Text('该函数暂无数据输出') : null,
            items: [
              for (final o in outputNames)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) {
              if (v == null) return;
              if (currentFuncId == null || currentFuncId.isEmpty) return;
              ref.read(uiMutatorProvider.notifier).setBinding(
                    node.id,
                    prop,
                    Binding(
                      ref: VariableRef.upstream(
                        nodeId: currentFuncId,
                        outputName: v,
                      ),
                    ),
                  );
            },
          ),
        ],
      ),
    );
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
              initialValue: functions.any((f) => f.id == currentFuncId)
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

/// 定时器 entry 管理 Sheet：列出已有定时器 + 新建 + 外部触发占位。
class _TimerEntrySheet extends ConsumerStatefulWidget {
  const _TimerEntrySheet();

  @override
  ConsumerState<_TimerEntrySheet> createState() => _TimerEntrySheetState();
}

class _TimerEntrySheetState extends ConsumerState<_TimerEntrySheet> {
  String? _selectedFuncId;
  final TextEditingController _intervalController =
      TextEditingController(text: '5000');

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = ref.watch(uiMutatorProvider);
    if (project == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('未打开项目'),
      );
    }
    final functions = project.functions;
    final timers = functions
        .where((f) => f.entry?.kind == EntryKind.timer)
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('定时器 / 触发入口', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            // 已有定时器列表
            if (timers.isEmpty)
              Text('暂无定时器', style: theme.textTheme.bodySmall)
            else
              for (final f in timers)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.timer),
                  title: Text(f.name),
                  subtitle: Text('间隔 ${f.entry?.ref ?? '?'} ms'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => ref
                        .read(uiMutatorProvider.notifier)
                        .clearEntry(f.id),
                  ),
                ),
            const Divider(),
            // 新建定时器
            Text('新建定时器', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedFuncId != null &&
                      functions.any((f) => f.id == _selectedFuncId)
                  ? _selectedFuncId
                  : null,
              decoration: const InputDecoration(
                labelText: '选择函数',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final f in functions)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() => _selectedFuncId = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '间隔（毫秒）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _selectedFuncId == null
                      ? null
                      : () {
                          final ms = int.tryParse(_intervalController.text);
                          if (ms == null || ms <= 0) return;
                          ref
                              .read(uiMutatorProvider.notifier)
                              .setTimerEntry(_selectedFuncId!, ms);
                        },
                  child: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 外部触发占位
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('外部触发（推送 / 深链）v1 暂未实现')),
                );
              },
              icon: const Icon(Icons.link),
              label: const Text('外部触发（推送 / 深链 · v1 暂未实现）'),
            ),
          ],
        ),
      ),
    );
  }
}
