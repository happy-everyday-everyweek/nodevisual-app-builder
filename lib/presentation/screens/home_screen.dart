import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/repositories/project_repository.dart';
import '../../features/marketplace/marketplace_providers.dart';
import '../../features/project/project_providers.dart';

/// 主页（项目列表）屏幕。
///
/// 展示来自 [projectListProvider] 的项目列表，支持新建项目
/// （弹窗输入名称 → 创建 → 跳转编辑器）与点击项目跳转编辑器。
/// 列表为空时显示引导文案。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// 弹出新建项目对话框，返回输入名称（取消/空返回 null）。
  Future<String?> _promptProjectName(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('新建项目'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: '项目名称',
              hintText: '请输入项目名称',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  /// 新建项目流程：输入名称 → 创建 → 刷新列表 → 跳转编辑器。
  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final name = await _promptProjectName(context);
    if (name == null || name.isEmpty) return;
    final repo = ref.read(projectRepositoryProvider);
    final project = await repo.createProject(name);
    ref.invalidate(projectListProvider);
    if (!context.mounted) return;
    context.push(AppConstants.projectRoute(project.meta.id));
  }

  /// 显示关于对话框。
  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: '${AppConstants.appVersion} '
          '(build ${AppConstants.buildNumber})',
      applicationLegalese: 'MIT License',
      applicationIcon: const FlutterLogo(),
      children: const [
        SizedBox(height: 8),
        Text('端侧可视化节点编程工具'),
        SizedBox(height: 4),
        Text('通过插件市场扩展功能，支持 Android / Web / Windows 多端编译。',
            style: TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 触发已安装插件加载并注册到 PluginRegistry（启动时）。
    ref.watch(installedPluginsProvider);
    final asyncList = ref.watch(projectListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: '插件市场',
            onPressed: () => context.push(AppConstants.routeMarketplace),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '关于',
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: SafeArea(
        // 适配 Android 手势导航条 / edge-to-edge
        bottom: false,
        child: asyncList.when(
          data: (list) => list.isEmpty
              ? _EmptyState(theme: theme)
              : _ProjectList(theme: theme, projects: list),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('加载项目列表失败：$error'),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createProject(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建项目'),
      ),
    );
  }
}

/// 空列表引导文案。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hub_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('还没有项目', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '点击右下角「新建项目」开始创建\n可视化节点编程应用',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 项目列表。
///
/// 列表项入场动画：自下而上淡入 + 轻微位移（原路反向消失）。
/// 中等宽松：itemSpacing 12、padding 加大。
class _ProjectList extends StatefulWidget {
  const _ProjectList({required this.theme, required this.projects});

  final ThemeData theme;
  final List<ProjectSummary> projects;

  @override
  State<_ProjectList> createState() => _ProjectListState();
}

class _ProjectListState extends State<_ProjectList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // 首帧后启动，避免与 push 路由动画重叠。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.theme.colorScheme;
    return FadeTransition(
      opacity: _fade,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: widget.projects.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final p = widget.projects[index];
          // 错峰入场：每项延后 40ms。
          final delay = (index * 40).clamp(0, 240).toDouble();
          return _AnimatedListItem(
            controller: _ctrl,
            delay: delay,
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.surfaceContainerHigh,
                  foregroundColor: cs.onSurface,
                  child: const Icon(Icons.folder_outlined),
                ),
                title: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('更新于 ${_formatTime(p.updatedAt)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppConstants.projectRoute(p.id)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 单个列表项的入场动画包装：基于父 controller + delay 做错峰淡入。
class _AnimatedListItem extends StatelessWidget {
  const _AnimatedListItem({
    required this.controller,
    required this.delay,
    required this.child,
  });

  final Animation<double> controller;
  final double delay; // ms
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 将 controller (0..1, 320ms) 映射到 [delay, delay+200]ms 区间。
    final begin = delay / 320;
    final end = ((delay + 200) / 320).clamp(begin, 1.0).toDouble();
    final interval = Interval(
      begin,
      end,
      curve: Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = interval.transform(controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
