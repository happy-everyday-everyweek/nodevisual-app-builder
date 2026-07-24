import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/project.dart';
import '../build_artifact.dart';
import '../build_manifest.dart';
import '../build_progress.dart';
import '../build_target.dart';
import '../platform_builder.dart';

/// Windows 平台构建器（v1：生成 `.nvexe` 包，milestone）。
///
/// spec 明确："v1 优先级：Web + Android 先通，Windows 列后续里程碑"。
/// 真正的 Windows 可执行生成需要：
/// - 端侧 Flutter Windows 工具链（不可行）
/// - 或预构建 Flutter Windows 壳 + IR 注入（v1.2 计划）
///
/// v1 输出 `.nvexe` 包（IR bundle + 运行时说明），
/// 与 Android `.nvapk` 类似的策略：bundle 优先，等待 Runner 应用。
class WindowsBuilder with BuilderUtils implements PlatformBuilder {
  @override
  String get target => 'windows';

  @override
  Future<BuildArtifact> build({
    required Project project,
    required Directory outDir,
    required BuildManifest manifest,
    required void Function(BuildProgress progress) onProgress,
  }) async {
    onProgress(const BuildProgress(
      phase: 'Windows',
      percent: 10,
      message: '准备输出目录...',
    ));

    final winDir = Directory(p.join(outDir.path, 'windows'));
    if (winDir.existsSync()) winDir.deleteSync(recursive: true);
    winDir.createSync(recursive: true);

    onProgress(const BuildProgress(
      phase: 'Windows',
      percent: 25,
      message: '序列化 IR JSON...',
    ));
    writeIr(winDir, project);

    onProgress(const BuildProgress(
      phase: 'Windows',
      percent: 40,
      message: '写入 manifest...',
    ));
    writeManifest(winDir, manifest);

    onProgress(const BuildProgress(
      phase: 'Windows',
      percent: 60,
      message: '生成 README...',
    ));
    final readmeFile = File(p.join(winDir.path, 'README.md'));
    readmeFile.writeAsStringSync(_readmeMd(project));

    onProgress(const BuildProgress(
      phase: 'Windows',
      percent: 80,
      message: '打包 .nvexe...',
    ));

    final nvexePath = artifactPath(
      outDir,
      project.meta.name,
      'windows',
      BuildTarget.windows.bundleExtension,
    );
    if (nvexePath.existsSync()) nvexePath.deleteSync();

    final archive = Archive();
    for (final entity in winDir.listSync(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: winDir.path);
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Windows .nvexe 打包失败');
    }
    nvexePath.writeAsBytesSync(zipBytes);

    onProgress(BuildProgress(
      phase: 'Windows',
      percent: 100,
      message: 'Windows 构建完成（${(zipBytes.length / 1024).toStringAsFixed(1)} KB）',
      isCompleted: true,
    ));

    winDir.deleteSync(recursive: true);

    return BuildArtifact(
      target: BuildTarget.windows,
      path: nvexePath.path,
      displayName: '${project.meta.name}-windows.nvexe',
      sizeBytes: nvexePath.lengthSync(),
      builtAt: DateTime.now().toIso8601String(),
    );
  }

  String _readmeMd(Project project) {
    return '''# ${project.meta.name} - Windows 产物（Milestone）

由 NodeVisual App Builder 端侧生成。

## v1 状态：Milestone
本产物为 \`.nvexe\` 包（IR bundle），代表 spec 中"Windows 列后续里程碑"的 v1 占位。

## v1.2 计划
- 预构建 Flutter Windows 壳可执行文件夹模板（捆绑在 builder 应用 assets）
- 端侧注入 IR 到壳的运行时配置
- 输出可直接运行的 Windows 文件夹（.exe + Flutter Windows 运行时 + ir.json）

## 包内容
- \`manifest.json\` - 构建清单
- \`ir.json\` - 项目 IR
- \`README.md\` - 本文件
''';
  }
}
