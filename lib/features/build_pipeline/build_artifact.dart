import 'dart:io';

import 'build_target.dart';

/// 编译产物。
///
/// 表示一次编译后生成的单个文件或目录。一个 [BuildTarget] 可能有多个
/// 产物（如 Web 包含 HTML + JS + IR），但通常聚合为一个打包文件。
class BuildArtifact {
  /// 产物类型（与 [BuildTarget] 对应）。
  final BuildTarget target;

  /// 产物文件路径（zip / nvapk / nvexe 等）。
  ///
  /// 指向打包后的产物文件；如为目录产物，[isDirectory] 为 true。
  final File file;

  /// 产物友好名称（用于 UI 展示与分享）。
  final String displayName;

  /// 文件大小（字节）。
  final int sizeBytes;

  /// 是否为目录产物（未压缩为单文件）。
  final bool isDirectory;

  /// 构建时间（ISO8601）。
  final String builtAt;

  const BuildArtifact({
    required this.target,
    required this.file,
    required this.displayName,
    required this.sizeBytes,
    required this.builtAt,
    this.isDirectory = false,
  });

  /// 大小友好字符串（B / KB / MB）。
  String get sizeFormatted {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  @override
  String toString() =>
      'BuildArtifact($target, $displayName, ${sizeFormatted})';
}
