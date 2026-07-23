import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'presentation/screens/home_screen.dart';

/// 应用根 Widget。
///
/// 使用 [MaterialApp.router] + [GoRouter] 进行声明式路由管理。
/// 通过 [ProviderScope] 包裹（由 main.dart 注入）实现 Riverpod 依赖注入。
class NodeVisualApp extends ConsumerWidget {
  const NodeVisualApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

/// 全局路由配置。
///
/// Task 1 阶段仅注册主页路由，后续 Task 将按需追加
/// 编辑器、设置、节点详情等子路由。
final GoRouter _router = GoRouter(
  initialLocation: AppConstants.routeHome,
  routes: <RouteBase>[
    GoRoute(
      path: AppConstants.routeHome,
      name: 'home',
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
    ),
  ],
);
