import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/ui_tree.dart';
import 'animation_presets.dart';
import 'keyframe_executor.dart';

/// 预设动画编辑器（Phase 5.5）。
///
/// 提供以下编辑能力：
/// - 预设选择下拉（fade/slide/scale/bounce/rotate/elastic）。
/// - 时长滑块（0-3000ms）。
/// - 延迟滑块（0-1000ms）。
/// - 缓动曲线下拉（linear/easeIn/easeOut/easeInOut/bounce/elastic）。
/// - 预设参数编辑（slide 的方向 + 距离）。
/// - 预览播放按钮（点击重新播放入场动画预览）。
///
/// 编辑结果通过 [onChanged] 推出新的 [AnimationSpec]；
/// [onClear] 用于清空当前规范。
class PresetAnimationEditor extends ConsumerWidget {
  const PresetAnimationEditor({
    super.key,
    required this.spec,
    required this.onChanged,
    this.onClear,
    this.label,
  });

  /// 当前编辑的动画规范；为 null 表示未配置。
  final AnimationSpec? spec;

  /// 规范变更回调。
  final ValueChanged<AnimationSpec> onChanged;

  /// 清除回调（可选）。
  final VoidCallback? onClear;

  /// 区段标题（如"入场动画"）。
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = spec ?? const AnimationSpec(preset: AnimationPreset.fade);
    final preset = current.preset ?? AnimationPreset.fade;
    final easing = current.easing;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(
              children: [
                Text(
                  label!,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (spec != null && onClear != null)
                  InkWell(
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close,
                          size: 14, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          // 预设选择
          DropdownButtonFormField<AnimationPreset>(
            value: preset,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: '预设',
            ),
            items: const [
              DropdownMenuItem(value: AnimationPreset.fade, child: Text('淡入')),
              DropdownMenuItem(value: AnimationPreset.slide, child: Text('滑动')),
              DropdownMenuItem(value: AnimationPreset.scale, child: Text('缩放')),
              DropdownMenuItem(value: AnimationPreset.bounce, child: Text('弹跳')),
              DropdownMenuItem(value: AnimationPreset.rotate, child: Text('旋转')),
              DropdownMenuItem(value: AnimationPreset.elastic, child: Text('弹性')),
            ],
            onChanged: (v) {
              if (v != null) _emit(current, preset: v);
            },
          ),
          const SizedBox(height: 8),
          // 时长滑块
          Text('时长：${current.duration.round()} ms',
              style: theme.textTheme.bodySmall),
          Slider(
            min: 0,
            max: 3000,
            divisions: 60,
            value: current.duration.clamp(0.0, 3000.0),
            label: '${current.duration.round()} ms',
            onChanged: (v) => _emit(current, duration: v),
          ),
          // 延迟滑块
          Text('延迟：${current.delay.round()} ms',
              style: theme.textTheme.bodySmall),
          Slider(
            min: 0,
            max: 1000,
            divisions: 20,
            value: current.delay.clamp(0.0, 1000.0),
            label: '${current.delay.round()} ms',
            onChanged: (v) => _emit(current, delay: v),
          ),
          const SizedBox(height: 4),
          // 缓动曲线
          DropdownButtonFormField<EasingType>(
            value: easing,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: '缓动',
            ),
            items: const [
              DropdownMenuItem(value: EasingType.linear, child: Text('线性')),
              DropdownMenuItem(value: EasingType.easeIn, child: Text('渐入')),
              DropdownMenuItem(value: EasingType.easeOut, child: Text('渐出')),
              DropdownMenuItem(
                  value: EasingType.easeInOut, child: Text('渐入渐出')),
              DropdownMenuItem(value: EasingType.bounce, child: Text('弹跳')),
              DropdownMenuItem(value: EasingType.elastic, child: Text('弹性')),
            ],
            onChanged: (v) {
              if (v != null) _emit(current, easing: v);
            },
          ),
          if (preset == AnimationPreset.slide) ...[
            const SizedBox(height: 8),
            _SlideParamsEditor(
              params: Map<String, dynamic>.from(current.params),
              onChanged: (p) => _emit(current, params: p),
            ),
          ],
          const SizedBox(height: 8),
          // 预览
          _PreviewButton(spec: current),
        ],
      ),
    );
  }

  void _emit(
    AnimationSpec base, {
    Object? preset = _unset,
    double? duration,
    double? delay,
    EasingType? easing,
    Map<String, dynamic>? params,
  }) {
    // AnimationSpec.copyWith 对 preset 使用 sentinel 区分"未提供"与"显式 null"，
    // 其余字段（duration/delay/easing/params）使用 ?? this.x，null 即表示保留。
    // 因此 duration/delay/easing/params 可直接透传；preset 仅在显式提供时透传，
    // 否则保留 base.preset，避免调整时长 / 延迟 / 缓动时误清空预设。
    onChanged(base.copyWith(
      preset: identical(preset, _unset) ? base.preset : preset,
      duration: duration,
      delay: delay,
      easing: easing,
      params: params,
    ));
  }
}

