import 'dart:convert';

import 'plugin_config_storage.dart';
import 'plugin_config_storage_io.dart'
    if (dart.library.html) 'plugin_config_storage_web.dart';

/// 插件配置存储工厂。
///
/// - 非 Web 平台：使用 [FlutterSecureStorage]（Android Keystore / iOS Keychain）。
/// - Web 平台：使用 [SharedPreferences]（localStorage），因为
///   flutter_secure_storage 不支持 Web。
PluginConfigStorage createPluginConfigStorage() =>
    createPluginConfigStorageImpl();
