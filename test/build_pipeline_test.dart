import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:nodevisual_app_builder/data/models/project.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/build_artifact.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/build_manifest.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/build_progress.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/builders/android_builder.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/builders/web_builder.dart';
import 'package:nodevisual_app_builder/features/build_pipeline/builders/windows_builder.dart';

/// 验证端侧编译管线能在内存中创建产物并打包 ZIP。
///
/// 覆盖：
/// - Web 构建器产出 ZIP，包含 index.html / runtime.js / ir.json / manifest.json / README.md
/// - Android 构建器产出 .nvapk 包，含 ir.json / manifest.json / README.md / RUNNER_SPEC.md
/// - Windows 构建器产出 .nvexe 包，含 ir.json / manifest.json / README.md
void main() {
  late Project sampleProject;
  late Directory tempDir;

  setUp(() {
    sampleProject = Project(
      meta: const ProjectMeta(
        id: 'test-proj',
        name: '测试项目',
        createdAt: '2026-01-01T00:00:00',
        updatedAt: '2026-01-01T00:00:00',
        version: '1',
      ),
    );
    tempDir = Directory.systemTemp.createTempSync('nv_build_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  BuildManifest buildManifest(String target) {
    return BuildManifest(
      target: target,
      project: ProjectInfo(
        id: sampleProject.meta.id,
        name: sampleProject.meta.name,
        irVersion: sampleProject.meta.version,
      ),
      build: const BuildInfo(
        builderVersion: '0.1.0',
        builtAt: '2026-01-01T00:00:00',
        builtOn: 'test',
      ),
      runtime: const RuntimeInfo(),
    );
  }

  test('WebBuilder 产出包含 runtime.js / index.html / ir.json / manifest.json 的 ZIP', () async {
    final builder = WebBuilder();
    final artifact = await builder.build(
      project: sampleProject,
      outDir: tempDir,
      manifest: buildManifest('web'),
      onProgress: (_) {},
    );

    expect(artifact.file.existsSync(), isTrue);
    expect(artifact.displayName, endsWith('.zip'));
    expect(artifact.sizeBytes, greaterThan(0));

    // 解压 ZIP 验证内容
    final bytes = artifact.file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, containsAll(<String>[
      'index.html',
      'runtime.js',
      'ir.json',
      'manifest.json',
      'README.md',
    ]));

    // ir.json 应能反序列化回 Project
    final irFile = archive.files.firstWhere((f) => f.name == 'ir.json');
    final irJson = jsonDecode(utf8.decode(irFile.content as List<int>))
        as Map<String, dynamic>;
    final restored = Project.fromJson(irJson);
    expect(restored.meta.name, '测试项目');

    // runtime.js 含关键标识
    final runtimeFile = archive.files.firstWhere((f) => f.name == 'runtime.js');
    final runtime = utf8.decode(runtimeFile.content as List<int>);
    expect(runtime, contains('NodeVisual Web Runtime'));
    expect(runtime, contains('runFunction'));

    // index.html 含 app-root
    final indexFile = archive.files.firstWhere((f) => f.name == 'index.html');
    final html = utf8.decode(indexFile.content as List<int>);
    expect(html, contains('app-root'));
    expect(html, contains('测试项目'));

    // manifest.json 含正确 target
    final manifestFile = archive.files.firstWhere((f) => f.name == 'manifest.json');
    final manifestJson = jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;
    expect(manifestJson['target'], 'web');
    expect(manifestJson['project']['name'], '测试项目');
  });

  test('AndroidBuilder 产出 .nvapk 包，含 RUNNER_SPEC.md', () async {
    final builder = AndroidBuilder();
    final artifact = await builder.build(
      project: sampleProject,
      outDir: tempDir,
      manifest: buildManifest('android'),
      onProgress: (_) {},
    );

    expect(artifact.file.existsSync(), isTrue);
    expect(artifact.displayName, endsWith('.nvapk'));

    final bytes = artifact.file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, containsAll(<String>[
      'ir.json',
      'manifest.json',
      'RUNNER_SPEC.md',
      'README.md',
    ]));

    final specFile = archive.files.firstWhere((f) => f.name == 'RUNNER_SPEC.md');
    final spec = utf8.decode(specFile.content as List<int>);
    expect(spec, contains('NodeVisual Runner'));
    expect(spec, contains('解释器版本'));
  });

  test('WindowsBuilder 产出 .nvexe 包，含 README 标记为 Milestone', () async {
    final builder = WindowsBuilder();
    final artifact = await builder.build(
      project: sampleProject,
      outDir: tempDir,
      manifest: buildManifest('windows'),
      onProgress: (_) {},
    );

    expect(artifact.file.existsSync(), isTrue);
    expect(artifact.displayName, endsWith('.nvexe'));

    final bytes = artifact.file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, containsAll(<String>[
      'ir.json',
      'manifest.json',
      'README.md',
    ]));

    final readmeFile = archive.files.firstWhere((f) => f.name == 'README.md');
    final readme = utf8.decode(readmeFile.content as List<int>);
    expect(readme, contains('Milestone'));
  });

  test('构建产物文件名清理非法字符', () async {
    final weirdProject = Project(
      meta: const ProjectMeta(
        id: 'p2',
        name: 'a/b:c?d',
        createdAt: '2026-01-01T00:00:00',
        updatedAt: '2026-01-01T00:00:00',
      ),
    );
    final builder = WebBuilder();
    final artifact = await builder.build(
      project: weirdProject,
      outDir: tempDir,
      manifest: buildManifest('web'),
      onProgress: (_) {},
    );

    // 文件名不应含路径分隔符
    expect(p.basename(artifact.file.path), 'a_b_c_d-web.zip');
  });
}
