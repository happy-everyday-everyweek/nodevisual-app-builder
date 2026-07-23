import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/project.dart';
import '../build_artifact.dart';
import '../build_manifest.dart';
import '../build_progress.dart';
import '../build_target.dart';
import '../platform_builder.dart';

/// Android 平台构建器（v1：生成 `.nvapk` 包 + 运行时说明）。
///
/// v1 设计取舍：
/// 在 Android 设备上无法直接调用 `flutter build` 生成 APK（Flutter SDK
/// 不在端侧）。本构建器采用 **IR bundle 模型**：
/// - 将 IR + manifest + 运行时说明打包为 `.nvapk` 文件（实质为 ZIP）
/// - 该文件可被 **NodeVisual Runner**（同伴应用）打开并执行
/// - 同时生成 README 说明端侧 APK 编译的限制与 v1.1 路线
///
/// v1.1 计划（标记，未实现）：
/// - 预构建 Flutter Android 壳 APK 模板（捆绑在 builder 应用 assets 中）
/// - 注入 IR 到壳 APK 的 assets/
/// - 用端侧实现的 APK 签名器（RSA + SHA256）重签
/// - 输出可直接安装的 APK
///
/// 全程端侧完成，不依赖云服务。
class AndroidBuilder with BuilderUtils implements PlatformBuilder {
  @override
  String get target => 'android';

  @override
  Future<BuildArtifact> build({
    required Project project,
    required Directory outDir,
    required BuildManifest manifest,
    required void Function(BuildProgress progress) onProgress,
  }) async {
    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 10,
      message: '准备输出目录...',
    ));

    // 子目录：android/
    final androidDir = Directory(p.join(outDir.path, 'android'));
    if (androidDir.existsSync()) androidDir.deleteSync(recursive: true);
    androidDir.createSync(recursive: true);

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 25,
      message: '序列化 IR JSON...',
    ));
    writeIr(androidDir, project);

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 40,
      message: '写入 manifest...',
    ));
    writeManifest(androidDir, manifest);

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 55,
      message: '生成运行时说明...',
    ));
    final runnerSpecFile = File(p.join(androidDir.path, 'RUNNER_SPEC.md'));
    runnerSpecFile.writeAsStringSync(_runnerSpec(project));

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 70,
      message: '生成 README...',
    ));
    final readmeFile = File(p.join(androidDir.path, 'README.md'));
    readmeFile.writeAsStringSync(_readmeMd(project));

    onProgress(const BuildProgress(
      phase: 'Android',
      percent: 85,
      message: '打包 .nvapk...',
    ));

    final nvapkPath = artifactPath(
      outDir,
      project.meta.name,
      'android',
      BuildTarget.android.bundleExtension,
    );
    if (nvapkPath.existsSync()) nvapkPath.deleteSync();

    final archive = Archive();
    for (final entity in androidDir.listSync(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: androidDir.path);
        final bytes = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Android .nvapk 打包失败');
    }
    nvapkPath.writeAsBytesSync(zipBytes);

    onProgress(BuildProgress(
      phase: 'Android',
      percent: 100,
      message: 'Android 构建完成（${(zipBytes.length / 1024).toStringAsFixed(1)} KB）',
      isCompleted: true,
    ));

    androidDir.deleteSync(recursive: true);

    return BuildArtifact(
      target: BuildTarget.android,
      file: nvapkPath,
      displayName: '${project.meta.name}-android.nvapk',
      sizeBytes: nvapkPath.lengthSync(),
      builtAt: DateTime.now().toIso8601String(),
    );
  }

  /// 运行时规范（描述 .nvapk 包格式，供 NodeVisual Runner 读取）。
  String _runnerSpec(Project project) {
    return '''# NodeVisual Runner Spec

## 包格式
\`.nvapk\` 文件实质为 ZIP 压缩包，包含：

- \`manifest.json\` - 构建清单（项目元信息 + 构建信息 + 运行时要求）
- \`ir.json\` - 项目中间表示（IR），即运行时格式
- \`RUNNER_SPEC.md\` - 本文件（运行时规范说明）
- \`README.md\` - 用户可读说明

## 运行时要求
- **解释器版本**：v1
- **运行时模式**：interpreter（IR 即运行时格式，Dart 节点解释器执行）
- **目标平台**：Android
- **最低 API**：Android 21（5.0 Lollipop）
- **依赖**：Flutter 运行时（由 Runner 应用提供）

## Runner 应用职责
1. 解压 \`.nvapk\` 文件
2. 读取 \`manifest.json\` 校验版本兼容性
3. 加载 \`ir.json\` 到 [Project] 模型
4. 启动 Flutter 应用，使用 [NodeInterpreter] 执行函数
5. 渲染 \`ir.ui.tree\` 为 Flutter UI
6. 处理 UI 事件 → 触发函数 → 更新绑定

## v1 支持的节点类型
- 变量：variable_set, variable_get
- 运算：arithmetic, logic, string_op
- 流程：if, loop, function_call, return
- 数据库：db_query, db_insert, db_update, db_delete, db_create_table, db_alter_table
- 插件：plugin_*（按注册的插件 executor 执行）

## v1 限制
- Web/Windows 端不支持 db_* 与 plugin_* 节点（降级为 no-op）
- Loop 节点在 v1 不支持子图递归执行（仅展开 list 输出 item/index）
- 函数调用深度受 MAX_STEPS=10000 限制
''';
  }

  String _readmeMd(Project project) {
    return '''# ${project.meta.name} - Android 产物

由 NodeVisual App Builder 端侧生成。

## v1 说明
本产物为 \`.nvapk\` 包（IR bundle），需配合 **NodeVisual Runner** 应用运行。

## v1.1 计划
未来版本将支持直接生成可安装的 APK：
- 预构建 Flutter Android 壳 APK 模板
- 端侧注入 IR 到壳 APK
- 端侧 RSA + SHA256 重签
- 输出独立可安装 APK

## 包内容
- \`manifest.json\` - 构建清单
- \`ir.json\` - 项目 IR
- \`RUNNER_SPEC.md\` - 运行时规范
- \`README.md\` - 本文件
''';
  }
}
