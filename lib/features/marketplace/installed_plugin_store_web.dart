import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'installed_plugin_store.dart';
import 'plugin_manifest.dart';

/// 基于 [SharedPreferences] 的 [InstalledPluginStore] 实现（Web 平台）。
///
/// Web 平台不支持 dart:io（Directory / File），改用 SharedPreferences
/// （底层 localStorage）持久化已安装插件清单。
///
/// 数据布局（按插件分键，避免单键全量重写导致的配额超限）：
/// - `web.installed_plugins.ids`：JSON 数组，存所有已安装插件的 id 列表（索引）。
/// - `web.installed_plugins.manifest.<id>`：单个插件的 [PluginManifest] JSON。
///
/// 这样 save/remove 只需改索引 + 单个 manifest 键，避免把所有大体积 manifest
/// 反复全量序列化写入单键（function 类型插件 manifest 可能数百 KB）。
class SharedPrefsInstalledPluginStore implements InstalledPluginStore {
  SharedPrefsInstalledPluginStore();

  static const String _idsKey = 'web.installed_plugins.ids';
  static const String _manifestKeyPrefix = 'web.installed_plugins.manifest.';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _manifestKey(String pluginId) => '$_manifestKeyPrefix$pluginId';

  Future<List<String>> _readIds() async {
    final prefs = await _sp();
    final raw = prefs.getString(_idsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: true);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeIds(List<String> ids) async {
    final prefs = await _sp();
    await prefs.setString(_idsKey, jsonEncode(ids));
  }

  @override
  Future<List<PluginManifest>> listInstalled() async {
    final prefs = await _sp();
    final ids = await _readIds();
    final result = <PluginManifest>[];
    for (final id in ids) {
      final raw = prefs.getString(_manifestKey(id));
      if (raw == null || raw.isEmpty) continue;
      try {
        result.add(PluginManifest.fromJson(
            jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // 跳过损坏条目
      }
    }
    return result;
  }

  @override
  Future<PluginManifest?> getInstalled(String pluginId) async {
    final prefs = await _sp();
    final raw = prefs.getString(_manifestKey(pluginId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return PluginManifest.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PluginManifest manifest) async {
    final prefs = await _sp();
    final ids = await _readIds();
    // 写入单插件 manifest 键。
    await prefs.setString(
        _manifestKey(manifest.id), jsonEncode(manifest.toJson()));
    // 更新索引（若为新插件则追加）。
    if (!ids.contains(manifest.id)) {
      ids.add(manifest.id);
      await _writeIds(ids);
    }
  }

  @override
  Future<void> remove(String pluginId) async {
    final prefs = await _sp();
    final ids = await _readIds();
    // 删除单插件 manifest 键。
    await prefs.remove(_manifestKey(pluginId));
    // 更新索引。
    if (ids.remove(pluginId)) {
      await _writeIds(ids);
    }
  }

  @override
  Future<bool> isInstalled(String pluginId) async {
    final prefs = await _sp();
    return prefs.containsKey(_manifestKey(pluginId));
  }
}

/// Web 平台实现入口（供 [installed_plugin_store_factory.dart] 调用）。
InstalledPluginStore createInstalledPluginStoreImpl() =>
    SharedPrefsInstalledPluginStore();
