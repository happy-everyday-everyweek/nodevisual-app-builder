import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/project.dart';
import '../../data/models/project_version.dart';
import '../build_pipeline/artifact_download.dart';
import '../build_pipeline/build_artifact.dart';
import '../build_pipeline/build_providers.dart';
import '../build_pipeline/build_result.dart';
import '../build_pipeline/build_target.dart';
import '../project/project_providers.dart';
import 'publish_providers.dart';

/// 发布段视图。
///
/// 包含两个步骤：
/// 1. **编译**：选择目标平台 → 编译打包 → 产物列表（与原 BuildScreen 等价）。
/// 2. **分发**：连接 GitHub 账号 → 填写版本说明 → 一键发布到 GitHub
///    （自动创建仓库 / 推送 main + gh-pages / 创建 Release）。
///
/// 顶部还有版本管理区：显示当前版本、可选 bump（patch/minor/major）、
/// 版本历史列表。
///
/// 整体布局参照 [FunctionsSegmentView] / [DatabaseSegmentView]：
/// `SafeArea` + `top: 72` 为悬浮 CapsuleTopBar 让出空间，
/// 内容用可滚动 ListView 承载。
class PublishSegmentView extends ConsumerStatefulWidget {
  const PublishSegmentView({super.key});

  @override
  ConsumerState<PublishSegmentView> createState() =>
      _PublishSegmentViewState();
}

class _PublishSegmentViewState extends ConsumerState<PublishSegmentView> {
  /// 版本 bump 选择（patch / minor / major）。
  _BumpKind _bump = _BumpKind.patch;

  /// 自定义版本号覆盖（用户输入则优先于 bump）。
  final TextEditingController _versionOverride = TextEditingController();

  /// 发布说明。
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _versionOverride.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// 计算目标版本号。
  ///
  /// 优先使用用户输入的自定义版本号；否则基于当前 semver + bump。
  /// 解析失败回退到 "0.1.0"。
  String get _targetSemver {
    final custom = _versionOverride.text.trim();
    if (custom.isNotEmpty && SemVer.isValid(custom)) return custom;
    final project = ref.read(currentProjectProvider);
    final current = SemVer.tryParse(project?.meta.semver ?? '0.1.0') ??
        SemVer(0, 1, 0);
    switch (_bump) {
      case _BumpKind.patch:
        return current.bumpPatch().toString();
      case _BumpKind.minor:
        return current.bumpMinor().toString();
      case _BumpKind.major:
        return current.bumpMajor().toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);

    if (project == null) {
      return const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: Text('未打开项目')),
        ),
      );
    }

    final versions = ref.watch(projectVersionsProvider(project.meta.id));

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 72),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _VersionCard(
              project: project,
              versions: versions.valueOrNull ?? const [],
              bump: _bump,
              onBumpChange: (v) => setState(() => _bump = v),
              versionOverride: _versionOverride,
              onVersionOverrideChange: () => setState(() {}),
              targetSemver: _targetSemver,
            ),
            const SizedBox(height: 16),
            const _CompileStep(),
            const SizedBox(height: 16),
            _DistributeStep(
              notesController: _notesController,
              targetSemver: _targetSemver,
            ),
          ],
        ),
      ),
    );
  }
}

/// 版本 bump 选项。
enum _BumpKind { patch, minor, major }

