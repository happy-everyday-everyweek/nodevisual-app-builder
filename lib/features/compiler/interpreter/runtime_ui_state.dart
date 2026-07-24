import '../../../data/models/ui_tree.dart';

/// 运行时 UI 状态覆盖层。
///
/// 用于 `ui_*` 控制节点在函数执行期间修改 UI 组件的运行时表现。
/// 这是一个简单的内存覆盖映射：键为组件 id，值为该组件的运行时覆盖属性
/// （如 text / visible / enabled / 任意 prop）。
///
/// 预览模式（应用内即时运行）由调用方持有本对象并在渲染时合并；
/// 编译后应用通过代码生成消费这些节点（codegen 阶段）。
class RuntimeUiState {
  RuntimeUiState();

  /// 组件 id → 运行时覆盖属性。
  final Map<String, UiRuntimeOverride> overrides = {};

  /// 设置组件文本属性（如 Text 的 content / TextField 的 hintText）。
  void setText(String componentId, String text) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.props['text'] = text;
  }

  /// 设置组件可见性。
  void setVisible(String componentId, bool visible) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.visible = visible;
  }

  /// 设置组件启用状态。
  void setEnabled(String componentId, bool enabled) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.enabled = enabled;
  }

  /// 设置组件任意属性。
  void setProp(String componentId, String key, Object? value) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.props[key] = value;
  }

  /// 导航请求（路由 + 参数）。
  UiNavRequest? lastNavRequest;

  /// Toast 请求队列（函数执行期间可多次调用）。
  final List<UiToastRequest> toasts = [];

  void navigate(String route, Map<String, dynamic> params) {
    lastNavRequest = UiNavRequest(route: route, params: params);
  }

  void showToast(String message, {String type = 'info'}) {
    toasts.add(UiToastRequest(message: message, type: type));
  }

  /// 查询某组件的运行时覆盖（不存在返回 null）。
  UiRuntimeOverride? get(String componentId) => overrides[componentId];

  /// 清空所有覆盖。
  void clear() {
    overrides.clear();
    lastNavRequest = null;
    toasts.clear();
  }
}

/// 单个组件的运行时覆盖。
class UiRuntimeOverride {
  /// 任意属性覆盖（key = prop name, value = 运行时值）。
  Map<String, Object?> props = {};

  /// 可见性覆盖（null 表示不覆盖）。
  bool? visible;

  /// 启用状态覆盖（null 表示不覆盖）。
  bool? enabled;

  /// 应用到 [UiNode.props] 的合并视图（不修改原 props）。
  Map<String, dynamic> applyTo(Map<String, dynamic> base) {
    return {...base, ...props};
  }
}

/// 导航请求。
class UiNavRequest {
  final String route;
  final Map<String, dynamic> params;
  const UiNavRequest({required this.route, required this.params});
}

/// Toast 请求。
class UiToastRequest {
  final String message;
  final String type; // info / success / error / warning
  const UiToastRequest({required this.message, required this.type});
}
