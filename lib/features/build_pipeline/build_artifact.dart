import 'dart:typed_data';

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
  /// 指向打包后的产物文件路径字符串；如为目录产物，[isDirectory] 为 true。
  /// 使用 String 而非 dart:io 的 File，以兼容 Web 平台。
  ///
  /// Web 平台下若无文件系统（仅内存产物），此处填合成标识
  /// （如 `'memory:<displayName>'`），真实数据见 [bytes]。
  final String path;

  /// 产物友好名称（用于 UI 展示与分享）。
  final String displayName;

  /// 文件大小（字节）。
  final int sizeBytes;

  /// 是否为目录产物（未压缩为单文件）。
  final bool isDirectory;

  /// 构建时间（ISO8601）。
  final String builtAt;

  /// 内存产物字节（可选）。
  ///
  /// Web 平台无文件系统，构建产物以字节形式保留在内存中，由 UI 层
  /// 通过浏览器下载 API 触发下载。非 Web 平台通常为 null（直接使用 [path]）。
  final Uint8List? bytes;

  const BuildArtifact({
    required this.target,
    required this.path,
    required this.displayName,
    required this.sizeBytes,
    required this.builtAt,
    this.isDirectory = false,
    this.bytes,
  });

  /// 大小友好字符串（B / KB / MB）。
  String get sizeFormatted {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  /// 是否为内存产物（无文件系统路径，仅有 bytes）。
  bool get isInMemory => bytes != null;

  @override
  String toString() =>
      'BuildArtifact($target, $displayName, ${sizeFormatted})';
}
