import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

import '../../../../data/models/ui_tree.dart';

/// 预设动画执行器（Phase 5.1）。
///
/// 将 [AnimationPreset] 与 [EasingType] 转换为 Flutter 动画系统的具体
/// [Tween] / [Curve] / [AnimationController]，并提供统一的 Widget 变换入口。
///
/// 设计要点：
/// - [getTween] 返回预设对应的"主 Tween"（按 preset 类型返回不同泛型）。
/// - [applyTransform] 按预设类型把归一化进度值（0-1）变换为对应 Widget 包装，
///   供 [AnimatedBuilder] 直接使用。
/// - [buildEntranceAnimation] / [buildExitAnimation] 构造带时长与延迟的控制器，
///   入场与出场本质相同（forward / reverse 由调用方控制方向）。
class PresetAnimationExecutor {
  const PresetAnimationExecutor._();

  /// 获取预设动画的主 [Tween]。
  ///
  /// 各预设返回的 Tween 类型如下：
  /// - [AnimationPreset.fade]    → `Tween<double>`（opacity 0→1）
  /// - [AnimationPreset.slide]    → `Tween<Offset>`（按方向从远处滑入）
  /// - [AnimationPreset.scale]    → `Tween<double>`（scale 0→1）
  /// - [AnimationPreset.bounce]   → `Tween<double>`（进度 0→1，靠 bounce 曲线驱动）
  /// - [AnimationPreset.rotate]   → `Tween<double>`（rotation 0→2π）
  /// - [AnimationPreset.elastic]  → `Tween<double>`（进度 0→1，靠 elastic 曲线驱动）
  ///
  /// [params] 支持的字段：
  /// - `direction`：slide 方向，'left' / 'right' / 'top' / 'bottom'（默认 left）。
  /// - `distance`：slide 距离（px，默认 100）。
  static Tween<dynamic> getTween(
    AnimationPreset preset,
    Map<String, dynamic> params,
  ) {
    switch (preset) {
      case AnimationPreset.fade:
        return Tween<double>(begin: 0.0, end: 1.0);
      case AnimationPreset.slide:
        final direction = (params['direction'] as String?) ?? 'left';
        final distance =
            (params['distance'] as num?)?.toDouble() ?? 100.0;
        return Tween<Offset>(
          begin: _offsetForDirection(direction, distance),
          end: Offset.zero,
        );
      case AnimationPreset.scale:
        return Tween<double>(begin: 0.0, end: 1.0);
      case AnimationPreset.bounce:
        // bounce 效果由 [EasingType.bounce] / [Curves.bounceOut] 驱动，
        // 这里返回归一化进度，[applyTransform] 会基于该值缩放。
        return Tween<double>(begin: 0.0, end: 1.0);
      case AnimationPreset.rotate:
        return Tween<double>(begin: 0.0, end: 2 * math.pi);
      case AnimationPreset.elastic:
        // elastic 同理，靠 [Curves.elasticOut] 驱动。
        return Tween<double>(begin: 0.0, end: 1.0);
    }
  }

  /// 获取 [EasingType] 对应的 [Curve]。
  static Curve getCurve(EasingType easing) {
    switch (easing) {
      case EasingType.linear:
        return Curves.linear;
      case EasingType.easeIn:
        return Curves.easeIn;
      case EasingType.easeOut:
        return Curves.easeOut;
      case EasingType.easeInOut:
        return Curves.easeInOut;
      case EasingType.bounce:
        return Curves.bounceOut;
      case EasingType.elastic:
        return Curves.elasticOut;
    }
  }

  /// 按 slide 方向将 [distance] 转为起始 [Offset]。
  static Offset _offsetForDirection(String direction, double distance) {
    switch (direction) {
      case 'right':
        return Offset(distance, 0);
      case 'top':
        return Offset(0, -distance);
      case 'bottom':
        return Offset(0, distance);
      case 'left':
      default:
        return Offset(-distance, 0);
    }
  }

  /// 根据预设与归一化进度值（0-1）包装 [child]，返回变换后的 Widget。
  ///
  /// [value] 应为应用了缓动曲线后的值（建议传入 [CurvedAnimation].value）。
  /// 对于 slide 预设，[value] 表示已抵达的比例（1 = 完全到位，0 = 完全偏移）。
  ///
  /// 注意：bounce / elastic 曲线会短暂超出 [0,1] 范围（超调），
  /// 缩放变换允许保留此超调以体现弹性手感；opacity 始终 clamp 到 [0,1]。
  static Widget applyTransform({
    required Widget child,
    required AnimationPreset preset,
    required double value,
    required Map<String, dynamic> params,
  }) {
    final v = value.clamp(0.0, 1.0);
    switch (preset) {
      case AnimationPreset.fade:
        return Opacity(opacity: v, child: child);
      case AnimationPreset.slide:
        final direction = (params['direction'] as String?) ?? 'left';
        final distance =
            (params['distance'] as num?)?.toDouble() ?? 100.0;
        // progress=1 时偏移为 0；progress=0 时偏移最大。
        final offset = _offsetForDirection(direction, distance * (1.0 - v));
        return Transform.translate(offset: offset, child: child);
      case AnimationPreset.scale:
        return Transform.scale(scale: v, child: child);
      case AnimationPreset.bounce:
        // 弹跳：缩放允许超过 1（曲线超调），opacity clamp 到 [0,1]。
        return Opacity(
          opacity: v,
          child: Transform.scale(scale: value, child: child),
        );
      case AnimationPreset.rotate:
        return Transform.rotate(angle: value * 2 * math.pi, child: child);
      case AnimationPreset.elastic:
        // 弹性：缩放允许超过 1（曲线超调），opacity clamp 到 [0,1]。
        return Opacity(
          opacity: v,
          child: Transform.scale(scale: value, child: child),
        );
    }
  }

  /// 构建入场动画控制器。
  ///
  /// 入场动画从 0 → 1 forward 播放。[spec.duration] 单位 ms，
  /// 取值非正数时回退到 300ms。
  static AnimationController buildEntranceAnimation({
    required TickerProvider vsync,
    required AnimationSpec spec,
  }) {
    final durationMs = spec.duration > 0 ? spec.duration.toInt() : 300;
    return AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: durationMs),
    );
  }

  /// 构建出场动画控制器。
  ///
  /// 出场动画通常从 1 → 0 reverse 播放（调用方负责 [AnimationController.reverse]）。
  /// 控制器构造与入场一致，方向由调用方控制。
  static AnimationController buildExitAnimation({
    required TickerProvider vsync,
    required AnimationSpec spec,
  }) {
    final durationMs = spec.duration > 0 ? spec.duration.toInt() : 300;
    return AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: durationMs),
    );
  }

  /// 构建触发动画控制器（与入场/出场同构，独立提供以便日后扩展）。
  static AnimationController buildTriggeredAnimation({
    required TickerProvider vsync,
    required AnimationSpec spec,
  }) {
    final durationMs = spec.duration > 0 ? spec.duration.toInt() : 300;
    return AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: durationMs),
    );
  }

  /// 计算包含延迟在内的总播放时长（ms），用于估算完成时机。
  static int totalDurationMs(AnimationSpec spec) {
    final dur = spec.duration > 0 ? spec.duration.toInt() : 300;
    final delay = spec.delay > 0 ? spec.delay.toInt() : 0;
    return dur + delay;
  }
}
