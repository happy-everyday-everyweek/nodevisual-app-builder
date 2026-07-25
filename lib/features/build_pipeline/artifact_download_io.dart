import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import 'build_artifact.dart';

/// 非 Web 平台的产物下载/分享实现。
///
/// 通过 share_plus 调起系统分享面板，分享产物文件。
/// 仅适用于有文件系统路径的产物（[BuildArtifact.bytes] 为 null）。
Future<bool> downloadArtifactImpl(BuildArtifact artifact) async {
  if (artifact.bytes != null) {
    // 非 Web 平台收到仅内存产物：当前不处理（理论上不会发生）。
    return false;
  }
  await Share.shareXFiles(
    [XFile(artifact.path)],
    text: '${artifact.displayName} - 由 ${AppConstants.appName} 生成',
  );
  return true;
}
