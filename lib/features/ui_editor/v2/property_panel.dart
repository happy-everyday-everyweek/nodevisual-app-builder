import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/page.dart';
import '../../../data/models/ui_tree.dart';
import '../layout/layout_panel.dart';
import '../ui_editor_providers.dart';
import 'sections/params_section.dart';
import 'sections/style_section.dart';
import 'sections/triggers_section.dart';

/// 四段式属性面板（Phase 4 v2）。
///
/// 固定 4 段顺序：参数 / 布局 / 样式 / 触发；每段可折叠。
///
/// 参数段：
/// - 普通组件：根据 [ComponentDef.props] 动态渲染（[ParamsSection]）
/// - Page 组件：页面特有参数（name/route/isHome/background/safeArea）
///
/// 布局段：
/// - 普通组件：复用 [LayoutPanel]
/// - Page 组件：只读（固定填充屏幕）
///
/// 样式段：
/// - 根据 [ComponentDef.styles] 动态渲染（[StyleSection]）
/// - 末尾固定包含动画配置区
///
/// 触发段：
/// - 普通组件：根据 [ComponentDef.events] 渲染事件（[TriggersSection]）
/// - Page 组件：生命周期事件（[PageLifecycleSection]）
class PropertyPanel extends ConsumerWidget {
  const PropertyPanel({super.key, required this.node});

  final UiNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPage = node.isPage;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 标题：组件类型 + id 简写
        Row(
          children: [
            Icon(isPage ? Icons.pages : Icons.tune,
                size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isPage
                    ? '页面 · ${node.pageName ?? '未命名'}'
                    : '${node.type} · ${node.id.substring(0, 6)}',
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
        // 1. 参数段
        _CollapsibleSection(
          title: '参数',
          icon: Icons.tune_rounded,
          initiallyExpanded: true,
          child: isPage
              ? _PageParamsEditor(node: node)
              : ParamsSection(node: node),
        ),
        const SizedBox(height: 8),
        // 2. 布局段
        _CollapsibleSection(
          title: '布局',
          icon: Icons.view_quilt_rounded,
          initiallyExpanded: false,
          child: isPage
              ? const _ReadOnlyPageLayout()
              : LayoutPanel(nodeId: node.id),
        ),
        const SizedBox(height: 8),
        // 3. 样式段（仅普通组件，Page 无样式段）
        if (!isPage) ...[
          _CollapsibleSection(
            title: '样式',
            icon: Icons.palette_outlined,
            initiallyExpanded: false,
            child: StyleSection(node: node),
          ),
          const SizedBox(height: 8),
        ],
        // 4. 触发段
        _CollapsibleSection(
          title: isPage ? '页面生命周期' : '触发事件',
          icon: Icons.flash_on_outlined,
          initiallyExpanded: true,
          child: isPage
              ? PageLifecycleSection(page: node)
              : TriggersSection(node: node),
        ),
      ],
    );
  }
}

/// 可折叠段：标题行 + 展开内容。
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.initiallyExpanded,
    required this.child,
  });

  final String title;
  final IconData icon;
  final bool initiallyExpanded;
  final Widget child;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.chevron_right,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// Page 节点参数编辑器：name / route / isHome / background / safeArea。
class _PageParamsEditor extends ConsumerStatefulWidget {
  const _PageParamsEditor({required this.node});

  final UiNode node;

  @override
  ConsumerState<_PageParamsEditor> createState() => _PageParamsEditorState();
}

class _PageParamsEditorState extends ConsumerState<_PageParamsEditor> {
  late final TextEditingController _name;
  late final TextEditingController _route;
  late final TextEditingController _background;

  @override
  void initState() {
    super.initState();
    _name =
        TextEditingController(text: widget.node.pageName ?? '');
    _route =
        TextEditingController(text: widget.node.pageRoute ?? '');
    _background =
        TextEditingController(text: widget.node.pageBackground ?? '');
  }

  @override
  void didUpdateWidget(covariant _PageParamsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final name = widget.node.pageName ?? '';
    if (_name.text != name) _name.text = name;
    final route = widget.node.pageRoute ?? '';
    if (_route.text != route) _route.text = route;
    final bg = widget.node.pageBackground ?? '';
    if (_background.text != bg) _background.text = bg;
  }

  @override
  void dispose() {
    _name.dispose();
    _route.dispose();
    _background.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutator = ref.read(uiMutatorProvider.notifier);
    final node = widget.node;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 页面名
        Text('页面名', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) =>
              mutator.updatePage(node.id, name: v),
        ),
        const SizedBox(height: 8),
        // 路由
        Text('路由', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        TextField(
          controller: _route,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: '/path',
          ),
          onChanged: (v) =>
              mutator.updatePage(node.id, route: v),
        ),
        const SizedBox(height: 8),
        // 是否首页
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('设为首页'),
          value: node.isHomePage,
          onChanged: (v) =>
              v ? mutator.updatePage(node.id, isHome: true) : null,
        ),
        const SizedBox(height: 8),
        // 背景
        Text('背景颜色', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        TextField(
          controller: _background,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: '#RRGGBB',
          ),
          onChanged: (v) => mutator.updateProp(
            node.id,
            PagePropsKeys.background,
            v,
          ),
        ),
        const SizedBox(height: 8),
        // 顶部安全区域
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('顶部安全区域'),
          value: node.pageSafeAreaTop,
          onChanged: (v) => mutator.updateProp(
            node.id,
            PagePropsKeys.safeAreaTop,
            v,
          ),
        ),
        // 底部安全区域
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('底部安全区域'),
          value: node.pageSafeAreaBottom,
          onChanged: (v) => mutator.updateProp(
            node.id,
            PagePropsKeys.safeAreaBottom,
            v,
          ),
        ),
      ],
    );
  }
}

/// Page 布局段只读提示：固定填充屏幕。
class _ReadOnlyPageLayout extends StatelessWidget {
  const _ReadOnlyPageLayout();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '页面布局固定为填充屏幕（width=100%, height=100%），不可修改。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
