import 'dart:io';
import 'dart:typed_data';

/// 非 Web 平台的文件字节读取实现。
///
/// 通过 dart:io 的 [File] 读取文件系统上的产物文件。
Future<Uint8List?> readArtifactFileBytesImpl(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
