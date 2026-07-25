import 'build_artifact.dart';
import 'artifact_download_io.dart'
    if (dart.library.html) 'artifact_download_web.dart';

/// 下载或分享构建产物（平台相关）。
///
/// - **非 Web 平台**：调用系统分享面板（share_plus），将产物文件分享出去。
/// - **Web 平台**：触发浏览器下载，将内存中的产物字节保存为本地文件。
///
/// 返回 `true` 表示已成功触发分享/下载流程（不保证用户完成操作）；
/// 返回 `false` 表示无法处理（如非 Web 平台收到仅内存产物）。
Future<bool> downloadArtifact(BuildArtifact artifact) =>
    downloadArtifactImpl(artifact);
