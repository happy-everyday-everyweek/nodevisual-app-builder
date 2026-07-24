import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'installed_plugin_store.dart';
import 'plugin_manifest.dart';

/// 基于 [SharedPreferences] 的 [InstalledPluginStore] 实现（Web 平台）。
///
/// Web 平台不支持 dart:io（Directory / File），改用 SharedPreferences
/// （底层 localStorage）持久化已安装插件清单。
///
/// 数据布局：
/// - `web.installed_plugins.index`：JSON 数组，每项为 [PluginManifest] 序列化。
class SharedPrefsInstalledPluginStore implements InstalledPluginStore {
  SharedPrefsInstalledPluginStore();

  static const String _indexKey = 'web.installed_plugins.index';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<PluginManifest>> _readIndex() async {
    final prefs = await _sp();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <PluginManifest>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            result.add(PluginManifest.fromJson(item));
          } catch (_) {
            // 跳过损坏条目
          }
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeIndex(List<PluginManifest> manifests) async {
    final prefs = await _sp();
    final encoded = jsonEncode(
        manifests.map((m) => m.toJson()).toList());
    await prefs.setString(_indexKey, encoded);
  }

  @override
  Future<List<PluginManifest>> listInstalled() => _readIndex();

  @override
  Future<PluginManifest?> getInstalled(String pluginId) async {
    final all = await _readIndex();
    for (final m in all) {
      if (m.id == pluginId) return m;
    }
    return null;
  }

  @override
  Future<void> save(PluginManifest manifest) async {
    final all = await _readIndex();
    final idx = all.indexWhere((m) => m.id == manifest.id);
    if (idx >= 0) {
      all[idx] = manifest;
    } else {
      all.add(manifest);
    }
    await _writeIndex(all);
  }

  @override
  Future<void> remove(String pluginId) async {
    final all = await _readIndex();
    all.removeWhere((m) => m.id == pluginId);
    await _writeIndex(all);
  }

  @override
  Future<bool> isInstalled(String pluginId) async {
    final all = await _readIndex();
    return all.any((m) => m.id == pluginId);
  }
}

/// Web 平台实现入口（供 [installed_plugin_store_factory.dart] 调用）。
InstalledPluginStore createInstalledPluginStoreImpl() =>
    SharedPrefsInstalledPluginStore();
