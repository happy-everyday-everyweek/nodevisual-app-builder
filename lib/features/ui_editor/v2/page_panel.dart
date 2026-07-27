import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/page.dart';
import '../../../data/models/ui_tree.dart';
import '../ui_editor_providers.dart';

/// 页面管理面板（Phase 4 v2）。
///
/// 展示项目所有 Page 节点（[Project.ui] 中 type=='page' 的节点），
/// 支持新建页面、重命名、删除（仅当 >1 页时）、设为首页。
///
/// 点击页面卡片 → 切换 [selectedPageIdProvider]，画布同步渲染该 Page。
/// 双击页面卡片 → 选中该 Page 节点本身（属性面板显示 Page 参数）。
class PagePanel extends ConsumerWidget {
  const PagePanel({super.key, this.scrollController});

  /// 可选滚动控制器（用于在 BottomSheet 中同步滚动）。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final project = ref.watch(uiMutatorProvider);
    final selectedPageId = ref.watch(selectedPageIdProvider);

    if (project == null) {
      return Center(
        child: Text(
          '未打开项目',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final pages =
        project.ui.where((n) => n.isPage).toList(growable: false);
    final canDelete = pages.length > 1;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Icon(Icons.pages, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text('页面', style: theme.textTheme.titleSmall),
            const Spacer(),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建'),
              onPressed: () => _addPage(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pages.isEmpty)
          _EmptyHint(
            icon: Icons.layers_clear_outlined,
            text: '请先创建页面',
            subtext: '点击右上角"新建"按钮添加第一个页面',
            theme: theme,
          )
        else
          for (final page in pages)
            _PageCard(
              page: page,
              selected: page.id == selectedPageId,
              canDelete: canDelete,
              onTap: () {
                ref.read(selectedPageIdProvider.notifier).state = page.id;
              },
            ),
      ],
    );
  }

  Future<void> _addPage(BuildContext context, WidgetRef ref) async {
    final name = await _promptString(
      context,
      title: '新建页面',
      hint: '页面名',
    );
    if (name == null || name.trim().isEmpty) return;
    final created =
        ref.read(uiMutatorProvider.notifier).addPage(name.trim());
    if (created != null) {
      // 新建后自动选中。
      ref.read(selectedPageIdProvider.notifier).state = created.id;
    }
  }
}

/// 单个页面卡片。
class _PageCard extends ConsumerWidget {
  const _PageCard({
    required this.page,
    required this.selected,
    required this.canDelete,
    required this.onTap,
  });

  final UiNode page;
  final bool selected;
  final bool canDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mutator = ref.read(uiMutatorProvider.notifier);

    return Card(
      elevation: 0,
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.45)
          : cs.surfaceContainerHigh.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 1.5 : 0.75,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Icon(
                page.isHomePage ? Icons.home : Icons.article_outlined,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      page.pageName ?? '未命名页面',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (page.pageRoute != null &&
                        page.pageRoute!.isNotEmpty)
                      Text(
                        '路由：${page.pageRoute}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        '${page.children.length} 个根组件',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (page.isHomePage)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '首页',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: '页面操作',
                onSelected: (v) {
                  switch (v) {
                    case 'home':
                      mutator.updatePage(page.id, isHome: true);
                    case 'rename':
                      _rename(context, ref, page);
                    case 'select':
                      // 选中 Page 节点本身（属性面板显示 Page 参数）。
                      ref
                          .read(uiMutatorProvider.notifier)
                          .selectComponent(page.id);
                  }
                },
                itemBuilder: (ctx) => [
                  if (!page.isHomePage)
                    const PopupMenuItem(
                      value: 'home',
                      child: Text('设为首页'),
                    ),
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('重命名'),
                  ),
                  const PopupMenuItem(
                    value: 'select',
                    child: Text('编辑页面属性'),
                  ),
                  if (canDelete)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '删除页面',
                        style: TextStyle(color: cs.error),
                      ),
                      onTap: () {
                        // 用 onTap 而非 onSelected 避免菜单关闭前
                        // 弹确认框导致层级冲突。
                        Future.microtask(
                          () => _confirmDelete(ctx, ref, page.id),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    UiNode page,
  ) async {
    final name = await _promptString(
      context,
      title: '重命名页面',
      hint: '页面名',
      initial: page.pageName ?? '',
    );
    if (name == null || name.trim().isEmpty) return;
    ref.read(uiMutatorProvider.notifier).updatePage(
          page.id,
          name: name.trim(),
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String pageId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除页面'),
        content: const Text('删除后不可恢复，且关联的页面事件绑定也会清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(uiMutatorProvider.notifier).removePage(pageId);
      // 清理选中态。
      if (ref.read(selectedPageIdProvider) == pageId) {
        ref.read(selectedPageIdProvider.notifier).state = null;
      }
      if (ref.read(selectedUiNodeIdProvider) == pageId) {
        ref.read(uiMutatorProvider.notifier).selectComponent(null);
      }
    }
  }
}

/// 空状态提示。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.text,
    required this.subtext,
    required this.theme,
  });

  final IconData icon;
  final String text;
  final String subtext;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
