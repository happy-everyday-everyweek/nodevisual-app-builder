import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/project.dart';
import 'build_artifact.dart';
import 'build_manifest.dart';
import 'build_progress.dart';

/// 平台构建器接口。
///
/// 每个目标平台（Web / Android / Windows）实现此接口，由 [BuildPipeline]
/// 调度。构建器职责：
/// - 接收 IR（已序列化的 [Project]）+ 输出目录
/// - 生成平台特定产物（静态文件 / 包）
/// - 返回 [BuildArtifact]（指向产物文件）
///
/// 构建器应：
/// - 完全端侧执行，不依赖网络或云服务
/// - 通过 [onProgress] 报告进度
/// - 失败时抛异常，由 [BuildPipeline] 捕获并转为 [BuildResult.failure]
abstract class PlatformBuilder {
  /// 目标平台标识（web / android / windows）。
  String get target;

  /// 构建产物。
  ///
  /// [project]：已加载的项目 IR。
  /// [outDir]：输出目录（已存在，构建器在其下自由创建文件/子目录）。
  /// [manifest]：构建清单（已填好项目+构建元信息，构建器可补充 runtime 段）。
  /// [onProgress]：进度回调（phase, percent 0..100, message）。
  /// 返回打包后的产物文件（[BuildArtifact.file]）。
  Future<BuildArtifact> build({
    required Project project,
    required Directory outDir,
    required BuildManifest manifest,
    required void Function(BuildProgress progress) onProgress,
  });
}

/// 构建器公共工具。
///
/// 提供产物路径计算、清单写入、IR 写入等共享逻辑，
/// 各平台构建器通过 mixin 复用。
mixin BuilderUtils {
  /// 计算产物输出文件路径。
  ///
  /// `[outDir]/<projectName>-<target><ext>`。
  File artifactPath(
    Directory outDir,
    String projectName,
    String target,
    String ext,
  ) =>
      File(p.join(
        outDir.path,
        '${_sanitizeFileName(projectName)}-$target$ext',
      ));

  /// 清理文件名（去除路径分隔符与非法字符）。
  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// 写入 manifest.json 到目录（缩进 2）。
  File writeManifest(Directory dir, BuildManifest manifest) {
    final file = File(p.join(dir.path, 'manifest.json'));
    file.writeAsStringSync(_prettyJson(manifest.toJson()));
    return file;
  }

  /// 写入 ir.json 到目录（缩进 2）。
  File writeIr(Directory dir, Project project) {
    final file = File(p.join(dir.path, 'ir.json'));
    file.writeAsStringSync(_prettyJson(project.toJson()));
    return file;
  }

  /// 格式化 JSON 输出（缩进 2）。
  String _prettyJson(Map<String, dynamic> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }
}
