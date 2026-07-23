import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 插件配置安全存储。
///
/// 使用 flutter_secure_storage 持久化插件配置（API Key 等），按 pluginId
/// 命名空间隔离。**敏感配置（API Key）仅存于此，不写入项目 JSON**。
///
/// 每个插件的完整 config map 序列化为单条 JSON 存储，key 形如
/// `plugin_config.<pluginId>`，避免 secret 字段单独管理带来的复杂度，
/// 同时保证整个 config 与插件绑定、随插件删除而清理。
class PluginConfigStorage {
  PluginConfigStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// 存储 key 前缀。
  static const String _keyPrefix = 'plugin_config.';

  String _key(String pluginId) => '$_keyPrefix$pluginId';

  /// 读取某插件的完整配置 map（不存在返回空 map）。
  Future<Map<String, dynamic>> getPluginConfig(String pluginId) async {
    final raw = await _storage.read(key: _key(pluginId));
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } catch (_) {
      // 损坏数据降级为空配置，避免阻塞 UI。
      return const {};
    }
  }

  /// 写入某插件的完整配置 map（整体覆盖）。
  Future<void> setPluginConfig(String pluginId, Map<String, dynamic> config) async {
    await _storage.write(
      key: _key(pluginId),
      value: jsonEncode(config),
    );
  }

  /// 删除某插件的全部配置。
  Future<void> deletePluginConfig(String pluginId) async {
    await _storage.delete(key: _key(pluginId));
  }
}