// ---- 版本管理区 ----

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.project,
    required this.versions,
    required this.bump,
    required this.onBumpChange,
    required this.versionOverride,
    required this.onVersionOverrideChange,
    required this.targetSemver,
  });

  final Project project;
  final List<ProjectVersion> versions;
  final _BumpKind bump;
  final ValueChanged<_BumpKind> onBumpChange;
  final TextEditingController versionOverride;
  final VoidCallback onVersionOverrideChange;
  final String targetSemver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = project.meta.semver;
    final hasHistory = versions.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('版本管理', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            // 当前版本 + 目标版本
            Row(
              children: [
                _VersionBadge(
                  label: '当前',
                  value: 'v$current',
                  color: theme.colorScheme.surfaceContainerHighest,
                  onColor: theme.colorScheme.onSurface,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                _VersionBadge(
                  label: '即将发布',
                  value: 'v$targetSemver',
                  color: theme.colorScheme.primaryContainer,
                  onColor: theme.colorScheme.onPrimaryContainer,
                ),
                const Spacer(),
                if (project.meta.githubRepoUrl != null)
                  IconButton(
                    tooltip: '打开 GitHub 仓库',
                    icon: const Icon(Icons.open_in_new, size: 20),
                    onPressed: () =>
                        launchUrl(Uri.parse(project.meta.githubRepoUrl!)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 版本 bump 选择
            Wrap(
              spacing: 8,
              children: [
                for (final kind in _BumpKind.values)
                  ChoiceChip(
                    label: Text(_bumpLabel(kind)),
                    selected: bump == kind,
                    onSelected: (_) => onBumpChange(kind),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 自定义版本号输入
            TextField(
              controller: versionOverride,
              decoration: const InputDecoration(
                hintText: '自定义版本号（如 1.0.0），留空使用上方 bump',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag, size: 18),
              ),
              onChanged: (_) => onVersionOverrideChange(),
            ),
            const SizedBox(height: 16),
            // 版本历史
            Text('版本历史', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (!hasHistory)
              Text(
                '尚未发布过版本',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...versions.map((v) => _VersionHistoryTile(version: v)),
          ],
        ),
      ),
    );
  }

  String _bumpLabel(_BumpKind k) {
    switch (k) {
      case _BumpKind.patch:
        return '+patch（修订）';
      case _BumpKind.minor:
        return '+minor（功能）';
      case _BumpKind.major:
        return '+major（破坏性）';
    }
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({
    required this.label,
    required this.value,
    required this.color,
    required this.onColor,
  });

  final String label;
  final String value;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: onColor.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: onColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionHistoryTile extends StatelessWidget {
  const _VersionHistoryTile({required this.version});
  final ProjectVersion version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dt = DateTime.tryParse(version.publishedAt);
    final dtStr = dt == null
        ? version.publishedAt
        : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: version.releaseUrl == null
          ? null
          : () => launchUrl(Uri.parse(version.releaseUrl!)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'v${version.semver}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                dtStr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (version.releaseUrl != null)
              const Icon(Icons.open_in_new, size: 14),
          ],
        ),
      ),
    );
  }
}

// ---- 步骤 1：编译 ----

class _CompileStep extends ConsumerWidget {
  const _CompileStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final targets = ref.watch(selectedBuildTargetsProvider);
    final state = ref.watch(buildStateProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StepBadge(index: 1),
                const SizedBox(width: 8),
                Text('编译', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '选择目标平台并完成端侧编译打包。产物可用于分发步骤或直接下载。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // 目标平台
            ...BuildTarget.values.map((t) {
              final on = targets.contains(t);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: CheckboxListTile(
                  value: on,
                  onChanged: (_) => ref
                      .read(selectedBuildTargetsProvider.notifier)
                      .toggle(t),
                  secondary: Icon(_iconFor(t)),
                  title: Text(t.label),
                  subtitle: Text(t.description),
                ),
              );
            }),
            const SizedBox(height: 12),
            // 构建按钮 + 进度
            _BuildAction(state: state),
            const SizedBox(height: 12),
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

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

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
          Icon(_iconFor(artifact.target),
              size: 20, color: theme.colorScheme.primary),
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
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载',
            onPressed: () async {
              final ok = await downloadArtifact(artifact);
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? '已开始下载 ${artifact.displayName}'
                      : '无法下载该产物（缺少内存数据）'),
                  duration: const Duration(seconds: 2),
                ),
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
    final path = a.path;
    if (a.isInMemory) return '内存产物';
    final parts = path.split('/');
    if (parts.length <= 2) return path;
    return '.../${parts.sublist(parts.length - 2).join('/')}';
  }
}

// ---- 步骤 2：分发 ----

class _DistributeStep extends ConsumerWidget {
  const _DistributeStep({
    required this.notesController,
    required this.targetSemver,
  });

  final TextEditingController notesController;
  final String targetSemver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(githubAuthProvider);
    final publishState = ref.watch(publishStateProvider);
    final buildState = ref.watch(buildStateProvider);

    // 当前可用的产物（来自步骤 1 编译结果）。
    final artifacts = switch (buildState) {
      BuildDone(:final result) when result.success => result.artifacts,
      _ => const <BuildArtifact>[],
    };

    final isPublishing = publishState is PublishRunning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StepBadge(index: 2),
                const SizedBox(width: 8),
                Text('分发', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '将项目开源到 GitHub：自动创建仓库、推送 main 与 gh-pages 分支、'
              '生成 Release。当前仅提供此一个渠道，其他平台可下载产物自行分发。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _GithubAuthCard(auth: auth),
            const SizedBox(height: 12),
            // 发布说明
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '发布说明（可选）',
                hintText: '本次发布的新增 / 修复 / 变更...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            // 发布按钮 + 状态
            switch (publishState) {
              PublishIdle() => FilledButton.icon(
                  onPressed: _canPublish(auth)
                      ? () => _doPublish(ref)
                      : null,
                  icon: const Icon(Icons.public),
                  label: Text('发布 v$targetSemver 到 GitHub'),
                ),
              PublishRunning(:final phase, :final message) => Column(
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
                            '$phase · $message',
                            style: theme.textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(),
                  ],
                ),
              PublishDone(:final releaseUrl, :final repoUrl) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('发布完成',
                              style: theme.textTheme.titleSmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri.parse(releaseUrl)),
                          icon: const Icon(Icons.new_releases_outlined, size: 18),
                          label: const Text('查看 Release'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri.parse(repoUrl)),
                          icon: const Icon(Icons.folder_outlined, size: 18),
                          label: const Text('打开仓库'),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(publishStateProvider.notifier).reset(),
                          child: const Text('再来一次'),
                        ),
                      ],
                    ),
                  ],
                ),
              PublishError(:final message) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: theme.colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                message,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: isPublishing
                          ? null
                          : () =>
                              ref.read(publishStateProvider.notifier).reset(),
                      child: const Text('重置'),
                    ),
                  ],
                ),
            },
            // 提示：未编译 / 未授权
            if (artifacts.isEmpty &&
                publishState is PublishIdle) ...[
              const SizedBox(height: 8),
              Text(
                '提示：尚未编译产物。仅 Web 产物会作为 GitHub Pages 部署，'
                'Android / Windows 产物会作为 Release 附件。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 是否满足发布条件：仅需已授权。
  ///
  /// 即使步骤 1 未编译产物，发布仍可创建仓库 + 推送 IR/README + 部署 gh-pages
  /// （由 [PublishNotifier] 内部生成 Web 文件）。Release 附件按实际产物上传。
  bool _canPublish(GithubAuthState auth) {
    return auth is GithubAuthAuthenticated;
  }

  Future<void> _doPublish(WidgetRef ref) async {
    final buildState = ref.read(buildStateProvider);
    final artifacts = switch (buildState) {
      BuildDone(:final result) when result.success => result.artifacts,
      _ => const <BuildArtifact>[],
    };
    await ref.read(publishStateProvider.notifier).publish(
          semver: targetSemver,
          releaseNotes: notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
          artifacts: artifacts,
        );
  }
}

/// GitHub 认证状态卡片。
class _GithubAuthCard extends ConsumerWidget {
  const _GithubAuthCard({required this.auth});
  final GithubAuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return switch (auth) {
      GithubAuthIdle() => _authPrompt(
          theme,
          icon: Icons.cloud_outlined,
          title: '连接 GitHub 账号',
          subtitle: '使用 Device Flow 授权，无需输入密码，token 仅保存在内存中。',
          action: FilledButton.icon(
            onPressed: () => ref.read(githubAuthProvider.notifier).signIn(),
            icon: const Icon(Icons.login),
            label: const Text('连接 GitHub'),
          ),
        ),
      GithubAuthPending(:final userCode, :final verificationUri) => _authPrompt(
          theme,
          icon: Icons.link_outlined,
          title: '请在浏览器中完成授权',
          subtitle: '已自动打开浏览器，请在页面输入以下用户码：',
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  userCode,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(verificationUri)),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('重新打开'),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(githubAuthProvider.notifier).reset(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      GithubAuthAuthenticated(:final user) => _authPrompt(
          theme,
          icon: Icons.check_circle,
          title: '已连接：${user.name ?? user.login}',
          subtitle: user.name == null ? user.login : '登录名：${user.login}',
          action: TextButton(
            onPressed: () => ref.read(githubAuthProvider.notifier).signOut(),
            child: const Text('登出'),
          ),
        ),
      GithubAuthError(:final message) => _authPrompt(
          theme,
          icon: Icons.error_outline,
          title: '授权失败',
          subtitle: message,
          action: FilledButton.icon(
            onPressed: () => ref.read(githubAuthProvider.notifier).signIn(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
    };
  }

  Widget _authPrompt(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
