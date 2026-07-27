import 'ui_tree.dart';

/// Page 类型标识。
///
/// 当 [UiNode.type] == [kPageType] 时，该节点是一个 Page 节点（特殊 UiNode），
/// 承载页面级 props（[PagePropsKeys]）与生命周期触发（[PageLifecycleEvent]）。
///
/// Page 节点的 [UiNode.pageId] 为空（节点本身即页面）；
/// 其 [UiNode.children] 为该页面的 UI 根节点树。
const String kPageType = 'page';

/// Page 节点 props 键名常量。
///
/// Page 特有属性存储在 [UiNode.props] 中，使用这些键名访问。
class PagePropsKeys {
  PagePropsKeys._();

  /// 页面名（在项目内可读，不要求唯一）。
  static const String name = 'name';

  /// 页面路由路径（用于编译产物的路由表，可空表示使用 id 作为路径）。
  static const String route = 'route';

  /// 是否为应用首页（启动时进入的页面），项目内最多一个为 true。
  static const String isHome = 'isHome';

  /// 页面背景（颜色或背景图描述）。
  static const String background = 'background';

  /// 是否启用顶部安全区域。
  static const String safeAreaTop = 'safeAreaTop';

  /// 是否启用底部安全区域。
  static const String safeAreaBottom = 'safeAreaBottom';

  /// 页面转场动画类型（none/fade/slide/scale 等）。
  static const String transition = 'transition';

  /// 页面转场动画时长（毫秒）。
  static const String transitionDuration = 'transitionDuration';
}

/// Page 生命周期事件名（存储在 [UiNode.triggers] 中，值为函数 id）。
///
/// 这些事件名与 [FunctionEntry.pageEvent] 使用的 [PageEventName] 保持一致，
/// 但在本模型中直接作为 [UiNode.triggers] 的 key，值指向触发的函数 id。
class PageLifecycleEvent {
  PageLifecycleEvent._();

  /// 页面加载时触发（进入页面）。
  static const String onLoad = 'onLoad';

  /// 页面销毁时触发（离开页面）。
  static const String onDispose = 'onDispose';

  /// 页面恢复时触发（从后台切到前台 / 从下级页面返回）。
  static const String onResume = 'onResume';

  /// 页面暂停时触发（切到后台 / 跳到下级页面）。
  static const String onPause = 'onPause';

  /// 全部 Page 生命周期事件。
  static const List<String> all = [onLoad, onDispose, onResume, onPause];
}

/// Page 节点便捷扩展。
///
/// 提供 Page 特有属性的类型安全访问器，避免在调用方手写
/// `node.props[PagePropsKeys.name] as String?` 这类易错的类型转换。
extension PageNodeExtension on UiNode {
  /// 是否为 Page 节点。
  bool get isPage => type == kPageType;

  /// 页面名（仅 Page 节点有效；非 Page 节点返回 null）。
  String? get pageName => isPage ? props[PagePropsKeys.name] as String? : null;

  /// 页面路由路径（仅 Page 节点有效）。
  String? get pageRoute => isPage ? props[PagePropsKeys.route] as String? : null;

  /// 是否为应用首页（仅 Page 节点有效；非 Page 节点返回 false）。
  bool get isHomePage => isPage && (props[PagePropsKeys.isHome] as bool?) == true;

  /// 页面背景（仅 Page 节点有效）。
  String? get pageBackground =>
      isPage ? props[PagePropsKeys.background] as String? : null;

  /// 是否启用顶部安全区域（仅 Page 节点有效；默认 true）。
  bool get pageSafeAreaTop =>
      isPage ? (props[PagePropsKeys.safeAreaTop] as bool?) ?? true : true;

  /// 是否启用底部安全区域（仅 Page 节点有效；默认 true）。
  bool get pageSafeAreaBottom =>
      isPage ? (props[PagePropsKeys.safeAreaBottom] as bool?) ?? true : true;

  /// 页面转场动画类型（仅 Page 节点有效；默认 none）。
  String get pageTransition =>
      isPage ? (props[PagePropsKeys.transition] as String?) ?? 'none' : 'none';

  /// 页面转场动画时长毫秒（仅 Page 节点有效；默认 300）。
  double get pageTransitionDuration => isPage
      ? (props[PagePropsKeys.transitionDuration] as num?)?.toDouble() ?? 300
      : 300;

  /// 该 Page 绑定的生命周期事件 → 函数 id 映射（仅 Page 节点有效）。
  ///
  /// 等同于 [UiNode.triggers]，仅对 Page 节点语义化为生命周期触发。
  Map<String, String> get pageLifecycleTriggers =>
      isPage ? triggers : const {};
}

/// 创建 Page 节点的工厂函数。
///
/// Page 节点是一种特殊的 [UiNode]：
/// - [type] 固定为 [kPageType]
/// - [pageId] 固定为 null（节点本身即页面）
/// - [layout] 固定为填充屏幕（width=100%, height=100%）
/// - 页面属性存入 [props]（[PagePropsKeys]）
/// - 生命周期触发存入 [triggers]（[PageLifecycleEvent]）
/// - [children] 为该页面的 UI 根节点树
///
/// [lifecycleTriggers] 为生命周期事件名 → 函数 id 映射，可只传入部分事件。
UiNode createPageNode({
  required String id,
  required String name,
  String? route,
  bool isHome = false,
  String? background,
  bool safeAreaTop = true,
  bool safeAreaBottom = true,
  Map<String, String> lifecycleTriggers = const {},
  List<UiNode> children = const [],
  Map<String, Binding> bindings = const {},
}) {
  return UiNode(
    id: id,
    type: kPageType,
    pageId: null,
    props: {
      PagePropsKeys.name: name,
      if (route != null) PagePropsKeys.route: route,
      if (isHome) PagePropsKeys.isHome: true,
      if (background != null) PagePropsKeys.background: background,
      PagePropsKeys.safeAreaTop: safeAreaTop,
      PagePropsKeys.safeAreaBottom: safeAreaBottom,
    },
    children: children,
    bindings: bindings,
    // Page 固定填充屏幕：宽高均为 100%。
    layout: const LayoutConfig(
      mode: LayoutMode.relative,
      width: SizeSpec(value: 100, unit: SizeUnit.percent),
      height: SizeSpec(value: 100, unit: SizeUnit.percent),
    ),
    triggers: lifecycleTriggers,
  );
}
