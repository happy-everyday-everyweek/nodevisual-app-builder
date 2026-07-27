import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart';

import '../../../../data/models/ui_tree.dart';
import 'animation_presets.dart';

/// 关键帧动画执行器（Phase 5.2）。
///
/// 根据 [Keyframe] 列表构建复合 [Animation]<[KeyframeProperties]>：
/// 控制器的归一化进度（0-1）映射到关键帧时间轴，在相邻关键帧间插值。
///
/// 关键帧时间轴约定：
/// - 关键帧按 [Keyframe.time]（0-1）排序；首帧应位于 0，末帧应位于 1。
/// - 进度 < 首帧时间时取首帧属性；进度 > 末帧时间时取末帧属性。
/// - 相邻关键帧间使用前一个关键帧的 [Keyframe.easing] 缓动。
class KeyframeAnimationExecutor {
  const KeyframeAnimationExecutor._();

  /// 根据关键帧列表构建复合动画。
  ///
  /// 返回的 [Animation]<[KeyframeProperties]> 监听 [controller] 的进度变化，
  /// 在每次值更新时计算当前关键帧之间的插值属性。
  ///
  /// 若 [keyframes] 为空，返回值恒为默认空属性（无任何变换）。
  static Animation<KeyframeProperties> buildKeyframeAnimation({
    required AnimationController controller,
    required List<Keyframe> keyframes,
  }) {
    if (keyframes.isEmpty) {
      return AlwaysStoppedAnimation<KeyframeProperties>(
        const KeyframeProperties(),
      );
    }
    final sorted = List<Keyframe>.from(keyframes)
      ..sort((a, b) => a.time.compareTo(b.time));
    return _KeyframeAnimation(controller, sorted);
  }

  /// 在指定时间点插值属性。
  ///
  /// [t] 为相邻关键帧间的归一化进度（0-1），函数内部会再应用 [easing]
  /// 曲线，使插值在不同段内可使用不同缓动。
  ///
  /// 任一端属性为 null 时按 0 处理（保证有数值可插值）。
  static KeyframeProperties interpolate(
    KeyframeProperties from,
    KeyframeProperties to,
    double t,
    EasingType easing,
  ) {
    final curve = PresetAnimationExecutor.getCurve(easing);
    final eased = curve.transform(t.clamp(0.0, 1.0));
    return KeyframeProperties(
      x: _lerpNullable(from.x, to.x, eased),
      y: _lerpNullable(from.y, to.y, eased),
      opacity: _lerpNullable(from.opacity, to.opacity, eased),
      scale: _lerpNullable(from.scale, to.scale, eased),
      rotation: _lerpNullable(from.rotation, to.rotation, eased),
    );
  }

  /// 在两个 nullable double 间线性插值；两端均为 null 时返回 null。
  static double? _lerpNullable(double? from, double? to, double t) {
    if (from == null && to == null) return null;
    final f = from ?? 0.0;
    final tt = to ?? 0.0;
    return f + (tt - f) * t;
  }

  /// 根据 [KeyframeProperties] 包装 [child]，应用平移/缩放/旋转/透明度变换。
  ///
  /// 未设置（null）的属性不参与变换。
  static Widget applyProperties({
    required Widget child,
    required KeyframeProperties props,
  }) {
    Widget result = child;
    if (props.scale != null) {
      result = Transform.scale(scale: props.scale!, child: result);
    }
    if (props.rotation != null) {
      result = Transform.rotate(angle: props.rotation!, child: result);
    }
    final dx = props.x ?? 0.0;
    final dy = props.y ?? 0.0;
    if (dx != 0 || dy != 0) {
      result = Transform.translate(offset: Offset(dx, dy), child: result);
    }
    if (props.opacity != null) {
      result = Opacity(opacity: props.opacity!.clamp(0.0, 1.0), child: result);
    }
    return result;
  }
}

/// 关键帧驱动的 [Animation]<[KeyframeProperties]> 实现。
///
/// 监听父 [AnimationController] 的进度变化，每次更新时计算当前进度对应
/// 的 [KeyframeProperties]（在相邻关键帧间插值），并通知监听者。
class _KeyframeAnimation extends Animation<KeyframeProperties>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  _KeyframeAnimation(this._parent, this._keyframes) {
    _parent.addListener(notifyListeners);
    _parent.addStatusListener(notifyStatusListeners);
  }

  final Animation<double> _parent;
  final List<Keyframe> _keyframes;

  @override
  AnimationStatus get status => _parent.status;

  @override
  KeyframeProperties get value {
    final t = _parent.value.clamp(0.0, 1.0);
    if (_keyframes.isEmpty) return const KeyframeProperties();
    if (_keyframes.length == 1) return _keyframes.first.properties;
    if (t <= _keyframes.first.time) return _keyframes.first.properties;
    if (t >= _keyframes.last.time) return _keyframes.last.properties;
    for (int i = 0; i < _keyframes.length - 1; i++) {
      final from = _keyframes[i];
      final to = _keyframes[i + 1];
      if (t >= from.time && t <= to.time) {
        final span = to.time - from.time;
        final segT = span <= 0 ? 0.0 : (t - from.time) / span;
        return KeyframeAnimationExecutor.interpolate(
          from.properties,
          to.properties,
          segT,
          from.easing,
        );
      }
    }
    return _keyframes.last.properties;
  }

  @override
  void dispose() {
    _parent.removeListener(notifyListeners);
    _parent.removeStatusListener(notifyStatusListeners);
    super.dispose();
  }
}
