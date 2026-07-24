import 'dart:convert';

/// 插件配置存储抽象。
///
/// 持久化插件配置（API Key 等），按 pluginId 命名空间隔离。
/// **敏感配置（API Key）仅存于此，不写入项目 JSON**。
///
/// 每个插件的完整 config map 序列化为单条 JSON 存储，key 形如
/// `plugin_config.<pluginId>`，避免 secret 字段单独管理带来的复杂度，
/// 同时保证整个 config 与插件绑定、随插件删除而清理。
///
/// 平台实现：
/// - 非 Web：[SecurePluginConfigStorage]（flutter_secure_storage）。
/// - Web：[SharedPrefsPluginConfigStorage]（shared_preferences / localStorage）。
abstract class PluginConfigStorage {
  /// 存储 key 前缀。
  static const String keyPrefix = 'plugin_config.';

  /// 拼接某插件配置的存储 key。
  static String keyOf(String pluginId) => '$keyPrefix$pluginId';

  /// 读取某插件的完整配置 map（不存在返回空 map）。
  Future<Map<String, dynamic>> getPluginConfig(String pluginId);

  /// 写入某插件的完整配置 map（整体覆盖）。
  Future<void> setPluginConfig(
      String pluginId, Map<String, dynamic> config);

  /// 删除某插件的全部配置。
  Future<void> deletePluginConfig(String pluginId);

  /// 反序列化工具：将 raw JSON 字符串解析为 config map。
  /// 损坏数据降级为空配置，避免阻塞 UI。
  static Map<String, dynamic> decodeConfig(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } catch (_) {
      return const {};
    }
  }
}
