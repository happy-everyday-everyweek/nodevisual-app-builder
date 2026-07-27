import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/ui_tree.dart';
import 'animation_presets.dart';
import 'keyframe_executor.dart';

/// 关键帧动画编辑器（Phase 5.6）。
///
/// 提供以下能力：
/// - 可视化时间轴（横向 0-1）。
/// - 关键帧标记，可水平拖动调整时间。
/// - 添加 / 删除关键帧按钮。
/// - 选中关键帧的属性编辑面板（x/y/opacity/scale/rotation）。
/// - 关键帧间缓动曲线选择（修改当前关键帧的 easing，影响至下一帧的过渡）。
/// - 预览播放按钮。
class KeyframeAnimationEditor extends ConsumerStatefulWidget {
  const KeyframeAnimationEditor({
    super.key,
    required this.spec,
    required this.onChanged,
    this.onClear,
    this.label,
  });

  final AnimationSpec? spec;
  final ValueChanged<AnimationSpec> onChanged;
  final VoidCallback? onClear;
  final String? label;

  @override
  ConsumerState<KeyframeAnimationEditor> createState() =>
      _KeyframeAnimationEditorState();
}

class _KeyframeAnimationEditorState
    extends ConsumerState<KeyframeAnimationEditor> {
  /// 当前选中的关键帧索引（-1 表示未选中）。
  int _selected = -1;

  AnimationSpec get _current =>
      widget.spec ?? const AnimationSpec(keyframes: _defaultKeyframes);

  static const List<Keyframe> _defaultKeyframes = [
    Keyframe(
      time: 0.0,
      properties: KeyframeProperties(opacity: 0.0, scale: 0.5),
      easing: EasingType.easeOut,
    ),
    Keyframe(
      time: 1.0,
      properties: const KeyframeProperties(opacity: 1.0, scale: 1.0),
    ),
  ];

  void _emit(AnimationSpec next) => widget.onChanged(next);

  void _addKeyframe() {
    final list = List<Keyframe>.from(_current.keyframes);
    // 新关键帧时间：取末帧时间 + 0.1（不超过 1.0），否则 0.5。
    final newTime = list.isEmpty
        ? 0.5
        : (list.last.time + 0.1).clamp(0.0, 1.0);
    final newKf = Keyframe(
      time: newTime,
      properties: const KeyframeProperties(opacity: 1.0, scale: 1.0),
    );
    list.add(newKf);
    list.sort((a, b) => a.time.compareTo(b.time));
    _emit(_current.copyWith(keyframes: list));
    setState(() {
      // Keyframe 重写了 ==，使用 identical 精确定位新加的关键帧。
      _selected = list.indexWhere((k) => identical(k, newKf));
    });
  }

  void _deleteKeyframe(int index) {
    final list = List<Keyframe>.from(_current.keyframes);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    _emit(_current.copyWith(keyframes: list));
    setState(() {
      _selected = -1;
    });
  }

  void _updateKeyframe(int index, Keyframe next) {
    final list = List<Keyframe>.from(_current.keyframes);
    if (index < 0 || index >= list.length) return;
    list[index] = next;
    // 时间变更后需重新排序并保持选中。
    list.sort((a, b) => a.time.compareTo(b.time));
    _emit(_current.copyWith(keyframes: list));
    setState(() {
      // Keyframe 重写了 ==，使用 identical 精确定位被编辑的关键帧。
      _selected = list.indexWhere((k) => identical(k, next));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final keyframes = _current.keyframes;
    final selected =
        (_selected >= 0 && _selected < keyframes.length) ? _selected : -1;
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
          if (widget.label != null) ...[
            Row(
              children: [
                Text(
                  widget.label!,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (widget.spec != null && widget.onClear != null)
                  InkWell(
                    onTap: widget.onClear,
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
          // 时长 / 延迟 滑块（关键帧动画也需要总时长与延迟）。
          _buildTimingRow(theme),
          const SizedBox(height: 8),
          // 时间轴
          Text('时间轴', style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          _KeyframeTimeline(
            keyframes: keyframes,
            selectedIndex: selected,
            onSelect: (i) => setState(() => _selected = i),
            onDrag: (i, newTime) {
              final list = List<Keyframe>.from(keyframes);
              final clamped = newTime.clamp(0.0, 1.0);
              final updated = list[i].copyWith(time: clamped);
              list[i] = updated;
              list.sort((a, b) => a.time.compareTo(b.time));
              _emit(_current.copyWith(keyframes: list));
              setState(() {
                // 使用 identical 精确定位被拖动的关键帧。
                _selected = list.indexWhere((k) => identical(k, updated));
              });
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _addKeyframe,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加关键帧'),
              ),
              const SizedBox(width: 8),
              if (selected >= 0)
                OutlinedButton.icon(
                  onPressed: () => _deleteKeyframe(selected),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除选中'),
                ),
              const Spacer(),
              // 预览按钮
              _PreviewButton(spec: _current),
            ],
          ),
          const SizedBox(height: 8),
          if (selected >= 0 && selected < keyframes.length)
            _KeyframePropertyEditor(
              keyframe: keyframes[selected],
              index: selected,
              onChanged: (kf) => _updateKeyframe(selected, kf),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '点击时间轴上的关键帧以编辑属性。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimingRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('时长：${_current.duration.round()} ms',
                  style: theme.textTheme.bodySmall),
              Slider(
                min: 0,
                max: 3000,
                divisions: 60,
                value: _current.duration.clamp(0.0, 3000.0),
                label: '${_current.duration.round()} ms',
                onChanged: (v) => _emit(_current.copyWith(duration: v)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('延迟：${_current.delay.round()} ms',
                  style: theme.textTheme.bodySmall),
              Slider(
                min: 0,
                max: 1000,
                divisions: 20,
                value: _current.delay.clamp(0.0, 1000.0),
                label: '${_current.delay.round()} ms',
                onChanged: (v) => _emit(_current.copyWith(delay: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 关键帧时间轴：横向 0-1 的可视化条 + 关键帧标记。
class _KeyframeTimeline extends StatelessWidget {
  const _KeyframeTimeline({
    required this.keyframes,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDrag,
  });

  final List<Keyframe> keyframes;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final void Function(int index, double newTime) onDrag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 40,
          child: Stack(
            children: [
              // 时间轴主线
              Positioned(
                left: 0,
                right: 0,
                top: 20,
                child: Container(
                  height: 2,
                  color: cs.outline,
                ),
              ),
              // 刻度
              for (int i = 0; i <= 10; i++)
                Positioned(
                  left: width * i / 10 - 1,
                  top: 14,
                  child: Container(
                    width: 2,
                    height: 14,
                    color: cs.outlineVariant,
                  ),
                ),
              // 关键帧标记
              for (int i = 0; i < keyframes.length; i++)
                Positioned(
                  left: width * keyframes[i].time - 8,
                  top: 12,
                  child: GestureDetector(
                    onTap: () => onSelect(i),
                    onHorizontalDragUpdate: (details) {
                      final delta = details.delta.dx / width;
                      final newTime = keyframes[i].time + delta;
                      onDrag(i, newTime);
                    },
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: i == selectedIndex
                            ? cs.primary
                            : cs.secondaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == selectedIndex
                              ? cs.onPrimary
                              : cs.outline,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个关键帧属性编辑面板。
class _KeyframePropertyEditor extends StatelessWidget {
  const _KeyframePropertyEditor({
    required this.keyframe,
    required this.index,
    required this.onChanged,
  });

  final Keyframe keyframe;
  final int index;
  final ValueChanged<Keyframe> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('关键帧 #${index + 1} · t=${keyframe.time.toStringAsFixed(2)}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          // 时间
          Text('时间：${keyframe.time.toStringAsFixed(2)}',
              style: theme.textTheme.bodySmall),
          Slider(
            min: 0,
            max: 1,
            divisions: 100,
            value: keyframe.time.clamp(0.0, 1.0),
            label: keyframe.time.toStringAsFixed(2),
            onChanged: (v) => onChanged(keyframe.copyWith(time: v)),
          ),
          const SizedBox(height: 4),
          // 缓动曲线（影响至下一关键帧的过渡）
          DropdownButtonFormField<EasingType>(
            value: keyframe.easing,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: '缓动（至下一帧）',
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
              if (v != null) onChanged(keyframe.copyWith(easing: v));
            },
          ),
          const SizedBox(height: 8),
          // 5 个属性编辑（每个 = 数值输入 + 启用开关）
          _PropField(
            label: 'X 偏移',
            value: keyframe.properties.x,
            onChanged: (v) => _updateProp(x: v),
          ),
          _PropField(
            label: 'Y 偏移',
            value: keyframe.properties.y,
            onChanged: (v) => _updateProp(y: v),
          ),
          _PropField(
            label: '透明度',
            value: keyframe.properties.opacity,
            hint: '0.0 - 1.0',
            onChanged: (v) => _updateProp(opacity: v),
          ),
          _PropField(
            label: '缩放',
            value: keyframe.properties.scale,
            hint: '1.0 = 原始',
            onChanged: (v) => _updateProp(scale: v),
          ),
          _PropField(
            label: '旋转',
            value: keyframe.properties.rotation,
            hint: '弧度',
            onChanged: (v) => _updateProp(rotation: v),
          ),
        ],
      ),
    );
  }

  void _updateProp({
    Object? x = _unset,
    Object? y = _unset,
    Object? opacity = _unset,
    Object? scale = _unset,
    Object? rotation = _unset,
  }) {
    var props = keyframe.properties;
    // 仅转发显式提供的字段；未提供的保留原值。
    // KeyframeProperties.copyWith 使用内部 sentinel 区分"未提供"与"显式 null"，
    // 这里直接透传 Object?（含 null），让 copyWith 处理"显式置 null"语义。
    if (!identical(x, _unset)) props = props.copyWith(x: x);
    if (!identical(y, _unset)) props = props.copyWith(y: y);
    if (!identical(opacity, _unset)) props = props.copyWith(opacity: opacity);
    if (!identical(scale, _unset)) props = props.copyWith(scale: scale);
    if (!identical(rotation, _unset)) props = props.copyWith(rotation: rotation);
    onChanged(keyframe.copyWith(properties: props));
  }
}

/// 用于区分"参数未提供"与"参数显式为 null"的哨兵对象。
const Object _unset = Object();

/// 单个可空属性字段：复选框启用 + 数值输入。
class _PropField extends StatelessWidget {
  const _PropField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = value != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Checkbox(
              value: enabled,
              onChanged: (v) => onChanged(v == true ? 0.0 : null),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: TextField(
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: hint ?? '',
              ),
              controller: TextEditingController(text: _fmt(value)),
              onChanged: (v) {
                final n = num.tryParse(v);
                if (n != null) onChanged(n.toDouble());
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(2);
  }
}

/// 预览播放按钮 + 预览区域。
class _PreviewButton extends StatefulWidget {
  const _PreviewButton({required this.spec});

  final AnimationSpec spec;

  @override
  State<_PreviewButton> createState() => _PreviewButtonState();
}

class _PreviewButtonState extends State<_PreviewButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: widget.spec.duration > 0
            ? widget.spec.duration.toInt()
            : 300,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _PreviewButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dur = widget.spec.duration > 0
        ? widget.spec.duration.toInt()
        : 300;
    _controller.duration = Duration(milliseconds: dur);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    setState(() => _tick++);
    await Future<void>.delayed(Duration.zero);
    if (widget.spec.delay > 0) {
      await Future<void>.delayed(
        Duration(milliseconds: widget.spec.delay.toInt()),
      );
    }
    if (mounted) await _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: _play,
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
          // 用 tick + spec.hashCode 作为 key，每次播放重建内部 AnimatedBuilder。
          child: _PreviewHost(
            key: ValueKey('kf-preview-$_tick-${widget.spec.hashCode}'),
            controller: _controller,
            spec: widget.spec,
          ),
        ),
      ],
    );
  }
}

/// 预览容器：使用外部传入的 [AnimationController] 渲染当前 [spec]。
class _PreviewHost extends StatelessWidget {
  const _PreviewHost({
    super.key,
    required this.controller,
    required this.spec,
  });

  final AnimationController controller;
  final AnimationSpec spec;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (spec.keyframes.isEmpty) return child!;
        // 直接用 KeyframeAnimationExecutor.buildKeyframeAnimation 会创建额外监听，
        // 这里直接同步计算当前进度属性。
        final props = _evalAt(spec, controller.value);
        return KeyframeAnimationExecutor.applyProperties(
          child: child!,
          props: props,
        );
      },
      child: _sampleChild(context),
    );
  }

  KeyframeProperties _evalAt(AnimationSpec spec, double t) {
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
