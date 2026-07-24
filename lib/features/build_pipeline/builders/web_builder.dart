import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/project.dart';
import '../build_artifact.dart';
import '../build_manifest.dart';
import '../build_progress.dart';
import '../build_target.dart';
import '../platform_builder.dart';
import 'web_runtime_template.dart';

/// Web 平台构建器。
///
/// 生成完全自包含的静态 HTML/JS 包，包含：
/// - `index.html`：入口页面
/// - `runtime.js`：节点图解释器 + UI 渲染器（嵌入 IR 也可，但 v1 选择外置）
/// - `ir.json`：项目 IR
/// - `manifest.json`：构建清单
/// - `README.md`：说明
///
/// 产物为单个 ZIP 文件，可直接部署到任意静态服务器或浏览器打开。
///
/// 全程端侧完成，不依赖云服务。
class WebBuilder with BuilderUtils implements PlatformBuilder {
  @override
  String get target => 'web';

  @override
  Future<BuildArtifact> build({
    required Project project,
    required Directory outDir,
    required BuildManifest manifest,
    required void Function(BuildProgress progress) onProgress,
  }) async {
    onProgress(const BuildProgress(
      phase: 'Web',
      percent: 10,
      message: '准备输出目录...',
    ));

    // 子目录：web/
    final webDir = Directory(p.join(outDir.path, 'web'));
    if (webDir.existsSync()) webDir.deleteSync(recursive: true);
    webDir.createSync(recursive: true);

    onProgress(const BuildProgress(
      phase: 'Web',
      percent: 25,
      message: '序列化 IR JSON...',
    ));
    writeIr(webDir, project);

    onProgress(const BuildProgress(
      phase: 'Web',
      percent: 40,
      message: '写入 manifest...',
    ));
    writeManifest(webDir, manifest);

    onProgress(const BuildProgress(
      phase: 'Web',
      percent: 55,
      message: '生成 runtime.js...',
    ));
    final runtimeFile = File(p.join(webDir.path, 'runtime.js'));
    runtimeFile.writeAsStringSync(WebRuntimeTemplate.runtimeJs());

    onProgress(const BuildProgress(
      phase: 'Web',
      percent: 70,
      message: '生成 index.html...',
    ));
    final indexFile = File(p.join(webDir.path, 'index.html'));
    indexFile.writeAsStringSync(
      WebRuntimeTemplate.indexHtml(project.meta.name),
    );

    onProgress(const BuildProgress(
      phase: 'Web',
      percent: 80,
      message: '生成 README...',
    ));
    final readmeFile = File(p.join(webDir.path, 'README.md'));
    readmeFile.writeAsStringSync(
      WebRuntimeTemplate.readmeMd(project.meta.name),
    );

    onProgress(const BuildProgress(
      phase: 'Web',
      percent: 90,
      message: '打包 ZIP...',
    ));

    // 打包为 ZIP（保留所有产物）
    final zipPath = artifactPath(
      outDir,
      project.meta.name,
      'web',
      BuildTarget.web.bundleExtension,
    );
    if (zipPath.existsSync()) zipPath.deleteSync();

    final archive = Archive();
    for (final entity in webDir.listSync(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: webDir.path);
        final bytes = entity.readAsBytesSync();
        archive.addFile(
          ArchiveFile(rel, bytes.length, bytes),
        );
      }
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Web ZIP 打包失败');
    }
    zipPath.writeAsBytesSync(zipBytes);

    onProgress(BuildProgress(
      phase: 'Web',
      percent: 100,
      message: 'Web 构建完成（${(zipBytes.length / 1024).toStringAsFixed(1)} KB）',
      isCompleted: true,
    ));

    // 清理中间目录（保留最终 ZIP）
    webDir.deleteSync(recursive: true);

    return BuildArtifact(
      target: BuildTarget.web,
      path: zipPath.path,
      displayName: '${project.meta.name}-web.zip',
      sizeBytes: zipPath.lengthSync(),
      builtAt: DateTime.now().toIso8601String(),
    );
  }
}
