import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants.dart';
import '../../../data/models/project.dart';
import '../../../features/build_pipeline/build_artifact.dart';
import '../../../features/build_pipeline/build_progress.dart';
import '../../../features/build_pipeline/build_providers.dart';
import '../../../features/build_pipeline/build_result.dart';
import '../../../features/build_pipeline/build_target.dart';
import '../../../features/project/project_providers.dart';

/// 编译打包屏幕。
///
/// 提供端侧一键编译打包流程的 UI：
/// - 多选目标平台（Web / Android / Windows）
/// - 显示当前项目名
/// - 触发编译 → 实时展示进度（[BuildProgress]）
/// - 完成后列出产物（[BuildArtifact]），支持分享 / 返回
/// - 失败时展示错误与日志
class BuildScreen extends ConsumerWidget {
  const BuildScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final targets = ref.watch(selectedBuildTargetsProvider);
    final state = ref.watch(buildStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(project?.meta.name ?? '编译打包'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        // 适配 Android 手势导航条 / edge-to-edge
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // 项目信息
            _ProjectCard(project: project),
            const SizedBox(height: 16),
            // 目标平台选择
            _TargetSelector(
              selected: targets,
              onToggle: (t) =>
                  ref.read(selectedBuildTargetsProvider.notifier).toggle(t),
            ),
            const SizedBox(height: 16),
            // 构建按钮 / 进度
            _BuildAction(state: state),
            const SizedBox(height: 16),
            // 产物列表 / 错误
            switch (state) {
              BuildDone(:final result) => _BuildResultView(result: result),
              _ => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }
}

/// 项目信息卡。
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final Project? project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (project == null) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.warning_amber, color: theme.colorScheme.error),
          title: const Text('未加载项目'),
        ),
      );
    }
    final meta = project!.meta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    meta.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'IR 版本: ${meta.version}  ·  函数 ${project!.functions.length} 个  ·  数据表 ${project!.db.length} 张',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 目标平台选择器。
class _TargetSelector extends StatelessWidget {
  const _TargetSelector({
    required this.selected,
    required this.onToggle,
  });
  final Set<BuildTarget> selected;
  final void Function(BuildTarget) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('选择目标平台', style: theme.textTheme.titleSmall),
        ),
        ...BuildTarget.values.map((t) {
          final on = selected.contains(t);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: CheckboxListTile(
              value: on,
              onChanged: (_) => onToggle(t),
              secondary: Icon(_iconFor(t)),
              title: Text(t.label),
              subtitle: Text(t.description),
            ),
          );
        }),
      ],
    );
  }

  IconData _iconFor(BuildTarget t) {
    switch (t) {
      case BuildTarget.web:
        return Icons.language;
      case BuildTarget.android:
        return Icons.android;
      case BuildTarget.windows:
        return Icons.desktop_windows;
    }
  }
}

/// 构建按钮 + 进度显示。
class _BuildAction extends ConsumerWidget {
  const _BuildAction({required this.state});
  final BuildState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return switch (state) {
      BuildIdle() => FilledButton.icon(
          onPressed: () => ref.read(buildStateProvider.notifier).runBuild(),
          icon: const Icon(Icons.build_outlined),
          label: const Text('开始编译打包'),
        ),
      BuildRunning(:final progress) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${progress.phase} · ${progress.message}',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${progress.percent}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (progress.percent / 100).clamp(0.0, 1.0),
            ),
          ],
        ),
      BuildDone() => Row(
          children: [
            FilledButton.icon(
              onPressed: () => ref.read(buildStateProvider.notifier).runBuild(),
              icon: const Icon(Icons.refresh),
              label: const Text('重新编译'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => ref.read(buildStateProvider.notifier).reset(),
              child: const Text('清空'),
            ),
          ],
        ),
    };
  }
}

/// 构建结果展示（产物列表 / 错误 / 日志）。
class _BuildResultView extends ConsumerWidget {
  const _BuildResultView({required this.result});
  final BuildResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (!result.success) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Text('编译失败',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      )),
                  const Spacer(),
                  Text('${result.elapsedMs} ms',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                result.error ?? '未知错误',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                backgroundColor: theme.colorScheme.errorContainer,
                title: Text(
                  '构建日志（${result.logs.length} 行）',
                  style: theme.textTheme.bodySmall,
                ),
                children: [
                  Container(
                    color: theme.colorScheme.surface,
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      result.logs.join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text('编译完成', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('${result.elapsedMs} ms',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            Text('产物（${result.artifacts.length}）',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            ...result.artifacts.map((a) => _ArtifactTile(artifact: a)),
            const SizedBox(height: 12),
            ExpansionTile(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              title: Text(
                '构建日志（${result.logs.length} 行）',
                style: theme.textTheme.bodySmall,
              ),
              children: [
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    result.logs.join('\n'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个产物项（含分享按钮）。
class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({required this.artifact});
  final BuildArtifact artifact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(_iconFor(artifact.target), size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artifact.displayName,
                    style: theme.textTheme.bodyMedium),
                Text(
                  '${artifact.sizeFormatted} · ${_targetPath(artifact)}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: '分享',
            onPressed: () async {
              await Share.shareXFiles(
                [XFile(artifact.file.path)],
                text: '${artifact.displayName} - 由 ${AppConstants.appName} 生成',
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _iconFor(BuildTarget t) {
    switch (t) {
      case BuildTarget.web:
        return Icons.language;
      case BuildTarget.android:
        return Icons.android;
      case BuildTarget.windows:
        return Icons.desktop_windows;
    }
  }

  String _targetPath(BuildArtifact a) {
    final path = a.file.path;
    // 缩短显示：只保留最后 2 段
    final parts = path.split(Platform.pathSeparator);
    if (parts.length <= 2) return path;
    return '.../${parts.sublist(parts.length - 2).join('/')}';
  }
}
