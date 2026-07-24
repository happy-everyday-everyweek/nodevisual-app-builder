import 'package:collection/collection.dart';

const DeepCollectionEquality _pageDeepEq = DeepCollectionEquality();

/// 页面模型（UI 段的命名根，承载页面级触发与页面作用域函数变量）。
///
/// 一个 [Page] = 命名 UI 根（[rootUiNodeId] 指向 [Project.ui] 中的某根节点）
/// + 页面级事件绑定声明（仅作为元数据；实际触发函数的声明在
///   [FunctionDef.entry] = `pageEvent` 中，按 [id] 关联）。
///
/// 运行时：进入页面时按声明序执行该 Page 下所有 `entry.kind == pageEvent`
/// 的 onLoad 函数；离开页面时执行 onDispose 函数。函数 outputs 缓存到
/// 页面作用域，供该页面内 UI 组件的 `#` 引用读取。
class Page {
  /// 唯一标识。
  final String id;

  /// 页面名（在项目内可读，不要求唯一）。
  final String name;

  /// 页面对应的 UI 根节点 id（指向 [Project.ui] 列表中的某 [UiNode.id]）。
  ///
  /// 一个 UI 根节点只能归属到一个 Page。若 [rootUiNodeId] 为空，
  /// 表示该 Page 尚未关联 UI 根（用于"占位"页面）。
  final String? rootUiNodeId;

  /// 页面路由路径（用于编译产物的路由表，可空表示使用 id 作为路径）。
  final String? route;

  /// 是否为应用首页（启动时进入的页面），项目内最多一个为 true。
  final bool isHome;

  const Page({
    required this.id,
    required this.name,
    this.rootUiNodeId,
    this.route,
    this.isHome = false,
  });

  Page copyWith({
    String? id,
    String? name,
    Object? rootUiNodeId = _sentinel,
    Object? route = _sentinel,
    bool? isHome,
  }) =>
      Page(
        id: id ?? this.id,
        name: name ?? this.name,
        rootUiNodeId: identical(rootUiNodeId, _sentinel)
            ? this.rootUiNodeId
            : rootUiNodeId as String?,
        route: identical(route, _sentinel)
            ? this.route
            : route as String?,
        isHome: isHome ?? this.isHome,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Page &&
          id == other.id &&
          name == other.name &&
          rootUiNodeId == other.rootUiNodeId &&
          route == other.route &&
          isHome == other.isHome;

  @override
  int get hashCode => Object.hash(id, name, rootUiNodeId, route, isHome);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (rootUiNodeId != null) 'rootUiNodeId': rootUiNodeId,
        if (route != null) 'route': route,
        if (isHome) 'isHome': true,
      };

  factory Page.fromJson(Map<String, dynamic> json) => Page(
        id: json['id'] as String,
        name: json['name'] as String,
        rootUiNodeId: json['rootUiNodeId'] as String?,
        route: json['route'] as String?,
        isHome: (json['isHome'] as bool?) ?? false,
      );

  @override
  String toString() => 'Page($name#$id)';
}

const Object _sentinel = Object();
