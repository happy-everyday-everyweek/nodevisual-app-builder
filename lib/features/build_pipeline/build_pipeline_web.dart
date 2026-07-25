import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import '../../core/constants.dart';
import '../../data/ir/ir_validator.dart';
import '../../data/models/project.dart';
import 'build_artifact.dart';
import 'build_manifest.dart';
import 'build_progress.dart';
import 'build_result.dart';
import 'build_target.dart';
import 'builders/web_runtime_template.dart';

/// Web 平台的端侧编译管线（无 dart:io 依赖）。
///
/// 与 IO 平台的 [BuildPipeline] 对应，但在 Web 平台运行：
/// - **无文件系统**：所有中间产物保留在内存（`Map<String, Uint8List>`），
///   最终 ZIP 字节挂在 [BuildArtifact.bytes] 上，由 UI 层触发浏览器下载。
/// - **仅 Web 目标**：Android / Windows 目标需要原生工具链与文件系统，
///   Web 平台不可用；选择非 Web 目标时返回失败结果（不抛异常）。
/// - **完全端侧**：不调用任何网络/云服务，archive 包为纯 Dart 实现可在 Web 运行。
///
/// 该类与 `build_pipeline.dart` 中的 [BuildPipeline] 暴露相同的公共接口
/// （[progressStream] / [run] / [dispose]），通过条件导入在
/// `build_pipeline_factory.dart` 中按平台切换。
class BuildPipeline {
  BuildPipeline();

  /// 进度流（UI 层订阅）。
  final StreamController<BuildProgress> _progressController =
      StreamController<BuildProgress>.broadcast();
  Stream<BuildProgress> get progressStream => _progressController.stream;

  /// 执行一次编译打包。
  ///
  /// [project]：要编译的项目（已加载到内存）。
  /// [targets]：目标平台列表；Web 平台仅支持 [BuildTarget.web]，
  /// 其余目标会以失败结果返回但不中断其他目标。
  Future<BuildResult> run({
    required Project project,
    required List<BuildTarget> targets,
  }) async {
    final startedAt = DateTime.now();
    final logs = <String>['[Build] 开始编译 ${project.meta.name}（Web 平台）'];
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
      // 1. 校验 IR（与 IO 平台一致）。
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

      // 2. 对每个目标平台构建。
      final totalTargets = targets.length;
      for (var i = 0; i < totalTargets; i++) {
        final target = targets[i];
        final basePercent = 10 + (i * 80 ~/ totalTargets);
        final spanPercent = 80 ~/ totalTargets;

        _emitProgress(BuildProgress(
          phase: target.label,
          percent: basePercent,
          message: '${target.label} 构建（${i + 1}/$totalTargets）...',
        ));

        try {
          if (target != BuildTarget.web) {
            // Web 平台仅支持 Web 目标：Android / Windows 需原生工具链。
            final msg = '${target.label} 构建失败：Web 平台仅支持 Web 目标'
                '（${target.label}需要原生工具链与文件系统）';
            log('[Build] $msg');
            errors.add(msg);
            _emitProgress(BuildProgress(
              phase: target.label,
              percent: 100,
              message: msg,
              isCompleted: true,
              hasError: true,
            ));
            continue;
          }

          final manifest = _buildManifest(project, target);
          final artifact = await _buildWebBundle(
            project: project,
            manifest: manifest,
            basePercent: basePercent,
            spanPercent: spanPercent,
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

      // 3. 汇总。
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

  /// 构建 Web 包（内存操作，无 dart:io）。
  ///
  /// 生成与 IO 平台 [WebBuilder] 完全一致的内容：
  /// - `index.html`：入口页面
  /// - `runtime.js`：节点图解释器 + UI 渲染器
  /// - `ir.json`：项目 IR
  /// - `manifest.json`：构建清单
  /// - `README.md`：说明
  ///
  /// 全部内容以内存 `Map<String, Uint8List>` 持有，最终用 archive 打包为
  /// ZIP 字节，返回带 [BuildArtifact.bytes] 的产物。
  Future<BuildArtifact> _buildWebBundle({
    required Project project,
    required BuildManifest manifest,
    required int basePercent,
    required int spanPercent,
  }) async {
    void emit(int subPercent, String message) {
      _emitProgress(BuildProgress(
        phase: BuildTarget.web.label,
        percent: basePercent + (subPercent * spanPercent ~/ 100),
        message: message,
      ));
    }

    emit(10, '准备内存工作区...');
    final files = <String, Uint8List>{};

    emit(25, '序列化 IR JSON...');
    files['ir.json'] = _utf8(_prettyJson(project.toJson()));

    emit(40, '写入 manifest...');
    files['manifest.json'] = _utf8(_prettyJson(manifest.toJson()));

    emit(55, '生成 runtime.js...');
    files['runtime.js'] = _utf8(WebRuntimeTemplate.runtimeJs());

    emit(70, '生成 index.html...');
    files['index.html'] = _utf8(WebRuntimeTemplate.indexHtml(project.meta.name));

    emit(80, '生成 README...');
    files['README.md'] = _utf8(WebRuntimeTemplate.readmeMd(project.meta.name));

    emit(90, '打包 ZIP（内存）...');
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Web ZIP 打包失败');
    }
    final bytes = Uint8List.fromList(zipBytes);

    emit(100, 'Web 构建完成（${(bytes.length / 1024).toStringAsFixed(1)} KB）');
    _emitProgress(BuildProgress(
      phase: BuildTarget.web.label,
      percent: basePercent + spanPercent,
      message: 'Web 构建完成（${(bytes.length / 1024).toStringAsFixed(1)} KB）',
      isCompleted: true,
    ));

    final displayName = '${_sanitize(project.meta.name)}-web.zip';
    return BuildArtifact(
      target: BuildTarget.web,
      // Web 平台无文件系统路径，使用合成标识；真实数据见 bytes。
      path: 'memory:$displayName',
      displayName: displayName,
      sizeBytes: bytes.length,
      builtAt: DateTime.now().toIso8601String(),
      bytes: bytes,
    );
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

  /// 当前构建平台标识。
  ///
  /// Web 平台使用 `kIsWeb` + `defaultTargetPlatform` 推断，避免 dart:io。
  String _buildOnTag() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// 格式化 JSON 输出（缩进 2）。
  String _prettyJson(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent('  ').convert(json);

  /// 字符串转 UTF-8 字节。
  Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  /// 关闭进度流（构建完成后调用，释放资源）。
  void dispose() {
    _progressController.close();
  }
}

/// Web 平台实现入口（供 [build_pipeline_factory.dart] 条件导入调用）。
BuildPipeline createBuildPipelineImpl() => BuildPipeline();
