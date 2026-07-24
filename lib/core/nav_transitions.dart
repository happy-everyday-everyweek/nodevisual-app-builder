import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 路由过渡动画工具。
///
/// 设计目标：**"哪去哪回"**——push 进入时的动画方向与 pop 退出时的方向
/// 完全相反（进入从右向左滑入，退出从左向右滑出），且使用相同的曲线族
/// 保证视觉对称。
///
/// 提供两种过渡：
/// - [slideTransition]：标准水平滑动 + 淡入，用于 push 主流场景。
/// - [fadeTransition]：纯淡入淡出，用于 dialog / sheet 等已自定义位置的
///   场景（避免叠加位移）。
class NavTransitions {
  NavTransitions._();

  /// 标准过渡时长。
  static const Duration duration = Duration(milliseconds: 300);

  /// 反向（pop）过渡时长，略短于正向，符合"消失更快"感知。
  static const Duration reverseDuration = Duration(milliseconds: 250);

  /// 正向进入曲线（ease-out：开始快、结束慢）。
  static const Curve forwardCurve = Curves.easeOutCubic;

  /// 反向退出曲线（ease-in：开始慢、结束快）——视觉上"原路返回"。
  static const Curve reverseCurve = Curves.easeInCubic;

  /// 标准"哪去哪回"水平滑动 page。
  ///
  /// 进入：自右向左滑入 + 淡入。
  /// 退出：自左向右滑出 + 淡出。
  /// secondary（当前页被覆盖时）：保持原位 + 轻微暗化（0→0.05）。
  static CustomTransitionPage<T> slideTransition<T>({
    required Widget child,
    required GoRouterState state,
    bool fullscreenDialog = false,
  }) {
    return CustomTransitionPage<T>(
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      fullscreenDialog: fullscreenDialog,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // 入场：从右侧滑入（offset 1→0）。
        // 退场：pop 时 animation 反向 1→0，offset 自然回到 1（右侧），
        // 即原路返回。
        final slideIn = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: forwardCurve));

        // 当前页被新页覆盖时：轻微缩小 + 暗化（覆盖感）。
        // 退场时新页 reverse，此动画也 reverse，原路恢复。
        final secondaryScale = Tween<double>(
          begin: 1.0,
          end: 0.96,
        ).chain(CurveTween(curve: forwardCurve));
        final secondaryFade = Tween<double>(
          begin: 1.0,
          end: 0.7,
        ).chain(CurveTween(curve: forwardCurve));

        return SlideTransition(
          position: animation.drive(slideIn),
          child: FadeTransition(
            opacity: animation.drive(
              Tween<double>(begin: 0.0, end: 1.0)
                  .chain(CurveTween(curve: forwardCurve)),
            ),
            child: FadeTransition(
              opacity: secondaryAnimation.drive(secondaryFade),
              child: ScaleTransition(
                scale: secondaryAnimation.drive(secondaryScale),
                alignment: Alignment.centerRight,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 纯淡入淡出 page（用于 dialog 类或底部 sheet 路由）。
  static CustomTransitionPage<T> fadeTransition<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<T>(
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation.drive(
            Tween<double>(begin: 0.0, end: 1.0)
                .chain(CurveTween(curve: forwardCurve)),
          ),
          child: child,
        );
      },
    );
  }

  /// 简易入场动画 widget：用于卡片 / 列表项等非路由场景的"出现"动画。
  /// 配合 [AnimatedSwitcher] / [KeyedSubtree] 使用。
  static Widget appear({
    required Widget child,
    required Animation<double> animation,
    Offset offset = const Offset(0, 0.08),
  }) {
    return FadeTransition(
      opacity: animation.drive(
        Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: forwardCurve)),
      ),
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: offset, end: Offset.zero)
              .chain(CurveTween(curve: forwardCurve)),
        ),
        child: child,
      ),
    );
  }
}
