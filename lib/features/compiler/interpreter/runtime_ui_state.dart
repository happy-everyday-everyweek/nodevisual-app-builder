import '../../../data/models/ui_tree.dart';

/// 运行时 UI 状态覆盖层。
///
/// 用于 `ui_*` 控制节点在函数执行期间修改 UI 组件的运行时表现。
/// 这是一个简单的内存覆盖映射：键为组件 id（[UiNode.id]），值为该组件的
/// 运行时覆盖属性。
///
/// **适配新 UiNode 结构（Phase 7）**：
/// 新版 [UiNode] 含 `props / layout / style / animations / triggers` 五段。
/// 本类提供对各段的运行时覆盖能力：
/// - [UiRuntimeOverride.props]：覆盖 [UiNode.props]（含 text / value 等业务属性）。
/// - [UiRuntimeOverride.style]：覆盖 [UiNode.style]（视觉样式，如 color / fontSize）。
/// - [UiRuntimeOverride.layout]：覆盖整个 [UiNode.layout]（LayoutConfig）。
/// - [UiRuntimeOverride.triggerOverrides]：覆盖 [UiNode.triggers]（事件 → 函数 id）。
/// - [UiRuntimeOverride.visible] / [enabled]：覆盖可见性 / 启用状态。
/// - [UiRuntimeOverride.animationRequests]：运行时动画播放请求（入场/出场/触发）。
///
/// **Page 作为根节点**：Page 节点（type='page'）的 id 也可作为 key，
/// 用于覆盖页面级属性（如 background / safeArea）。Page 的生命周期触发
/// （onLoad 等）由 [PageLifecycleManager] 管理，不经过本类。
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

  /// 设置组件任意属性（覆盖 [UiNode.props] 的某一项）。
  void setProp(String componentId, String key, Object? value) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.props[key] = value;
  }

  /// 设置组件样式（覆盖 [UiNode.style] 的某一项，如 color / fontSize）。
  void setStyle(String componentId, String key, Object? value) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.style[key] = value;
  }

  /// 覆盖组件的整个 [LayoutConfig]（[UiNode.layout]）。
  void setLayout(String componentId, LayoutConfig layout) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.layout = layout;
  }

  /// 覆盖组件的某个事件触发（[UiNode.triggers] 的某一项）。
  /// [event] 为事件名（如 onTap / onLoad），[funcId] 为目标函数 id；
  /// [funcId] 为空表示删除该事件触发。
  void setTrigger(String componentId, String event, String? funcId) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    if (funcId == null || funcId.isEmpty) {
      o.triggerOverrides.remove(event);
    } else {
      o.triggerOverrides[event] = funcId;
    }
  }

  /// 请求播放组件动画（运行时触发，对应 [UiNode.animations] 中的某项）。
  /// [kind] ∈ {'entrance', 'exit', 'triggered'}；[event] 仅在 triggered 时
  /// 用于指明触发的事件名（用于在多个 triggered 动画中区分）。
  void requestAnimation(
    String componentId, {
    required String kind,
    String? event,
  }) {
    final o = overrides.putIfAbsent(componentId, () => UiRuntimeOverride());
    o.animationRequests.add(UiAnimationRequest(
      componentId: componentId,
      kind: kind,
      event: event,
    ));
  }

  /// 取出并清空所有待处理的动画请求（UI 渲染层在每帧后调用）。
  List<UiAnimationRequest> drainAnimationRequests() {
    final result = <UiAnimationRequest>[];
    for (final o in overrides.values) {
      result.addAll(o.animationRequests);
      o.animationRequests.clear();
    }
    return result;
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
///
/// 持有对 [UiNode] 各段的覆盖：props / style / layout / triggers / 动画请求。
/// UI 渲染层在渲染对应组件时合并这些覆盖到基础 [UiNode] 值。
class UiRuntimeOverride {
  /// 任意属性覆盖（key = prop name, value = 运行时值）。
  /// 覆盖 [UiNode.props] 的对应键。
  Map<String, Object?> props = {};

  /// 样式覆盖（key = style key, value = 运行时值）。
  /// 覆盖 [UiNode.style] 的对应键。
  Map<String, Object?> style = {};

  /// 布局配置覆盖（整体替换 [UiNode.layout]）。
  /// null 表示不覆盖布局。
  LayoutConfig? layout;

  /// 事件触发覆盖（key = 事件名, value = 函数 id）。
  /// 覆盖 [UiNode.triggers] 的对应键。
  Map<String, String> triggerOverrides = {};

  /// 可见性覆盖（null 表示不覆盖）。
  bool? visible;

  /// 启用状态覆盖（null 表示不覆盖）。
  bool? enabled;

  /// 待处理的动画播放请求（UI 渲染层每帧后 drain）。
  List<UiAnimationRequest> animationRequests = [];

  /// 应用到 [UiNode.props] 的合并视图（不修改原 props）。
  Map<String, dynamic> applyTo(Map<String, dynamic> base) {
    return {...base, ...props};
  }

  /// 应用到 [UiNode.style] 的合并视图（不修改原 style）。
  Map<String, dynamic> applyToStyle(Map<String, dynamic> base) {
    return {...base, ...style};
  }

  /// 应用到 [UiNode.triggers] 的合并视图（不修改原 triggers）。
  Map<String, String> applyToTriggers(Map<String, String> base) {
    return {...base, ...triggerOverrides};
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

/// 动画播放请求（运行时由 ui_play_animation 等控制节点发起）。
class UiAnimationRequest {
  /// 目标组件 id。
  final String componentId;

  /// 动画类型：'entrance' / 'exit' / 'triggered'。
  final String kind;

  /// 触发事件名（仅 kind='triggered' 时有效，用于区分多个触发动画）。
  final String? event;

  const UiAnimationRequest({
    required this.componentId,
    required this.kind,
    this.event,
  });
}
