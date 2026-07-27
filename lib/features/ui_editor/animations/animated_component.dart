import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/ui_tree.dart';
import 'animation_presets.dart';
import 'keyframe_executor.dart';

/// 动画组件包装器（Phase 5.4）。
///
/// 包裹任意 [child] Widget，根据 [node.animations] 配置自动播放：
/// - **入场动画**：组件首次构建时（[initState]）自动播放。
/// - **出场动画**：通过 [playExit] 主动触发（典型场景：父组件准备移除本节点前）。
/// - **触发动画**：通过 [playTriggered] 按事件名触发（如 onTap / onLongPress）。
///
/// 单一 [AnimationController] 复用：同一时刻只播放一个动画，新动画会重置控制器。
/// 这样可避免多个 ticker 并发开销，且符合大多数 UI 节点动画的串行语义。
///
/// [onAnimationComplete] 在每次动画播放完成时回调，调用方可据此执行后续动作
/// （如真正移除节点）。
class AnimatedComponent extends ConsumerStatefulWidget {
  const AnimatedComponent({
    super.key,
    required this.node,
    required this.child,
    this.onAnimationComplete,
    this.previewMode = false,
  });

  /// 被包装的 UI 节点（读取 [UiNode.animations]）。
  final UiNode node;

  /// 子组件。
  final Widget child;

  /// 动画完成回调。
  final ValueChanged<String>? onAnimationComplete;

  /// 预览模式：仅当显式调用播放方法时才动画，不在 initState 自动播放入场。
  final bool previewMode;

  @override
  ConsumerState<AnimatedComponent> createState() => _AnimatedComponentState();
}

class _AnimatedComponentState extends ConsumerState<AnimatedComponent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// 当前正在播放的动画规范（决定 build 中如何变换 child）。
  AnimationSpec? _currentSpec;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    if (!widget.previewMode) {
      _playEntrance();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换节点时若入场动画配置变化，按需重播。
    if (oldWidget.node.animations?.entrance != widget.node.animations?.entrance &&
        !widget.previewMode &&
        _currentSpec == null) {
      _playEntrance();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 播放入场动画。
  Future<void> _playEntrance() {
    final spec = widget.node.animations?.entrance;
    if (spec == null) return Future.value();
    return _run(spec, reverse: false, name: 'entrance');
  }

  /// 主动播放入场动画（外部触发）。
  Future<void> playEntrance() => _playEntrance();

  /// 播放出场动画。完成后回调 [widget.onAnimationComplete]('exit')。
  Future<void> playExit() {
    final spec = widget.node.animations?.exit;
    if (spec == null) {
      widget.onAnimationComplete?.call('exit');
      return Future.value();
    }
    return _run(spec, reverse: true, name: 'exit');
  }

  /// 播放事件触发的动画。
  ///
  /// 在 [node.animations.triggered] 中查找匹配 [eventName] 的项并播放。
  /// 未找到时立即回调 complete。
  Future<void> playTriggered(String eventName) {
    final triggered = widget.node.animations?.triggered ?? const [];
    final match = triggered.where((t) => t.event == eventName).toList(growable: false);
    if (match.isEmpty) {
      widget.onAnimationComplete?.call(eventName);
      return Future.value();
    }
    return _run(match.first.animation, reverse: false, name: eventName);
  }

  /// 通用播放驱动：设置 controller 时长、应用延迟、forward/reverse 播放。
  Future<void> _run({
    required AnimationSpec spec,
    required bool reverse,
    required String name,
  }) async {
    final durationMs = spec.duration > 0 ? spec.duration.toInt() : 300;
    _controller.duration = Duration(milliseconds: durationMs);
    _currentSpec = spec;
    if (mounted) setState(() {});
    // 延迟启动。
    if (spec.delay > 0) {
      await Future<void>.delayed(Duration(milliseconds: spec.delay.toInt()));
      if (!mounted) return;
    }
    // 入场：forward 0→1；出场：reverse 1→0。
    final TickerFuture fut = reverse
        ? _controller.reverse(from: 1.0)
        : _controller.forward(from: 0.0);
    try {
      await fut.orCancel;
    } on TickerCanceled {
      // 调用方在动画进行中 dispose（如 Widget 卸载），忽略即可。
      return;
    }
    if (!mounted) return;
    // 保持终态：入场后停留末帧；出场后停留首帧（不可见）。
    widget.onAnimationComplete?.call(name);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _currentSpec;
    if (spec == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (spec.keyframes.isNotEmpty) {
          // 关键帧动画直接读 controller.value（关键帧内部已处理段内 easing）。
          final props = _evalKeyframeAt(spec, _controller.value);
          return KeyframeAnimationExecutor.applyProperties(
            child: child!,
            props: props,
          );
        }
        final preset = spec.preset;
        if (preset == null) return child!;
        final curve = PresetAnimationExecutor.getCurve(spec.easing);
        // 入场时 controller 0→1；出场时 controller 1→0（reverse）。
        // 两种情形下直接对 controller.value 应用曲线，结果与目标方向一致。
        final v = curve.transform(_controller.value);
        return PresetAnimationExecutor.applyTransform(
          child: child!,
          preset: preset,
          value: v,
          params: spec.params,
        );
      },
      child: widget.child,
    );
  }

  /// 在控制器当前进度上计算关键帧属性（与 [_KeyframeAnimation] 等价但无监听）。
  KeyframeProperties _evalKeyframeAt(AnimationSpec spec, double t) {
    final sorted = List<Keyframe>.from(spec.keyframes)
      ..sort((a, b) => a.time.compareTo(b.time));
    if (sorted.isEmpty) return const KeyframeProperties();
    if (sorted.length == 1) return sorted.first.properties;
    final tt = t.clamp(0.0, 1.0);
    if (tt <= sorted.first.time) return sorted.first.properties;
    if (tt >= sorted.last.time) return sorted.last.properties;
    for (int i = 0; i < sorted.length - 1; i++) {
      final from = sorted[i];
      final to = sorted[i + 1];
      if (tt >= from.time && tt <= to.time) {
        final span = to.time - from.time;
        final segT = span <= 0 ? 0.0 : (tt - from.time) / span;
        return KeyframeAnimationExecutor.interpolate(
          from.properties,
          to.properties,
          segT,
          from.easing,
        );
      }
    }
    return sorted.last.properties;
  }
}
