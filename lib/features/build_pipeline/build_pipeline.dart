import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../data/ir/ir_serializer.dart';
import '../../data/ir/ir_validator.dart';
import '../../data/models/project.dart';
import 'build_artifact.dart';
import 'build_manifest.dart';
import 'build_progress.dart';
import 'build_result.dart';
import 'build_target.dart';
import 'builders/android_builder.dart';
import 'builders/web_builder.dart';
import 'builders/windows_builder.dart';
import 'platform_builder.dart';

/// 端侧编译管线编排器。
///
/// 协调一次编译打包的完整流程：
/// 1. 校验 IR（[IrValidator]）：引用完整性、DAG 无环、类型匹配
/// 2. 序列化 IR（[IrSerializer]）为 JSON（用于持久化与运行时加载）
/// 3. 对每个目标平台（[BuildTarget]）调用对应的 [PlatformBuilder]
/// 4. 汇总产物 + 日志，返回 [BuildResult]
///
/// 设计要点：
/// - **完全端侧**：不调用任何网络/云服务
/// - **流式进度**：通过 [progressController] 发布 [BuildProgress]
/// - **错误隔离**：单个目标失败不中断其他目标
/// - **可重入**：每次 [run] 都重新创建输出目录
class BuildPipeline {
  BuildPipeline({List<PlatformBuilder>? builders})
      : _builders = builders ?? _defaultBuilders();

  /// 注册的平台构建器。
  final List<PlatformBuilder> _builders;

  /// 进度流（UI 层订阅）。
  final StreamController<BuildProgress> _progressController =
      StreamController<BuildProgress>.broadcast();
  Stream<BuildProgress> get progressStream => _progressController.stream;

  /// 默认构建器集合。
  static List<PlatformBuilder> _defaultBuilders() => [
        WebBuilder(),
        AndroidBuilder(),
        WindowsBuilder(),
      ];

