import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_config_storage.dart';

/// 基于 [SharedPreferences] 的 [PluginConfigStorage] 实现（Web 平台）。
///
/// Web 平台不支持 flutter_secure_storage，改用 SharedPreferences
/// （底层 localStorage）持久化插件配置。
///
/// 注意：localStorage 非"安全存储"，敏感信息（API Key）以明文形式
/// 存储在浏览器中。这是 Web 平台的固有限制，UI 层仍以 obscureText
/// 隐藏输入，避免直接暴露。
class SharedPrefsPluginConfigStorage implements PluginConfigStorage {
  SharedPrefsPluginConfigStorage();

  SharedPreferences? _prefs;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<Map<String, dynamic>> getPluginConfig(String pluginId) async {
    final prefs = await _sp();
    final raw = prefs.getString(PluginConfigStorage.keyOf(pluginId));
    return PluginConfigStorage.decodeConfig(raw);
  }

  @override
  Future<void> setPluginConfig(
      String pluginId, Map<String, dynamic> config) async {
    final prefs = await _sp();
    await prefs.setString(
      PluginConfigStorage.keyOf(pluginId),
      jsonEncode(config),
    );
  }

  @override
  Future<void> deletePluginConfig(String pluginId) async {
    final prefs = await _sp();
    await prefs.remove(PluginConfigStorage.keyOf(pluginId));
  }
}

/// Web 平台实现入口（供 [plugin_config_storage_factory.dart] 调用）。
PluginConfigStorage createPluginConfigStorageImpl() =>
    SharedPrefsPluginConfigStorage();
