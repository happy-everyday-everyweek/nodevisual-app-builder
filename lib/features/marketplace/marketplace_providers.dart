import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plugins/plugin_config_storage.dart';
import '../plugins/plugin_config_storage_factory.dart';
import '../plugins/plugin_registry.dart';
import '../plugins/plugin_spec.dart';
import '../project/project_providers.dart';
import '../publish/github_publisher.dart';
import '../publish/publish_providers.dart';
import '../ui_editor/component_registry.dart';
import 'built_in_plugins.dart';
import 'function_plugin_executor.dart';
import 'http_plugin_executor.dart';
import 'installed_plugin_store.dart';
import 'installed_plugin_store_factory.dart';
import 'marketplace_client.dart';
import 'marketplace_entry.dart';
import 'plugin_manifest.dart';
import 'project_marketplace_client.dart';
import 'project_marketplace_entry.dart';

/// 市场客户端 provider（全局单例）。
final marketplaceClientProvider = Provider<MarketplaceClient>((ref) {
  final client = MarketplaceClient();
  ref.onDispose(client.dispose);
  return client;
});

/// 已安装插件存储 provider（全局单例，平台相关）。
///
/// - 非 Web 平台：基于文件系统（path_provider）。
/// - Web 平台：基于 SharedPreferences（localStorage）。
final installedPluginStoreProvider = Provider<InstalledPluginStore>((ref) {
  return createInstalledPluginStore();
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
    // 先取出 manifest，便于按类型反向注销（UI 组件 / 函数 / native）。
    final installed = await store.listInstalled();
    final manifest =
        installed.where((m) => m.id == pluginId).firstOrNull;

    await store.remove(pluginId);

    // 从 PluginRegistry 注销
    final registry = _ref.read(pluginRegistryProvider);
    registry.unregister(pluginId);

    // 从 ComponentRegistry 注销 UI 组件插件提供的组件。
    if (manifest != null && manifest.isUiComponent) {
      _ref.read(componentRegistryProvider).unregisterByPlugin(pluginId);
    }

    // 清理插件配置
    final configStorage = _ref.read(pluginConfigStorageProvider);
    await configStorage.deletePluginConfig(pluginId);

    final installedAfter = await store.listInstalled();
    state = AsyncValue.data(installedAfter);
  }

  void _registerAll(List<PluginManifest> manifests) {
    for (final manifest in manifests) {
      _registerOne(manifest);
    }
  }

  void _registerOne(PluginManifest manifest) {
    final registry = _ref.read(pluginRegistryProvider);
    // 根据执行器类型选择执行器实例：
    // - 'native'：从内置 native 执行器注册表查找（OpenAI / Anthropic 等）。
    // - 'function'：构造 FunctionPluginExecutor，解释执行嵌入的函数 IR。
    // - 'ui_component'：不注册 PluginExecutor，仅向 ComponentRegistry 注册
    //   新 UI 组件类型，由 UI 编辑器消费。
    // - 'http'（默认）：使用 HttpPluginExecutor 按 manifest 模板渲染请求。
    if (manifest.isUiComponent) {
      final def = manifest.uiComponent;
      if (def == null || def.componentType.isEmpty) {
        // ui_component 类型但缺少 uiComponent 或 componentType：跳过注册。
        return;
      }
      _ref.read(componentRegistryProvider).register(
            UiComponentEntry(def: def, pluginId: manifest.id),
          );
      // UI 组件插件不参与节点编辑页的插件调用，无需注册 PluginExecutor。
      return;
    }
    final spec = manifest.toPluginSpec();
    final PluginExecutor? executor;
    if (manifest.isNativeExecutor) {
      executor = nativePluginExecutors[manifest.id];
      if (executor == null) {
        // native 类型但未找到执行器：跳过注册，避免运行时崩溃。
        return;
      }
    } else if (manifest.isFunctionExecutor) {
      if (manifest.functionDef == null) {
        // function 类型但缺少 functionDef：跳过注册。
        return;
      }
      executor = FunctionPluginExecutor(manifest, registry);
    } else {
      executor = null;
    }
    registry.register(spec, executor ?? HttpPluginExecutor(manifest));
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

// ============================================================================
// 项目市场
// ============================================================================

/// 项目市场客户端 provider（全局单例）。
final projectMarketplaceClientProvider = Provider<ProjectMarketplaceClient>(
  (ref) {
    final client = ProjectMarketplaceClient();
    ref.onDispose(client.dispose);
    return client;
  },
);

/// 项目市场索引 provider（远程拉取）。
///
/// 拉取市场仓库的 projects.json，列出所有用户发布的项目。
/// 网络错误时返回空索引（UI 显示"市场暂无项目"）。
final projectMarketplaceIndexProvider =
  FutureProvider.autoDispose((ref) async {
  final client = ref.watch(projectMarketplaceClientProvider);
  return client.fetchIndex();
});

/// 克隆项目状态机：跟踪克隆操作的进行中 / 成功 / 失败状态。
sealed class CloneProjectState {
  const CloneProjectState();
}

class CloneProjectIdle extends CloneProjectState {
  const CloneProjectIdle();
}

class CloneProjectRunning extends CloneProjectState {
  const CloneProjectRunning(this.entryName);
  final String entryName;
}

class CloneProjectDone extends CloneProjectState {
  const CloneProjectDone(this.projectId, this.projectName);
  final String projectId;
  final String projectName;
}

class CloneProjectError extends CloneProjectState {
  const CloneProjectError(this.message);
  final String message;
}

/// 克隆项目控制器：从市场克隆项目到本地。
///
/// 调用 [ProjectMarketplaceClient.cloneProject] 下载 ir.json 并保存为
/// 本地项目。成功后通过 [CloneProjectDone] 返回新项目 id 与名称，
/// UI 据此跳转到项目编辑器。
final cloneProjectProvider =
  StateNotifierProvider<CloneProjectNotifier, CloneProjectState>(
  (ref) => CloneProjectNotifier(ref),
);

class CloneProjectNotifier extends StateNotifier<CloneProjectState> {
  CloneProjectNotifier(this._ref) : super(const CloneProjectIdle());

  final Ref _ref;

  /// 克隆市场项目到本地。
  ///
  /// 流程：
  /// 1. 通过 [ProjectMarketplaceClient.cloneProject] 下载 ir.json；
  /// 2. 保存为本地项目；
  /// 3. 刷新项目列表（[projectListProvider]）；
  /// 4. 返回新项目 id（state 转为 [CloneProjectDone]）。
  Future<void> clone(ProjectMarketplaceEntry entry) async {
    state = CloneProjectRunning(entry.name);
    try {
      final client = _ref.read(projectMarketplaceClientProvider);
      final repo = _ref.read(projectRepositoryProvider);
      final project = await client.cloneProject(entry, repo);
      // 刷新项目列表。
      _ref.invalidate(projectListProvider);
      state = CloneProjectDone(project.meta.id, project.meta.name);
    } catch (e) {
      state = CloneProjectError('克隆失败: $e');
    }
  }

  void reset() {
    state = const CloneProjectIdle();
  }
}

// ============================================================================
// 发布项目到市场
// ============================================================================

/// 发布项目到市场的状态机：跟踪 fork + PR 流程的进行中 / 成功 / 失败状态。
sealed class PublishProjectToMarketState {
  const PublishProjectToMarketState();
}

class PublishProjectToMarketIdle extends PublishProjectToMarketState {
  const PublishProjectToMarketIdle();
}

class PublishProjectToMarketRunning extends PublishProjectToMarketState {
  const PublishProjectToMarketRunning(this.phase);
  final String phase;
}

class PublishProjectToMarketDone extends PublishProjectToMarketState {
  const PublishProjectToMarketDone(this.prUrl);
  final String prUrl;
}

class PublishProjectToMarketError extends PublishProjectToMarketState {
  const PublishProjectToMarketError(this.message);
  final String message;
}

/// 发布项目到市场控制器：fork marketplace 仓库 + 更新 projects.json + 创建 PR。
///
/// 前置条件：项目已经发布到 GitHub（[Project.meta.githubRepoUrl] 非空）。
/// 调用方需在 UI 中校验此前置条件，不满足时禁用发布按钮。
final publishProjectToMarketProvider = StateNotifierProvider<
    PublishProjectToMarketNotifier, PublishProjectToMarketState>(
  (ref) => PublishProjectToMarketNotifier(ref),
);

class PublishProjectToMarketNotifier
    extends StateNotifier<PublishProjectToMarketState> {
  PublishProjectToMarketNotifier(this._ref)
      : super(const PublishProjectToMarketIdle());

  final Ref _ref;

  /// 发布当前项目到市场。
  ///
  /// [entry] 为项目市场条目（由 UI 根据项目元数据 + 标签构造）。
  /// 内部会读取 [githubAuthProvider] 获取已认证的 [GithubPublisher]，
  /// 调用 [ProjectMarketplaceClient.publishToMarketplace] 完成 fork + PR。
  Future<void> publish(ProjectMarketplaceEntry entry) async {
    final auth = _ref.read(githubAuthProvider);
    if (auth is! GithubAuthAuthenticated) {
      state = const PublishProjectToMarketError('请先连接 GitHub 账号');
      return;
    }
    state = const PublishProjectToMarketRunning('准备发布');
    try {
      final client = _ref.read(projectMarketplaceClientProvider);
      final publisher = GithubPublisher(accessToken: auth.accessToken);

      state = const PublishProjectToMarketRunning('Fork 市场仓库');
      final prUrl = await client.publishToMarketplace(
        entry: entry,
        publisher: publisher,
        userLogin: auth.user.login,
      );
      state = PublishProjectToMarketDone(prUrl);
    } catch (e) {
      state = PublishProjectToMarketError('发布到市场失败: $e');
    }
  }

  void reset() {
    state = const PublishProjectToMarketIdle();
  }
}
