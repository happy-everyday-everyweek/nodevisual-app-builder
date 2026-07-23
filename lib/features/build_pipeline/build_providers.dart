import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../project/project_providers.dart';
import 'build_artifact.dart';
import 'build_pipeline.dart';
import 'build_progress.dart';
import 'build_result.dart';
import 'build_target.dart';

/// 已选中的构建目标集合（多选）。
final selectedBuildTargetsProvider =
    StateNotifierProvider<SelectedBuildTargetsNotifier, Set<BuildTarget>>(
  (ref) => SelectedBuildTargetsNotifier(),
);

class SelectedBuildTargetsNotifier extends StateNotifier<Set<BuildTarget>> {
  SelectedBuildTargetsNotifier() : super(const {BuildTarget.web});

  void toggle(BuildTarget target) {
    final next = Set<BuildTarget>.from(state);
    if (next.contains(target)) {
      next.remove(target);
    } else {
      next.add(target);
    }
    state = next;
  }

  void clear() => state = const {};
}

/// 当前构建状态。
sealed class BuildState {
  const BuildState();
}

class BuildIdle extends BuildState {
  const BuildIdle();
}

class BuildRunning extends BuildState {
  const BuildRunning(this.progress);
  final BuildProgress progress;
}

class BuildDone extends BuildState {
  const BuildDone(this.result);
  final BuildResult result;
}

/// 构建状态控制器（同时维护进度流）。
final buildStateProvider =
    StateNotifierProvider<BuildStateNotifier, BuildState>(
  (ref) => BuildStateNotifier(ref),
);

class BuildStateNotifier extends StateNotifier<BuildState> {
  BuildStateNotifier(this._ref) : super(const BuildIdle());

  final Ref _ref;

  BuildPipeline? _pipeline;

  /// 触发一次编译打包。
  Future<void> runBuild() async {
    final project = _ref.read(currentProjectProvider);
    if (project == null) {
      state = BuildDone(BuildResult.failure(
        error: '未加载项目',
        logs: const [],
        elapsedMs: 0,
      ));
      return;
    }
    final targets = _ref.read(selectedBuildTargetsProvider);
    if (targets.isEmpty) {
      state = BuildDone(BuildResult.failure(
        error: '请至少选择一个目标平台',
        logs: const [],
        elapsedMs: 0,
      ));
      return;
    }

    _pipeline?.dispose();
    _pipeline = BuildPipeline();

    // 订阅进度流。
    final sub = _pipeline!.progressStream.listen((p) {
      if (!mounted) return;
      state = BuildRunning(p);
    });

    state = const BuildRunning(BuildProgress(
      phase: '初始化',
      percent: 0,
      message: '准备构建...',
    ));

    try {
      final result = await _pipeline!.run(
        project: project,
        targets: targets.toList(),
      );
      await sub.cancel();
      if (!mounted) return;
      state = BuildDone(result);
    } catch (e, st) {
      await sub.cancel();
      if (!mounted) return;
      state = BuildDone(BuildResult.failure(
        error: '构建异常: $e\n$st',
        logs: ['[Fatal] $e'],
        elapsedMs: 0,
      ));
    }
  }

  /// 重置为 idle（清空上次构建结果）。
  void reset() {
    _pipeline?.dispose();
    _pipeline = null;
    state = const BuildIdle();
  }

  @override
  void dispose() {
    _pipeline?.dispose();
    super.dispose();
  }
}

/// 最近一次构建的产物（便于分享入口读取）。
final lastBuildArtifactsProvider = Provider<List<BuildArtifact>>((ref) {
  final s = ref.watch(buildStateProvider);
  if (s is BuildDone) return s.result.artifacts;
  return const [];
});
