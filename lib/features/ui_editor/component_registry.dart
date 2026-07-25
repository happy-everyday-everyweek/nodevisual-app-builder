import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../marketplace/ui_component_def.dart';

/// UI 编辑器组件分类（与 segment_view.dart 中 [ComponentCategory] 对齐）。
///
/// 插件 manifest 中的分类标识使用 [name]（如 `'display'`）。
enum PluginComponentCategory {
  layout,
  display,
  media,
  input,
  container,
  indicator;

  static PluginComponentCategory fromName(String? name) {
    if (name == null) return PluginComponentCategory.display;
    return PluginComponentCategory.values.firstWhere(
      (e) => e.name == name,
      orElse: () => PluginComponentCategory.display,
    );
  }
}

/// UI 组件插件接口（运行时元数据视图）。
///
/// 由 [ComponentRegistry] 持有，UI 编辑器据此扩展组件面板、属性面板、
/// 触发事件列表与画布渲染。
class UiComponentEntry {
  const UiComponentEntry({
    required this.def,
    required this.pluginId,
  });

  /// 组件定义（来自 manifest）。
  final UiComponentDef def;

  /// 所属插件 id（用于卸载时反向定位）。
  final String pluginId;

  /// 完整组件类型（带 `plugin_` 前缀）。
  String get type => def.fullType;

  /// 中文展示名。
  String get displayName => def.displayName;

  /// 分类。
  PluginComponentCategory get category =>
      PluginComponentCategory.fromName(def.category);

  /// 是否可容纳子节点。
  bool get canHaveChildren => def.canHaveChildren;

  /// 触发事件列表（英文标识，UI 显示时通过 `_eventLabel` 映射中文）。
  List<String> get events => def.events;
}

/// UI 组件注册表：集中登记所有由插件提供的 UI 组件类型。
///
/// **注册时机**：
/// - UI 组件插件安装时（[InstalledPluginsNotifier._registerOne]）调用
///   [register]。
/// - 卸载时调用 [unregister]。
///
/// **消费方**：UI 编辑器 segment_view.dart 通过 [componentRegistryProvider]
/// 读取所有已注册组件，扩展组件面板 / 属性面板 / 画布渲染 / 触发事件列表。
class ComponentRegistry {
  final Map<String, UiComponentEntry> _entries = {};

  /// 注册一个 UI 组件（同 type 覆盖）。
  void register(UiComponentEntry entry) {
    _entries[entry.type] = entry;
  }

  /// 按 pluginId 注销其提供的 UI 组件。
  void unregisterByPlugin(String pluginId) {
    _entries.removeWhere((_, entry) => entry.pluginId == pluginId);
  }

  /// 按组件 type 查询；未注册返回 null。
  UiComponentEntry? get(String type) => _entries[type];

  /// 判断组件 type 是否为插件提供的组件。
  bool isPluginComponent(String type) => _entries.containsKey(type);

  /// 全部已注册组件（按注册顺序）。
  List<UiComponentEntry> all() => _entries.values.toList(growable: false);
}

/// 组件注册表 provider（全局单例）。
///
/// UI 组件插件安装 / 卸载时由 [InstalledPluginsNotifier] 维护其内容；
/// UI 编辑器通过 [watch] 监听变化以刷新组件面板。
final componentRegistryProvider =
    ChangeNotifierProvider<ComponentRegistryNotifier>(
  (ref) => ComponentRegistryNotifier(),
);

/// [ComponentRegistry] 的 Riverpod 可观察包装。
///
/// 通过 [ChangeNotifier] 在注册 / 注销后通知 UI 刷新。
class ComponentRegistryNotifier extends ChangeNotifier {
  final ComponentRegistry _registry = ComponentRegistry();

  /// 只读访问内部注册表。
  ComponentRegistry get registry => _registry;

  /// 注册一个 UI 组件。
  void register(UiComponentEntry entry) {
    _registry.register(entry);
    notifyListeners();
  }

  /// 按 pluginId 注销其提供的 UI 组件。
  void unregisterByPlugin(String pluginId) {
    _registry.unregisterByPlugin(pluginId);
    notifyListeners();
  }
}

/// 插件图标名 → IconData 映射（与 UI 编辑器 `_iconFromName` 对齐的常用集合）。
IconData pluginIconFromName(String name) {
  const map = <String, IconData>{
    'widgets': Icons.widgets_outlined,
    'star': Icons.star,
    'heart': Icons.favorite,
    'home': Icons.home,
    'person': Icons.person,
    'settings': Icons.settings,
    'search': Icons.search,
    'add': Icons.add,
    'close': Icons.close,
    'check': Icons.check,
    'menu': Icons.menu,
    'share': Icons.share,
    'edit': Icons.edit,
    'delete': Icons.delete,
    'info': Icons.info,
    'warning': Icons.warning,
    'error': Icons.error,
    'clock': Icons.access_time,
    'calendar': Icons.calendar_today,
    'camera': Icons.camera_alt_outlined,
    'image': Icons.image_outlined,
    'video': Icons.smart_display,
    'music': Icons.music_note,
    'file': Icons.insert_drive_file_outlined,
    'folder': Icons.folder_outlined,
    'mail': Icons.mail_outline,
    'phone': Icons.phone,
    'map': Icons.map_outlined,
    'location': Icons.location_on_outlined,
    'cloud': Icons.cloud_outlined,
    'download': Icons.download_outlined,
    'upload': Icons.upload_outlined,
    'refresh': Icons.refresh,
    'lock': Icons.lock_outline,
    'key': Icons.key,
    'extension': Icons.extension,
    'ai': Icons.smart_toy_outlined,
  };
  return map[name] ?? Icons.widgets_outlined;
}
