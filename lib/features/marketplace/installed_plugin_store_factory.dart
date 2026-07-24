import 'installed_plugin_store.dart';
import 'installed_plugin_store_io.dart'
    if (dart.library.html) 'installed_plugin_store_web.dart';

/// 平台相关的 [InstalledPluginStore] 工厂。
///
/// - 非 Web 平台：返回 [IoInstalledPluginStore]（基于文件系统 / path_provider）。
/// - Web 平台：返回 [SharedPrefsInstalledPluginStore]（基于 SharedPreferences）。
InstalledPluginStore createInstalledPluginStore() =>
    createInstalledPluginStoreImpl();
