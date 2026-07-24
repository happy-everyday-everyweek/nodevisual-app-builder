import 'plugin_manifest.dart';

/// 已安装插件本地存储抽象。
///
/// 将安装的 [PluginManifest] 序列化为 JSON 存储，每个插件一条记录。
/// 启动时读取全部已安装清单，注册到 PluginRegistry。
///
/// 平台实现：
/// - 非 Web：[IoInstalledPluginStore]（文件系统，path_provider）。
/// - Web：[SharedPrefsInstalledPluginStore]（SharedPreferences / localStorage）。
abstract class InstalledPluginStore {
  /// 列出全部已安装插件清单。
  Future<List<PluginManifest>> listInstalled();

  /// 获取指定插件的已安装清单（未安装返回 null）。
  Future<PluginManifest?> getInstalled(String pluginId);

  /// 保存（安装）插件清单。
  Future<void> save(PluginManifest manifest);

  /// 删除（卸载）插件。
  Future<void> remove(String pluginId);

  /// 检查是否已安装。
  Future<bool> isInstalled(String pluginId);
}
