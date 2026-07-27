import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/page.dart';
import '../../../data/models/ui_tree.dart';
import '../component_registry_v2.dart';
import '../ui_editor_providers.dart';

/// 组件面板（Phase 4 v2）。
///
/// 按三大分类（展示 / 交互 / 容器）展示内置组件，使用 [ComponentRegistry.byCategory]
/// 获取组件定义列表，每个分类用 [ExpansionTile] 包裹可折叠。
///
/// 顶部带搜索框，按 type / label 过滤。
///
/// 点击组件 → 添加到当前选中 Page 的 children 列表；
/// 若当前选中了容器类组件，则添加为该容器的子组件。
/// 无 Page 时禁用添加按钮。
class ComponentPanel extends ConsumerStatefulWidget {
  const ComponentPanel({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<ComponentPanel> createState() => _ComponentPanelState();
}

class _ComponentPanelState extends ConsumerState<ComponentPanel> {
  /// 搜索关键词（按 type 或 label 模糊匹配）。
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final project = ref.watch(uiMutatorProvider);
    final selectedPageId = ref.watch(selectedPageIdProvider);

    final hasPage = project != null &&
        selectedPageId != null &&
        project.ui.any((n) => n.id == selectedPageId && n.isPage);

    final q = _query.trim().toLowerCase();
    final cats = const [
      (ComponentCategory.display, '展示', Icons.visibility_outlined),
      (ComponentCategory.interactive, '交互', Icons.touch_app_outlined),
      (ComponentCategory.container, '容器', Icons.crop_square),
    ];

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Icon(Icons.widgets_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text('组件', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            isDense: true,
            hintText: '搜索组件…',
            prefixIcon: const Icon(Icons.search, size: 18),
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        if (!hasPage) ...[
          const SizedBox(height: 12),
          _DisabledHint(theme: theme),
        ],
        const SizedBox(height: 8),
        for (final (cat, label, icon) in cats)
          _CategorySection(
            category: cat,
            label: label,
            icon: icon,
            query: q,
            enabled: hasPage,
          ),
      ],
    );
  }
}

/// 无 Page 时的禁用提示。
class _DisabledHint extends StatelessWidget {
  const _DisabledHint({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '请先创建页面，再添加组件',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类区段（可折叠 ExpansionTile）。
class _CategorySection extends ConsumerWidget {
  const _CategorySection({
    required this.category,
    required this.label,
    required this.icon,
    required this.query,
    required this.enabled,
  });

  final ComponentCategory category;
  final String label;
  final IconData icon;
  final String query;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defs = ComponentRegistry.byCategory(category);
    final filtered = query.isEmpty
        ? defs
        : defs
            .where((d) =>
                d.label.toLowerCase().contains(query) ||
                d.type.toLowerCase().contains(query))
            .toList(growable: false);

    if (filtered.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        shape: const Border(),
        collapsedShape: const Border(),
        dense: true,
        title: Row(
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              '$label（${filtered.length}）',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final def in filtered)
                _ComponentChip(
                  def: def,
                  enabled: enabled,
                  onTap: enabled
                      ? () => _addComponent(ref, def.type)
                      : () {},
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 添加组件：若选中了容器组件 → 添加为子组件；否则添加到当前 Page。
  void _addComponent(WidgetRef ref, String type) {
    final mutator = ref.read(uiMutatorProvider.notifier);
    final selectedId = ref.read(selectedUiNodeIdProvider);
    final pageId = ref.read(selectedPageIdProvider);
    // Phase 6：addComponent 强制 pageId 校验，无选中页面时无法添加。
    if (pageId == null || pageId.isEmpty) return;

    String? parentId = pageId;
    // 若选中了容器类组件，添加为该容器的子组件。
    if (selectedId != null) {
      final found = mutator.findNode(selectedId);
      if (found != null &&
          ComponentRegistry.isContainer(found.node.type)) {
        parentId = selectedId;
      }
    }
    mutator.addComponent(type, parentId: parentId, pageId: pageId);
  }
}

/// 单个组件 chip。
class _ComponentChip extends StatelessWidget {
  const _ComponentChip({
    required this.def,
    required this.enabled,
    required this.onTap,
  });

  final ComponentDef def;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 88,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant, width: 0.75),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                def.icon ?? Icons.widgets_outlined,
                color: cs.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                def.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
