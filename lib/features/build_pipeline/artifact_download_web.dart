import 'dart:html' show AnchorElement, Blob, Url, document;

import 'build_artifact.dart';

/// Web 平台的产物下载实现。
///
/// 将内存中的产物字节（[BuildArtifact.bytes]）封装为 Blob，通过创建临时
/// `<a download>` 元素并触发点击实现浏览器下载，最后释放 ObjectURL。
///
/// 此文件仅在 Web 平台编译（通过条件导入 `if (dart.library.html)`），
/// `dart:html` 在非 Web 平台不可用，因此不可直接引用。
Future<bool> downloadArtifactImpl(BuildArtifact artifact) async {
  final bytes = artifact.bytes;
  if (bytes == null) return false;

  // 构造 ZIP Blob 并生成 ObjectURL。
  final blob = Blob([bytes], 'application/zip');
  final url = Url.createObjectUrl(blob);

  // 创建隐藏 <a> 元素触发下载。
  final anchor = AnchorElement(href: url)
    ..setAttribute('download', artifact.displayName)
    ..style.display = 'none';
  document.body?.append(anchor);
  anchor.click();

  // 清理：移除元素并释放 URL。
  anchor.remove();
  Url.revokeObjectUrl(url);
  return true;
}
