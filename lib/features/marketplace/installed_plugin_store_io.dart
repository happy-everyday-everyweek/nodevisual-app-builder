import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'installed_plugin_store.dart';
import 'plugin_manifest.dart';

/// 基于 [Directory] / [File]（文件系统）的 [InstalledPluginStore] 实现。
///
/// 适用于 Android / iOS / Windows / macOS / Linux。Web 平台不支持 dart:io，
/// 需使用 [SharedPrefsInstalledPluginStore]。
class IoInstalledPluginStore implements InstalledPluginStore {
  IoInstalledPluginStore();

  static const String _dirName = 'installed_plugins';

  Directory? _cacheDir;

  Future<Directory> _getDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  @override
  Future<List<PluginManifest>> listInstalled() async {
    final dir = await _getDir();
    final files = dir
        .listSync()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final manifests = <PluginManifest>[];
    for (final file in files) {
      try {
        final raw = file.readAsStringSync();
        final manifest = PluginManifest.parse(raw);
        manifests.add(manifest);
      } catch (_) {
        // 跳过损坏的清单文件
      }
    }
    return manifests;
  }

  @override
  Future<PluginManifest?> getInstalled(String pluginId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    if (!file.existsSync()) return null;
    try {
      return PluginManifest.parse(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PluginManifest manifest) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '${manifest.id}.json'));
    file.writeAsStringSync(jsonEncode(manifest.toJson()));
  }

  @override
  Future<void> remove(String pluginId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<bool> isInstalled(String pluginId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    return file.existsSync();
  }
}

/// IO 平台实现入口（供 [installed_plugin_store_factory.dart] 调用）。
InstalledPluginStore createInstalledPluginStoreImpl() =>
    IoInstalledPluginStore();
