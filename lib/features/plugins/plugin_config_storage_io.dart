import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'plugin_config_storage.dart';

/// 基于 [FlutterSecureStorage] 的 [PluginConfigStorage] 实现。
///
/// 适用于 Android（Keystore）/ iOS（Keychain）/ Windows / macOS / Linux。
/// Web 平台不支持 flutter_secure_storage，需使用 [SharedPrefsPluginConfigStorage]。
class SecurePluginConfigStorage implements PluginConfigStorage {
  SecurePluginConfigStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, dynamic>> getPluginConfig(String pluginId) async {
    final raw = await _storage.read(key: PluginConfigStorage.keyOf(pluginId));
    return PluginConfigStorage.decodeConfig(raw);
  }

  @override
  Future<void> setPluginConfig(
      String pluginId, Map<String, dynamic> config) async {
    await _storage.write(
      key: PluginConfigStorage.keyOf(pluginId),
      value: jsonEncode(config),
    );
  }

  @override
  Future<void> deletePluginConfig(String pluginId) async {
    await _storage.delete(key: PluginConfigStorage.keyOf(pluginId));
  }
}

/// IO 平台实现入口（供 [plugin_config_storage_factory.dart] 调用）。
PluginConfigStorage createPluginConfigStorageImpl() =>
    SecurePluginConfigStorage();
