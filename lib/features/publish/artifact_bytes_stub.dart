import 'dart:typed_data';

/// Web 平台的文件字节读取 stub（永远返回 null）。
///
/// Web 平台无文件系统访问能力，构建产物以 `BuildArtifact.bytes` 内存形式
/// 存在，调用方在调用此函数前已优先使用 `bytes`，因此 Web 平台走此分支
/// 时直接返回 null 即可（理论上不会触发）。
Future<Uint8List?> readArtifactFileBytesImpl(String path) async {
  return null;
}
