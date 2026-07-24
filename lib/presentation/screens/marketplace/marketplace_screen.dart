import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/marketplace/marketplace_entry.dart';
import '../../../features/marketplace/marketplace_providers.dart';
import '../../../features/marketplace/plugin_manifest.dart';
import '../../../features/plugins/plugin_config_storage.dart';
import '../../../features/plugins/plugin_registry.dart';
import '../../../features/plugins/plugin_spec.dart';

/// 插件市场屏幕：浏览 / 搜索 / 安装 / 卸载 / 配置。
///
/// 两个 Tab：
/// - 市场浏览：从远程 index.json 拉取可安装插件列表。
/// - 已安装：本地已安装插件列表，支持配置与卸载。
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('插件市场'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.storefront_outlined), text: '浏览'),
            Tab(icon: Icon(Icons.download_done_outlined), text: '已安装'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              ref.invalidate(marketplaceIndexProvider);
              ref.read(installedPluginsProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 搜索栏
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索插件…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _BrowseTab(searchQuery: _searchQuery),
                  _InstalledTab(searchQuery: _searchQuery),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 浏览 Tab
// ============================================================================

class _BrowseTab extends ConsumerWidget {
  const _BrowseTab({required this.searchQuery});

  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncIndex = ref.watch(marketplaceIndexProvider);
    final asyncInstalled = ref.watch(installedPluginsProvider);

    return asyncIndex.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: '无法加载插件市场索引\n$e',
        onRetry: () => ref.invalidate(marketplaceIndexProvider),
      ),
      data: (index) {
        final installedIds = asyncInstalled.maybeWhen(
          data: (list) => list.map((m) => m.id).toSet(),
          orElse: () => <String>{},
        );

        var plugins = index.plugins;
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          plugins = plugins
              .where((p) =>
                  p.displayName.toLowerCase().contains(q) ||
                  p.description.toLowerCase().contains(q) ||
                  p.tags.any((t) => t.toLowerCase().contains(q)))
              .toList();
        }

        if (plugins.isEmpty) {
          return _EmptyState(
            icon: Icons.search_off,
            message: searchQuery.isEmpty ? '市场暂无插件' : '无匹配插件',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
          itemCount: plugins.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final entry = plugins[i];
            final isInstalled = installedIds.contains(entry.id);
            return _PluginCard(
              entry: entry,
              isInstalled: isInstalled,
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// 已安装 Tab
// ============================================================================

class _InstalledTab extends ConsumerWidget {
  const _InstalledTab({required this.searchQuery});

  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncInstalled = ref.watch(installedPluginsProvider);

    return asyncInstalled.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: '加载已安装插件失败\n$e',
        onRetry: () => ref.read(installedPluginsProvider.notifier).refresh(),
      ),
      data: (manifests) {
        var filtered = manifests;
        if (searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          filtered = filtered
              .where((m) =>
                  m.displayName.toLowerCase().contains(q) ||
                  m.description.toLowerCase().contains(q))
              .toList();
        }

        if (filtered.isEmpty) {
          return _EmptyState(
            icon: Icons.extension_off_outlined,
            message: searchQuery.isEmpty ? '尚未安装任何插件' : '无匹配插件',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final manifest = filtered[i];
            return _InstalledPluginCard(manifest: manifest);
          },
        );
      },
    );
  }
}

// ============================================================================
// 插件卡片
// ============================================================================

class _PluginCard extends ConsumerWidget {
  const _PluginCard({required this.entry, required this.isInstalled});

  final MarketplaceEntry entry;
  final bool isInstalled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => _showDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _PluginIcon(iconName: entry.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.displayName,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'v${entry.version}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: entry.tags
                            .take(4)
                            .map((t) => _TagChip(label: t))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _InstallButton(
                entry: entry,
                isInstalled: isInstalled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _PluginDetailSheet(entry: entry, isInstalled: isInstalled),
    );
  }
}

class _InstalledPluginCard extends ConsumerWidget {
  const _InstalledPluginCard({required this.manifest});

  final PluginManifest manifest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => _showConfig(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _PluginIcon(iconName: manifest.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            manifest.displayName,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'v${manifest.version}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      manifest.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 12, color: theme.colorScheme.outline),
                        const SizedBox(width: 2),
                        Text(
                          manifest.author,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.input,
                            size: 12, color: theme.colorScheme.outline),
                        const SizedBox(width: 2),
                        Text(
                          '${manifest.inputs.length}入 ${manifest.outputs.length}出',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.settings_outlined,
                    color: theme.colorScheme.primary),
                tooltip: '配置',
                onPressed: () => _showConfig(context, ref),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                tooltip: '卸载',
                onPressed: () => _confirmUninstall(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfig(BuildContext context, WidgetRef ref) {
    final spec = manifest.toPluginSpec();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _PluginConfigSheet(
        spec: spec,
        manifest: manifest,
      ),
    );
  }

  Future<void> _confirmUninstall(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定卸载 ${manifest.displayName}？\n相关配置也会被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(installedPluginsProvider.notifier).uninstall(manifest.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已卸载 ${manifest.displayName}')),
      );
    }
  }
}

// ============================================================================
// 安装按钮
// ============================================================================

class _InstallButton extends ConsumerStatefulWidget {
  const _InstallButton({required this.entry, required this.isInstalled});

  final MarketplaceEntry entry;
  final bool isInstalled;

  @override
  ConsumerState<_InstallButton> createState() => _InstallButtonState();
}

class _InstallButtonState extends ConsumerState<_InstallButton> {
  bool _installing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 状态：done（已安装）→ check / installing → spinner / idle → download
    final Widget content;
    if (widget.isInstalled && !_installing) {
      content = Icon(Icons.check_circle, color: cs.primary, size: 28);
    } else if (_installing) {
      content = const Padding(
        padding: EdgeInsets.all(2),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      content = IconButton(
        onPressed: _install,
        icon: const Icon(Icons.download, size: 18),
        padding: EdgeInsets.zero,
        splashRadius: 16,
        tooltip: '安装',
        style: IconButton.styleFrom(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.primary,
        ),
      );
    }

    // AnimatedSwitcher 实现 download → spinner → check 的原路反向切换。
    // key 区分三态；退回时（如取消选中）同样按反向曲线恢复。
    final stateKey = widget.isInstalled && !_installing
        ? const ValueKey('done')
        : _installing
            ? const ValueKey('loading')
            : const ValueKey('idle');

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      child: SizedBox(
        width: 28,
        height: 28,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: KeyedSubtree(key: stateKey, child: content),
        ),
      ),
    );
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    try {
      await ref
          .read(installedPluginsProvider.notifier)
          .install(widget.entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已安装 ${widget.entry.displayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }
}

// ============================================================================
// 插件详情 Sheet
// ============================================================================

class _PluginDetailSheet extends ConsumerWidget {
  const _PluginDetailSheet({required this.entry, required this.isInstalled});

  final MarketplaceEntry entry;
  final bool isInstalled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: _PluginIcon(iconName: entry.icon, size: 48),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(entry.displayName,
                  style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'v${entry.version} · ${entry.author}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(entry.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (entry.tags.isNotEmpty) ...[
              Text('标签', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.tags.map((t) => _TagChip(label: t)).toList(),
              ),
              const SizedBox(height: 12),
            ],
            _InfoRow(
              icon: Icons.source_outlined,
              label: '源仓库',
              value: entry.repoUrl,
            ),
            const SizedBox(height: 12),
            Text('安装后可在此应用中创建该插件节点并配置参数。'
                '插件通过 HTTP 请求模板执行，无需动态代码。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 16),
            if (!isInstalled)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _install(context, ref),
                  icon: const Icon(Icons.download),
                  label: const Text('安装'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('已安装'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(installedPluginsProvider.notifier).install(entry);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已安装 ${entry.displayName}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装失败: $e')),
        );
      }
    }
  }
}

// ============================================================================
// 插件配置 Sheet（复用已安装插件的配置编辑）
// ============================================================================

class _PluginConfigSheet extends ConsumerStatefulWidget {
  const _PluginConfigSheet({required this.spec, required this.manifest});

  final PluginSpec spec;
  final PluginManifest manifest;

  @override
  ConsumerState<_PluginConfigSheet> createState() => _PluginConfigSheetState();
}

class _PluginConfigSheetState extends ConsumerState<_PluginConfigSheet> {
  late final Map<String, TextEditingController> _controllers;
  late Map<String, dynamic> _config;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _config = {};
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final storage = ref.read(pluginConfigStorageProvider);
    _config = await storage.getPluginConfig(widget.spec.id);
    for (final field in widget.spec.configSchema) {
      final value = _config[field.key] ?? field.defaultValue ?? '';
      _controllers[field.key] = TextEditingController(text: '$value');
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec.displayName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(spec.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 16),
            if (spec.configSchema.isEmpty)
              Text('该插件无需配置', style: theme.textTheme.bodyMedium)
            else ...[
              Text('配置', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              for (final field in spec.configSchema) ...[
                _ConfigFieldEditor(
                  field: field,
                  controller: _controllers[field.key],
                  onChanged: (value) {
                    _config[field.key] = value;
                  },
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('保存配置'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // 端口信息
            Text('输入端口', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            if (spec.inputs.isEmpty)
              Text('无', style: theme.textTheme.bodySmall)
            else
              for (final input in spec.inputs)
                _PortInfoRow(
                  name: input.name,
                  type: input.type.toJson(),
                  desc: input.description,
                ),
            const SizedBox(height: 8),
            Text('输出端口', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            if (spec.outputs.isEmpty)
              Text('无', style: theme.textTheme.bodySmall)
            else
              for (final output in spec.outputs)
                _PortInfoRow(
                  name: output.name,
                  type: output.type.toJson(),
                  desc: output.description,
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final storage = ref.read(pluginConfigStorageProvider);
    await storage.setPluginConfig(widget.spec.id, _config);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存')),
      );
    }
  }
}

// ============================================================================
// 小组件
// ============================================================================

class _PluginIcon extends StatelessWidget {
  const _PluginIcon({required this.iconName, this.size = 36});

  final String iconName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _iconData(iconName),
        size: size * 0.55,
        color: theme.colorScheme.primary,
      ),
    );
  }

  IconData _iconData(String name) {
    switch (name) {
      case 'weather':
        return Icons.cloud_outlined;
      case 'http':
        return Icons.language;
      case 'translate':
        return Icons.translate;
      case 'database':
        return Icons.storage_outlined;
      case 'ai':
        return Icons.psychology_outlined;
      case 'email':
        return Icons.email_outlined;
      case 'image':
        return Icons.image_outlined;
      default:
        return Icons.extension;
    }
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            )),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PortInfoRow extends StatelessWidget {
  const _PortInfoRow({
    required this.name,
    required this.type,
    required this.desc,
  });

  final String name;
  final String type;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(name,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                )),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(
                  color: theme.colorScheme.outlineVariant, width: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(type,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(desc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfigFieldEditor extends StatelessWidget {
  const _ConfigFieldEditor({
    required this.field,
    required this.controller,
    required this.onChanged,
  });

  final ConfigField field;
  final TextEditingController? controller;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case ConfigFieldType.secret:
        return TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: field.label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.lock_outline, size: 18),
          ),
          onChanged: onChanged,
        );
      case ConfigFieldType.number:
        return TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: true,
            labelText: field.label,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            final n = num.tryParse(v);
            if (n != null) onChanged(n);
          },
        );
      case ConfigFieldType.bool:
        final bool value = controller?.text == 'true';
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          value: value,
          onChanged: (v) {
            onChanged(v);
            controller?.text = v.toString();
          },
        );
      case ConfigFieldType.text:
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            labelText: field.label,
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        );
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
