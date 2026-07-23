import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plugin_config_storage.dart';
import 'plugin_registry.dart';
import 'plugin_spec.dart';

/// 插件配置面板（底部 BottomSheet）。
///
/// 展示某插件的 [PluginSpec.configSchema]，渲染对应输入控件：
/// - [ConfigFieldType.secret]：TextField obscureText（API Key 等）；
/// - [ConfigFieldType.text]：TextField；
/// - [ConfigFieldType.number]：TextField（数字键盘）；
/// - [ConfigFieldType.bool]：Switch。
///
/// 保存时整体写入 [PluginConfigStorage]（安全存储，按 pluginId 命名空间隔离）。
/// **secret 字段仅存 secure storage，不进入项目 JSON。**
///
/// Material 3，移动端友好：高度初始 60% 屏幕，可拖拽。
class PluginConfigSheet extends ConsumerStatefulWidget {
  const PluginConfigSheet({super.key, required this.pluginId});

  /// 要配置的插件 id。
  final String pluginId;

  /// 以底部 BottomSheet 形式弹出配置面板。
  /// 返回 true 表示已保存，false / null 表示取消。
  static Future<bool?> show(BuildContext context, {required String pluginId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PluginConfigSheet(pluginId: pluginId),
    );
  }

  @override
  ConsumerState<PluginConfigSheet> createState() => _PluginConfigSheetState();
}

class _PluginConfigSheetState extends ConsumerState<PluginConfigSheet> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};
  Map<String, dynamic> _config = {};
  bool _loading = true;
  bool _saving = false;

  PluginSpec? get _spec =>
      ref.read(pluginRegistryProvider).get(widget.pluginId)?.spec;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final storage = ref.read(pluginConfigStorageProvider);
    final config = await storage.getPluginConfig(widget.pluginId);
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
    // 初始化各字段控制器。
    final spec = _spec;
    if (spec != null) {
      for (final f in spec.configSchema) {
        final existing = _config[f.key];
        final value = existing ?? f.defaultValue;
        if (f.type == ConfigFieldType.bool) {
          _boolValues[f.key] = value == true;
        } else {
          _controllers[f.key] = TextEditingController(
            text: value?.toString() ?? '',
          );
        }
      }
    }
  }

  Future<void> _save() async {
    final spec = _spec;
    if (spec == null) return;
    setState(() => _saving = true);
    final newConfig = <String, dynamic>{};
    for (final f in spec.configSchema) {
      switch (f.type) {
        case ConfigFieldType.bool:
          newConfig[f.key] = _boolValues[f.key] ?? false;
        case ConfigFieldType.number:
          final raw = _controllers[f.key]?.text.trim() ?? '';
          newConfig[f.key] = num.tryParse(raw) ?? raw;
        case ConfigFieldType.text:
        case ConfigFieldType.secret:
          newConfig[f.key] = _controllers[f.key]?.text ?? '';
      }
    }
    final storage = ref.read(pluginConfigStorageProvider);
    await storage.setPluginConfig(widget.pluginId, newConfig);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = _spec;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHandle(theme),
              _buildHeader(theme, spec),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : spec == null
                        ? _buildMissing(theme)
                        : _buildFields(theme, spec, scrollController),
              ),
              if (spec != null && !_loading) _buildActions(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, PluginSpec? spec) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              spec == null ? '插件配置' : '${spec.displayName} 配置',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissing(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.extension_off,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            const Text('插件未注册'),
          ],
        ),
      ),
    );
  }

  Widget _buildFields(
    ThemeData theme,
    PluginSpec spec,
    ScrollController scrollController,
  ) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      children: [
        if (spec.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              spec.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        for (final f in spec.configSchema) _buildField(theme, f),
      ],
    );
  }

  Widget _buildField(ThemeData theme, ConfigField f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                f.label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (f.required)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '*',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const Spacer(),
              if (f.type == ConfigFieldType.secret)
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
          const SizedBox(height: 6),
          _buildInput(theme, f),
        ],
      ),
    );
  }

  Widget _buildInput(ThemeData theme, ConfigField f) {
    switch (f.type) {
      case ConfigFieldType.bool:
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            _boolValues[f.key] == true ? '已启用' : '未启用',
            style: theme.textTheme.bodyMedium,
          ),
          value: _boolValues[f.key] ?? false,
          onChanged: (v) => setState(() => _boolValues[f.key] = v),
        );
      case ConfigFieldType.number:
        return TextField(
          controller: _controllers[f.key],
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        );
      case ConfigFieldType.text:
        return TextField(
          controller: _controllers[f.key],
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        );
      case ConfigFieldType.secret:
        return TextField(
          controller: _controllers[f.key],
          obscureText: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            helperText: '敏感信息仅存安全存储，不写入项目数据',
          ),
        );
    }
  }

  Widget _buildActions() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(
          children: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