  /// 执行一次编译打包。
  ///
  /// [project]：要编译的项目（已加载到内存）
  /// [targets]：目标平台列表（不可为空）
  /// 返回 [BuildResult]：包含全部产物或首个致命错误。
  Future<BuildResult> run({
    required Project project,
    required List<BuildTarget> targets,
  }) async {
    final startedAt = DateTime.now();
    final logs = <String>['[Build] 开始编译 ${project.meta.name}'];
    final artifacts = <BuildArtifact>[];
    final errors = <String>[];
    void log(String msg) {
      logs.add(msg);
    }

    if (targets.isEmpty) {
      return BuildResult.failure(
        error: '未选择目标平台',
        logs: logs,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
    }

    try {
      // 1. 校验 IR
      _emitProgress(const BuildProgress(
        phase: '校验',
        percent: 5,
        message: '校验 IR 完整性...',
      ));
      log('[Validate] 校验 IR...');
      final issues = IrValidator.validate(project);
      final errors0 = issues
          .where((i) => i.severity == IssueSeverity.error)
          .toList();
      if (errors0.isNotEmpty) {
        final msg = 'IR 校验失败：${errors0.length} 个错误\n'
            '${errors0.take(5).map((e) => "  - ${e.message}").join("\n")}';
        log('[Validate] $msg');
        _emitProgress(BuildProgress(
          phase: '校验',
          percent: 100,
          message: msg,
          isCompleted: true,
          hasError: true,
        ));
        return BuildResult.failure(
          error: msg,
          logs: logs,
          elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        );
      }
      log('[Validate] IR 校验通过（${issues.length} 提示）');

      // 2. 准备输出目录
      _emitProgress(const BuildProgress(
        phase: '准备',
        percent: 10,
        message: '创建输出目录...',
      ));
      final outRoot = await _buildOutputRoot();
      final projectOutDir = Directory(
        p.join(outRoot.path, _sanitize(project.meta.name)),
      );
      if (projectOutDir.existsSync()) {
        projectOutDir.deleteSync(recursive: true);
      }
      projectOutDir.createSync(recursive: true);
      log('[Prepare] 输出目录: ${projectOutDir.path}');

      // 3. 对每个目标平台构建
      final totalTargets = targets.length;
      for (var i = 0; i < totalTargets; i++) {
        final target = targets[i];
        final builder = _builders.firstWhere(
          (b) => b.target == target.name,
          orElse: () => throw StateError(
            '未注册的构建器: ${target.name}',
          ),
        );
        final basePercent = 10 + (i * 80 ~/ totalTargets);
        final spanPercent = 80 ~/ totalTargets;

        _emitProgress(BuildProgress(
          phase: target.label,
          percent: basePercent,
          message: '${target.label} 构建（${i + 1}/$totalTargets）...',
        ));

        try {
          final manifest = _buildManifest(project, target);
          final targetOutDir = Directory(
            p.join(projectOutDir.path, target.name),
          )..createSync(recursive: true);

          final artifact = await builder.build(
            project: project,
            outDir: targetOutDir,
            manifest: manifest,
            onProgress: (p) {
              _emitProgress(BuildProgress(
                phase: target.label,
                percent: basePercent + (p.percent * spanPercent ~/ 100),
                message: p.message,
                isCompleted: p.isCompleted,
                hasError: p.hasError,
              ));
            },
          );
          artifacts.add(artifact);
          log('[Build] ${target.label} 完成: ${artifact.displayName} '
              '(${artifact.sizeFormatted})');
        } catch (e, st) {
          final msg = '${target.label} 构建失败: $e';
          log('[Build] $msg');
          log('[Build] stack: $st');
          errors.add(msg);
          _emitProgress(BuildProgress(
            phase: target.label,
            percent: 100,
            message: msg,
            isCompleted: true,
            hasError: true,
          ));
        }
      }

      // 4. 汇总
      final success = errors.isEmpty;
      _emitProgress(BuildProgress(
        phase: '完成',
        percent: 100,
        message: success
            ? '全部目标构建完成，共 ${artifacts.length} 个产物'
            : '部分目标失败：${errors.length} 个错误',
        isCompleted: true,
        hasError: !success,
      ));
      log('[Build] 完成，成功 $success，产物 ${artifacts.length}');

      return BuildResult(
        success: success,
        artifacts: artifacts,
        logs: logs,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        error: success ? null : errors.join('\n'),
      );
    } catch (e, st) {
      log('[Build] 致命错误: $e');
      log('[Build] stack: $st');
      _emitProgress(BuildProgress(
        phase: '错误',
        percent: 100,
        message: '编译失败: $e',
        isCompleted: true,
        hasError: true,
      ));
      return BuildResult.failure(
        error: '编译失败: $e',
        logs: logs,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        artifacts: artifacts,
      );
    }
  }

  /// 发送进度到流。
  void _emitProgress(BuildProgress p) {
    if (!_progressController.isClosed) _progressController.add(p);
  }

  /// 构建 manifest（含项目元信息、构建时间、运行时要求）。
  BuildManifest _buildManifest(Project project, BuildTarget target) {
    final now = DateTime.now().toIso8601String();
    return BuildManifest(
      target: target.name,
      project: ProjectInfo(
        id: project.meta.id,
        name: project.meta.name,
        description: project.meta.description,
        irVersion: project.meta.version,
      ),
      build: BuildInfo(
        builderVersion: AppConstants.appVersion,
        builtAt: now,
        builtOn: _buildOnTag(),
      ),
      runtime: const RuntimeInfo(),
    );
  }

  /// 当前构建平台标识（端侧构建标记）。
  String _buildOnTag() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// 构建输出根目录（位于应用文档目录下 builds/）。
  Future<Directory> _buildOutputRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'builds'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// 关闭进度流（构建完成后调用，释放资源）。
  void dispose() {
    _progressController.close();
  }
}
