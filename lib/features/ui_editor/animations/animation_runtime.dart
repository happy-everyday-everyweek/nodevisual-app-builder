import 'package:flutter/widgets.dart';

import '../../../../data/models/ui_tree.dart';
import 'animation_presets.dart';
import 'keyframe_executor.dart';

/// 动画运行时执行器（Phase 5.3）。
///
/// 协调 [AnimationsConfig] 的播放流程，对外暴露三个语义化入口：
/// - [playEntrance]：播放入场动画（首次出现）。
/// - [playExit]：播放出场动画（移除前）。
/// - [playTriggered]：按事件名播放触发的动画。
///
/// 设计模式：每次播放构造一个独立的 [AnimationController]，包装 [child]
/// 为受动画驱动的 Widget，通过 [onAnimated] 回调推送给调用方。
/// 调用方应在 Future 完成后停止渲染返回的 Widget（典型场景为预览面板）。
///
/// 注意：本类不管理 [TickerProvider] 与 controller 的生命周期，
/// 调用方需保证 [vsync] 在播放期间处于活跃状态（如 [State] 已 mounted）。
class AnimationRuntime {
  const AnimationRuntime._();

  /// 播放入场动画。
  ///
  /// 流程：
  /// 1. 若 [config] 无 entrance 动画，直接以原 [child] 回调并返回。
  /// 2. 应用 [AnimationSpec.delay] 延迟。
  /// 3. 构造 [AnimationController] + 缓动后的归一化 Animation<double>，
  ///    包装 [child] 为受驱动的 Widget，通过 [onAnimated] 推出。
  /// 4. forward 播放至完成。
  /// 5. 释放 controller。
  ///
  /// 调用方在 Future 完成后必须停止使用回调推出的 Widget（其依赖的
  /// controller 已被 dispose）。
  static Future<void> playEntrance({
    required TickerProvider vsync,
    required AnimationsConfig? config,
    required Widget child,
    required ValueChanged<Widget> onAnimated,
  }) async {
    final spec = config?.entrance;
    if (spec == null) {
      onAnimated(child);
      return;
    }
    await _drive(
      vsync: vsync,
      spec: spec,
      child: child,
      onAnimated: onAnimated,
      reverse: false,
    );
  }

  /// 播放出场动画。
  ///
  /// 出场动画从 1 → 0 reverse 播放，使组件从当前状态过渡到目标状态。
  static Future<void> playExit({
    required TickerProvider vsync,
    required AnimationsConfig? config,
    required Widget child,
    required ValueChanged<Widget> onAnimated,
  }) async {
    final spec = config?.exit;
    if (spec == null) {
      onAnimated(child);
      return;
    }
    await _drive(
      vsync: vsync,
      spec: spec,
      child: child,
      onAnimated: onAnimated,
      reverse: true,
    );
  }

  /// 播放事件触发的动画。
  ///
  /// 在 [config.triggered] 中查找匹配 [eventName] 的第一项并播放。
  /// 未找到时立即返回，不调用 [onAnimated]。
  static Future<void> playTriggered({
    required TickerProvider vsync,
    required AnimationsConfig? config,
    required String eventName,
    required Widget child,
    required ValueChanged<Widget> onAnimated,
  }) async {
    final triggered = config?.triggered ?? const [];
    final match =
        triggered.where((t) => t.event == eventName).toList(growable: false);
    if (match.isEmpty) return;
    await _drive(
      vsync: vsync,
      spec: match.first.animation,
      child: child,
      onAnimated: onAnimated,
      reverse: false,
    );
  }

  /// 内部驱动器：构造 controller 与驱动 Widget，等待播放完成。
  static Future<void> _drive({
    required TickerProvider vsync,
    required AnimationSpec spec,
    required Widget child,
    required ValueChanged<Widget> onAnimated,
    required bool reverse,
  }) async {
    final controller = PresetAnimationExecutor.buildEntranceAnimation(
      vsync: vsync,
      spec: spec,
    );
    try {
      if (spec.delay > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: spec.delay.toInt()),
        );
      }
      final animated = _buildAnimatedWidget(
        controller: controller,
        spec: spec,
        child: child,
      );
      onAnimated(animated);
      if (reverse) {
        controller.value = 1.0;
        await controller.reverse().orCancel;
      } else {
        await controller.forward().orCancel;
      }
    } on TickerCanceled {
      // 调用方在动画进行中 dispose（如 Widget 卸载），忽略即可。
    } finally {
      controller.dispose();
    }
  }

  /// 按 [spec] 类型构造受动画驱动的 Widget。
  static Widget _buildAnimatedWidget({
    required AnimationController controller,
    required AnimationSpec spec,
    required Widget child,
  }) {
    // 关键帧动画优先。
    if (spec.keyframes.isNotEmpty) {
      final kfAnim = KeyframeAnimationExecutor.buildKeyframeAnimation(
        controller: controller,
        keyframes: spec.keyframes,
      );
      return AnimatedBuilder(
        animation: kfAnim,
        builder: (context, _) =>
            KeyframeAnimationExecutor.applyProperties(
              child: child,
              props: kfAnim.value,
            ),
      );
    }
    final preset = spec.preset;
    if (preset == null) {
      return child;
    }
    final curve = PresetAnimationExecutor.getCurve(spec.easing);
    final curved = CurvedAnimation(parent: controller, curve: curve);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) => PresetAnimationExecutor.applyTransform(
        child: child,
        preset: preset,
        value: curved.value,
        params: spec.params,
      ),
    );
  }

  /// 估算播放总时长（含延迟），用于无 Ticker 场景的进度估算。
  static Duration estimateDuration(AnimationSpec spec) {
    final ms = PresetAnimationExecutor.totalDurationMs(spec);
    return Duration(milliseconds: ms);
  }
}
