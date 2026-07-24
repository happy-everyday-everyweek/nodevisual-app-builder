import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm/anthropic_plugin.dart';
import 'llm/openai_plugin.dart';
import 'plugin_config_storage.dart';
import 'plugin_config_storage_factory.dart';
import 'plugin_spec.dart';

/// 已注册的插件条目（规格 + 执行器）。
class PluginEntry {
  const PluginEntry({required this.spec, required this.executor});

  /// 插件规格。
  final PluginSpec spec;

  /// 插件执行器（可能同时实现 [StreamPluginExecutor]）。
  final PluginExecutor executor;

  /// 是否支持流式执行。
  bool get supportsStream => executor is StreamPluginExecutor;

  /// 若支持流式，返回 [StreamPluginExecutor]，否则 null。
  StreamPluginExecutor? get streamExecutor =>
      executor is StreamPluginExecutor ? executor as StreamPluginExecutor : null;
}

/// 插件注册表。
///
/// 集中登记所有已注册插件（规格 + 执行器），提供按 id 查询与枚举。
/// 启动时内置注册 LLM 插件（OpenAI / Anthropic，见 Task 10）。
class PluginRegistry {
  PluginRegistry._(this._entries);

  final Map<String, PluginEntry> _entries;

  /// 注册插件（同 id 覆盖）。
  void register(PluginSpec spec, PluginExecutor executor) {
    _entries[spec.id] = PluginEntry(spec: spec, executor: executor);
  }

  /// 注销插件。
  void unregister(String id) {
    _entries.remove(id);
  }

  /// 按 id 查询插件条目；未注册返回 null。
  PluginEntry? get(String id) => _entries[id];

  /// 全部已注册插件条目（按注册顺序）。
  List<PluginEntry> all() => _entries.values.toList(growable: false);

  /// 是否已注册。
  bool isRegistered(String id) => _entries.containsKey(id);

  /// 全部已注册插件规格（按注册顺序）。
  List<PluginSpec> allSpecs() =>
      _entries.values.map((e) => e.spec).toList(growable: false);

  /// 构建内置插件注册表（启动时调用）。
  static PluginRegistry withBuiltins() {
    final entries = <String, PluginEntry>{};
    final registry = PluginRegistry._(entries);
    // ---- Task 10：内置 LLM 插件 ----
    registry.register(openAiPluginSpec, OpenAiExecutor());
    registry.register(anthropicPluginSpec, AnthropicExecutor());
    return registry;
  }
}

/// 插件注册表 provider（内置 LLM 插件已注册）。
final pluginRegistryProvider = Provider<PluginRegistry>((ref) {
  return PluginRegistry.withBuiltins();
});

/// 插件配置存储 provider（平台相关）。
///
/// - 非 Web 平台：基于 flutter_secure_storage。
/// - Web 平台：基于 shared_preferences（localStorage）。
final pluginConfigStorageProvider = Provider<PluginConfigStorage>((ref) {
  return createPluginConfigStorage();
});