/// 用于区分"参数未提供"与"参数显式为 null"的哨兵对象。
const Object _unset = Object();

/// slide 预设参数编辑器（方向 + 距离）。
class _SlideParamsEditor extends StatelessWidget {
  const _SlideParamsEditor({
    required this.params,
    required this.onChanged,
  });

  final Map<String, dynamic> params;
  final ValueChanged<Map<String, dynamic>> onChanged;

  static const List<String> _directions = ['left', 'right', 'top', 'bottom'];

  @override
  Widget build(BuildContext context) {
    final direction = (params['direction'] as String?) ?? 'left';
    final distance = (params['distance'] as num?)?.toDouble() ?? 100.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _directions.contains(direction) ? direction : 'left',
          isDense: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            labelText: '方向',
          ),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('从左')),
            DropdownMenuItem(value: 'right', child: Text('从右')),
            DropdownMenuItem(value: 'top', child: Text('从上')),
            DropdownMenuItem(value: 'bottom', child: Text('从下')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged({...params, 'direction': v});
          },
        ),
        const SizedBox(height: 4),
        Text('距离：${distance.round()} px',
            style: Theme.of(context).textTheme.bodySmall),
        Slider(
          min: 20,
          max: 400,
          divisions: 38,
          value: distance.clamp(20.0, 400.0),
          label: '${distance.round()} px',
          onChanged: (v) => onChanged({...params, 'distance': v}),
        ),
      ],
    );
  }
}

/// 预览播放按钮 + 预览区域。
///
/// 每次点击重建 [_PreviewHost]（key 变化），让其 initState 自动播放
/// 当前 [spec] 的入场动画。
class _PreviewButton extends StatefulWidget {
  const _PreviewButton({required this.spec});

  final AnimationSpec spec;

  @override
  State<_PreviewButton> createState() => _PreviewButtonState();
}

class _PreviewButtonState extends State<_PreviewButton> {
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _tick++),
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('预览'),
        ),
        const SizedBox(height: 6),
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: cs.outlineVariant, width: 0.5),
          ),
          alignment: Alignment.center,
          child: _PreviewHost(
            key: ValueKey('preview-${_tick}-${widget.spec.hashCode}'),
            spec: widget.spec,
          ),
        ),
      ],
    );
  }
}

/// 预览容器：构造自己的 [AnimationController]，在 [initState] 自动播放。
class _PreviewHost extends StatefulWidget {
  const _PreviewHost({super.key, required this.spec});

  final AnimationSpec spec;

  @override
  State<_PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<_PreviewHost>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final dur =
        widget.spec.duration > 0 ? widget.spec.duration.toInt() : 300;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: dur),
    );
    Future<void>.microtask(() async {
      if (widget.spec.delay > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: widget.spec.delay.toInt()),
        );
      }
      if (mounted) await _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (spec.keyframes.isNotEmpty) {
          return _buildKeyframePreview(spec, _controller.value);
        }
        final preset = spec.preset;
        if (preset == null) return child!;
        final curve = PresetAnimationExecutor.getCurve(spec.easing);
        final v = curve.transform(_controller.value);
        return PresetAnimationExecutor.applyTransform(
          child: child!,
          preset: preset,
          value: v,
          params: spec.params,
        );
      },
      child: _sampleChild(context),
    );
  }

  Widget _buildKeyframePreview(AnimationSpec spec, double t) {
    final sorted = List<Keyframe>.from(spec.keyframes)
      ..sort((a, b) => a.time.compareTo(b.time));
    KeyframeProperties props = const KeyframeProperties();
    if (sorted.isNotEmpty) {
      if (sorted.length == 1) {
        props = sorted.first.properties;
      } else {
        final tt = t.clamp(0.0, 1.0);
        if (tt <= sorted.first.time) {
          props = sorted.first.properties;
        } else if (tt >= sorted.last.time) {
          props = sorted.last.properties;
        } else {
          for (int i = 0; i < sorted.length - 1; i++) {
            final from = sorted[i];
            final to = sorted[i + 1];
            if (tt >= from.time && tt <= to.time) {
              final span = to.time - from.time;
              final segT = span <= 0 ? 0.0 : (tt - from.time) / span;
              props = KeyframeAnimationExecutor.interpolate(
                from.properties,
                to.properties,
                segT,
                from.easing,
              );
              break;
            }
          }
        }
      }
    }
    return KeyframeAnimationExecutor.applyProperties(
      child: _sampleChild(context),
      props: props,
    );
  }

  /// 预览使用的样本 Widget（一个有色彩的圆角方框 + 图标）。
  Widget _sampleChild(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.star, color: cs.onPrimary, size: 24),
    );
  }
}
