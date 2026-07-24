import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/nav_transitions.dart';
import 'core/theme.dart';
import 'features/node_graph/function_editor_screen.dart';
import 'features/node_graph/node_editor_screen.dart';
import 'presentation/screens/build/build_screen.dart';
import 'presentation/screens/editor/editor_shell_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/marketplace/marketplace_screen.dart';

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
/// 所有页面采用 [NavTransitions.slideTransition] "哪去哪回"过渡：
/// push 进入自右向左滑入，pop 退出原路自左向右滑出，曲线对称反向。
/// 全屏对话框（如 build）使用 [NavTransitions.fadeTransition] 避免位移叠加。
final GoRouter _router = GoRouter(
  initialLocation: AppConstants.routeHome,
  routes: <RouteBase>[
    GoRoute(
      path: AppConstants.routeHome,
      name: 'home',
      pageBuilder: (context, state) => NavTransitions.slideTransition(
        child: const HomeScreen(),
        state: state,
      ),
    ),
    GoRoute(
      path: AppConstants.routeMarketplace,
      name: 'marketplace',
      pageBuilder: (context, state) => NavTransitions.slideTransition(
        child: const MarketplaceScreen(),
        state: state,
      ),
    ),
    GoRoute(
      path: AppConstants.routeProject,
      name: 'project',
      pageBuilder: (BuildContext context, GoRouterState state) {
        final projectId = state.pathParameters['id']!;
        return NavTransitions.slideTransition(
          child: EditorShellScreen(projectId: projectId),
          state: state,
        );
      },
      routes: <RouteBase>[
        GoRoute(
          path: 'function/:fid',
          name: 'functionEditor',
          pageBuilder: (BuildContext context, GoRouterState state) {
            final projectId = state.pathParameters['id']!;
            final functionId = state.pathParameters['fid']!;
            return NavTransitions.slideTransition(
              child: FunctionEditorScreen(
                projectId: projectId,
                functionId: functionId,
              ),
              state: state,
            );
          },
          routes: <RouteBase>[
            GoRoute(
              path: 'node/:nid',
              name: 'nodeEditor',
              pageBuilder: (BuildContext context, GoRouterState state) {
                final projectId = state.pathParameters['id']!;
                final functionId = state.pathParameters['fid']!;
                final nodeId = state.pathParameters['nid']!;
                return NavTransitions.slideTransition(
                  child: NodeEditorScreen(
                    projectId: projectId,
                    functionId: functionId,
                    nodeId: nodeId,
                  ),
                  state: state,
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: 'build',
          name: 'build',
          pageBuilder: (BuildContext context, GoRouterState state) {
            final projectId = state.pathParameters['id']!;
            return NavTransitions.fadeTransition(
              child: BuildScreen(projectId: projectId),
              state: state,
            );
          },
        ),
      ],
    ),
  ],
);
