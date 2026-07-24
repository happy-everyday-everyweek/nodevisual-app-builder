import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plugins/plugin_config_storage.dart';
import '../plugins/plugin_registry.dart';
import '../plugins/plugin_spec.dart';
import 'http_plugin_executor.dart';
import 'marketplace_client.dart';
import 'marketplace_entry.dart';
import 'plugin_manifest.dart';

/// 市场客户端 provider（全局单例）。
final marketplaceClientProvider = Provider<MarketplaceClient>((ref) {
  final client = MarketplaceClient();
  ref.onDispose(client.dispose);
  return client;
});

/// 已安装插件存储 provider（全局单例）。
final installedPluginStoreProvider = Provider<InstalledPluginStore>((ref) {
  return InstalledPluginStore();
});

/// 已安装插件清单列表 provider。
///
/// 初始时从本地存储加载，安装/卸载后通过 [refreshInstalledPlugins] 刷新。
final installedPluginsProvider =
    StateNotifierProvider<InstalledPluginsNotifier, AsyncValue<List<PluginManifest>>>(
  (ref) => InstalledPluginsNotifier(ref),
);

class InstalledPluginsNotifier
    extends StateNotifier<AsyncValue<List<PluginManifest>>> {
  InstalledPluginsNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final store = _ref.read(installedPluginStoreProvider);
      final installed = await store.listInstalled();
      // 注册到 PluginRegistry
      _registerAll(installed);
      state = AsyncValue.data(installed);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 安装插件。
  Future<void> install(MarketplaceEntry entry) async {
    state = const AsyncValue.loading();
    try {
      final client = _ref.read(marketplaceClientProvider);
      final store = _ref.read(installedPluginStoreProvider);

      final manifest = await client.downloadPluginManifest(entry);
      await store.save(manifest);

      // 注册到 PluginRegistry
      _registerOne(manifest);

      // 刷新列表
      final installed = await store.listInstalled();
      state = AsyncValue.data(installed);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// 卸载插件。
  Future<void> uninstall(String pluginId) async {
    final store = _ref.read(installedPluginStoreProvider);
    await store.remove(pluginId);

    // 从 PluginRegistry 注销
    final registry = _ref.read(pluginRegistryProvider);
    registry.unregister(pluginId);

    // 清理插件配置
    final configStorage = _ref.read(pluginConfigStorageProvider);
    await configStorage.deletePluginConfig(pluginId);

    final installed = await store.listInstalled();
    state = AsyncValue.data(installed);
  }

  void _registerAll(List<PluginManifest> manifests) {
    for (final manifest in manifests) {
      _registerOne(manifest);
    }
  }

  void _registerOne(PluginManifest manifest) {
    final registry = _ref.read(pluginRegistryProvider);
    final spec = manifest.toPluginSpec();
    final executor = HttpPluginExecutor(manifest);
    registry.register(spec, executor);
  }

  /// 重新加载已安装列表。
  Future<void> refresh() async => _load();
}

/// 市场索引 provider（远程拉取）。
final marketplaceIndexProvider =
    FutureProvider.autoDispose<MarketplaceIndex>((ref) async {
  final client = ref.watch(marketplaceClientProvider);
  return client.fetchIndex();
});

/// 安装状态 provider（快速查询某插件是否已安装）。
final isPluginInstalledProvider = FutureProvider.family<bool, String>(
  (ref, pluginId) async {
    final store = ref.watch(installedPluginStoreProvider);
    return store.isInstalled(pluginId);
  },
);

/// 已安装插件 spec 列表（供节点编辑页选择 plugin 类型节点时使用）。
final installedPluginSpecsProvider = Provider<List<PluginSpec>>((ref) {
  final asyncInstalled = ref.watch(installedPluginsProvider);
  return asyncInstalled.maybeWhen(
    data: (manifests) =>
        manifests.map((m) => m.toPluginSpec()).toList(),
    orElse: () => const [],
  );
});
