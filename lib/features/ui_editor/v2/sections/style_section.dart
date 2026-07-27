import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/ui_tree.dart';
import '../../component_registry_v2.dart';
import '../../ui_editor_providers.dart';

/// 样式段编辑器（Phase 4 v2）。
///
/// 根据选中组件的 [ComponentDef.styles] 列表动态渲染每个样式的编辑器：
/// - text → [TextField]
/// - number → 数字输入框
/// - boolean → [Switch]
/// - select → [DropdownButton]
/// - color → 颜色选择器（hex + 色块）
/// - size → 数值 + 单位（px / %）
/// - spacing → 4 方向独立数值（如 padding / margin）
///
/// 末尾固定包含 [AnimationSection]（入场/出场/触发动画配置，可展开/折叠）。
class StyleSection extends ConsumerWidget {
  const StyleSection({super.key, required this.node});

  final UiNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final def = ComponentRegistry.byType(node.type);
    if (def == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '未知组件类型：${node.type}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final styles = def.styles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final spec in styles) ...[
          _StyleEditor(
            key: ValueKey('${node.id}:${spec.key}'),
            node: node,
            spec: spec,
          ),
          const SizedBox(height: 8),
        ],
        if (styles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '该组件无可编辑样式',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const Divider(),
        AnimationSection(node: node),
      ],
    );
  }
}

/// 单个样式编辑器（按 [StyleSpec.type] 分支）。
class _StyleEditor extends ConsumerStatefulWidget {
  const _StyleEditor({
    super.key,
    required this.node,
    required this.spec,
  });

  final UiNode node;
  final StyleSpec spec;

  @override
  ConsumerState<_StyleEditor> createState() => _StyleEditorState();
}

class _StyleEditorState extends ConsumerState<_StyleEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: '${widget.node.style[widget.spec.key] ?? widget.spec.defaultValue ?? ''}',
    );
  }

  @override
  void didUpdateWidget(covariant _StyleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current =
        '${widget.node.style[widget.spec.key] ?? widget.spec.defaultValue ?? ''}';
    if (_controller.text != current) {
      _controller.text = current;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(spec.label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        _buildField(),
      ],
    );
  }

  Widget _buildField() {
    final spec = widget.spec;
    final node = widget.node;
    final mutator = ref.read(uiMutatorProvider.notifier);
    switch (spec.type) {
      case StyleType.text:
        return TextField(
          controller: _controller,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => mutator.updateStyleProp(node.id, spec.key, v),
        );
      case StyleType.number:
        return TextField(
          controller: _controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            final n = num.tryParse(v);
            if (n != null) mutator.updateStyleProp(node.id, spec.key, n);
          },
        );
      case StyleType.boolean:
        final v = (node.style[spec.key] as bool?) ?? false;
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: v,
          onChanged: (val) => mutator.updateStyleProp(node.id, spec.key, val),
          title: Text(v ? '是' : '否'),
        );
      case StyleType.select:
        final options = spec.options ?? const <String>[];
        final current =
            '${node.style[spec.key] ?? spec.defaultValue ?? (options.isEmpty ? '' : options.first)}';
        final value = options.contains(current) ? current : null;
        return DropdownButtonFormField<String>(
          value: value,
          isDense: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) {
            if (v != null) mutator.updateStyleProp(node.id, spec.key, v);
          },
        );
      case StyleType.color:
        return _ColorField(
          controller: _controller,
          currentColor:
              '${node.style[spec.key] ?? spec.defaultValue ?? '#000000'}',
          onChanged: (v) => mutator.updateStyleProp(node.id, spec.key, v),
        );
      case StyleType.size:
        return _SizeField(
          controller: _controller,
          spec: node.style[spec.key],
          defaultUnit: SizeUnit.px,
          onChanged: (value, unit) {
            final map = <String, dynamic>{
              'value': value,
              'unit': unit.toJson(),
            };
            mutator.updateStyleProp(node.id, spec.key, map);
          },
        );
      case StyleType.spacing:
        return _SpacingField(
          spec: node.style[spec.key],
          onChanged: (top, bottom, left, right) {
            final map = <String, dynamic>{
              'top': top,
              'bottom': bottom,
              'left': left,
              'right': right,
            };
            mutator.updateStyleProp(node.id, spec.key, map);
          },
        );
    }
  }
}

/// 颜色字段：hex 输入 + 色块预览。
class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.controller,
    required this.currentColor,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String currentColor;
  final ValueChanged<String> onChanged;

  static const List<String> _presetColors = [
    '#000000', '#FFFFFF', '#F44336', '#E91E63', '#9C27B0', '#673AB7',
    '#3F51B5', '#2196F3', '#03A9F4', '#00BCD4', '#009688', '#4CAF50',
    '#8BC34A', '#CDDC39', '#FFC107', '#FF9800', '#FF5722', '#795548',
    '#9E9E9E', '#607D8B', '#1976D2', '#BDBDBD', '#424242', '#F5F5F5',
    'transparent',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        GestureDetector(
          onTap: () => _showPresetPalette(context),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _parseColor(currentColor),
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '#RRGGBB',
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  void _showPresetPalette(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择颜色'),
        content: SizedBox(
          width: 240,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final hex in _presetColors)
                InkWell(
                  onTap: () {
                    controller.text = hex;
                    onChanged(hex);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _parseColor(hex),
                      border: Border.all(
                        color: Theme.of(ctx).colorScheme.outline,
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String value) {
    if (value == 'transparent') return Colors.transparent;
    final hex = value.replaceFirst('#', '');
    if (hex.length == 6 || hex.length == 8) {
      try {
        final rgba = int.parse(hex, radix: 16);
        if (hex.length == 6) return Color(0xFF000000 | rgba);
        return Color(rgba);
      } catch (_) {
        // 忽略
      }
    }
    return Colors.transparent;
  }
}

/// 尺寸字段（数值 + 单位）。
class _SizeField extends StatelessWidget {
  const _SizeField({
    required this.controller,
    required this.spec,
    required this.defaultUnit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final dynamic spec;
  final SizeUnit defaultUnit;
  final void Function(double value, SizeUnit unit) onChanged;

  @override
  Widget build(BuildContext context) {
    final currentValue = (spec is Map ? (spec['value'] as num?)?.toDouble() : null) ?? 0;
    final unitStr = spec is Map ? (spec['unit'] as String?) : null;
    final currentUnit = SizeUnit.fromJson(unitStr) == SizeUnit.percent
        ? SizeUnit.percent
        : defaultUnit;

    // 同步 controller 文本
    if (controller.text != '$currentValue' && controller.text != '${currentValue.round()}') {
      // 仅当 controller 当前文本非数字或与值不一致时同步
      final n = num.tryParse(controller.text);
      if (n == null || n != currentValue) {
        controller.text = currentValue == currentValue.roundToDouble()
            ? '${currentValue.round()}'
            : '$currentValue';
      }
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              final n = num.tryParse(v);
              if (n != null) onChanged(n.toDouble(), currentUnit);
            },
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 90,
          child: DropdownButtonFormField<SizeUnit>(
            value: currentUnit,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: SizeUnit.px, child: Text('px')),
              DropdownMenuItem(value: SizeUnit.percent, child: Text('%')),
            ],
            onChanged: (v) {
              if (v != null) onChanged(currentValue, v);
            },
          ),
        ),
      ],
    );
  }
}

/// 间距字段（4 方向独立数值）。
class _SpacingField extends StatefulWidget {
  const _SpacingField({
    required this.spec,
    required this.onChanged,
  });

  final dynamic spec;
  final void Function(double top, double bottom, double left, double right)
      onChanged;

  @override
  State<_SpacingField> createState() => _SpacingFieldState();
}

class _SpacingFieldState extends State<_SpacingField> {
  late final TextEditingController _top;
  late final TextEditingController _bottom;
  late final TextEditingController _left;
  late final TextEditingController _right;

  @override
  void initState() {
    super.initState();
    final m = widget.spec is Map
        ? widget.spec as Map<dynamic, dynamic>
        : <dynamic, dynamic>{};
    _top = TextEditingController(text: _fmt(m['top']));
    _bottom = TextEditingController(text: _fmt(m['bottom']));
    _left = TextEditingController(text: _fmt(m['left']));
    _right = TextEditingController(text: _fmt(m['right']));
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final d = (v as num).toDouble();
    return d == d.roundToDouble() ? '${d.round()}' : '$d';
  }

  void _emit() {
    widget.onChanged(
      num.tryParse(_top.text)?.toDouble() ?? 0,
      num.tryParse(_bottom.text)?.toDouble() ?? 0,
      num.tryParse(_left.text)?.toDouble() ?? 0,
      num.tryParse(_right.text)?.toDouble() ?? 0,
    );
  }

  @override
  void dispose() {
    _top.dispose();
    _bottom.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row('上', _top),
        const SizedBox(height: 4),
        _row('下', _bottom),
        const SizedBox(height: 4),
        _row('左', _left),
        const SizedBox(height: 4),
        _row('右', _right),
      ],
    );
  }

  Widget _row(String label, TextEditingController controller) {
    return Row(
      children: [
        SizedBox(width: 24, child: Text(label)),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
        ),
      ],
    );
  }
}

/// 动画配置区（入场/出场/触发动画）。
///
/// 可展开/折叠；展开时显示三个子区段：
/// - 入场动画：预设 + 时长 + 延迟 + 缓动
/// - 出场动画：预设 + 时长 + 延迟 + 缓动
/// - 触发动画列表：每个 entry 为 事件 → 动画配置
class AnimationSection extends ConsumerStatefulWidget {
  const AnimationSection({super.key, required this.node});

  final UiNode node;

  @override
  ConsumerState<AnimationSection> createState() => _AnimationSectionState();
}

class _AnimationSectionState extends ConsumerState<AnimationSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.animation, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '动画配置',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (widget.node.animations != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '已配置',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontSize: 10,
                      ),
                    ),
                  ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.chevron_right,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          _AnimationSpecEditor(
            label: '入场动画',
            spec: widget.node.animations?.entrance,
            onChanged: (spec) {
              final cur = widget.node.animations ?? const AnimationsConfig();
              ref
                  .read(uiMutatorProvider.notifier)
                  .updateAnimations(widget.node.id, cur.copyWith(entrance: spec));
            },
            onClear: () {
              final cur = widget.node.animations;
              if (cur == null) return;
              ref
                  .read(uiMutatorProvider.notifier)
                  .updateAnimations(widget.node.id, cur.copyWith(entrance: null));
            },
          ),
          const SizedBox(height: 8),
          _AnimationSpecEditor(
            label: '出场动画',
            spec: widget.node.animations?.exit,
            onChanged: (spec) {
              final cur = widget.node.animations ?? const AnimationsConfig();
              ref
                  .read(uiMutatorProvider.notifier)
                  .updateAnimations(widget.node.id, cur.copyWith(exit: spec));
            },
            onClear: () {
              final cur = widget.node.animations;
              if (cur == null) return;
              ref
                  .read(uiMutatorProvider.notifier)
                  .updateAnimations(widget.node.id, cur.copyWith(exit: null));
            },
          ),
          const SizedBox(height: 12),
          _TriggeredAnimationsEditor(node: widget.node),
        ],
      ],
    );
  }
}

/// 单个 [AnimationSpec] 编辑器（预设 + 时长 + 延迟 + 缓动）。
class _AnimationSpecEditor extends ConsumerStatefulWidget {
  const _AnimationSpecEditor({
    required this.label,
    required this.spec,
    required this.onChanged,
    required this.onClear,
  });

  final String label;
  final AnimationSpec? spec;
  final ValueChanged<AnimationSpec> onChanged;
  final VoidCallback onClear;

  @override
  ConsumerState<_AnimationSpecEditor> createState() =>
      _AnimationSpecEditorState();
}

class _AnimationSpecEditorState extends ConsumerState<_AnimationSpecEditor> {
  late final TextEditingController _duration;
  late final TextEditingController _delay;

  @override
  void initState() {
    super.initState();
    _duration = TextEditingController(text: '${widget.spec?.duration ?? 300}');
    _delay = TextEditingController(text: '${widget.spec?.delay ?? 0}');
  }

  @override
  void didUpdateWidget(covariant _AnimationSpecEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final d = '${widget.spec?.duration ?? 300}';
    if (_duration.text != d) _duration.text = d;
    final dl = '${widget.spec?.delay ?? 0}';
    if (_delay.text != dl) _delay.text = dl;
  }

  @override
  void dispose() {
    _duration.dispose();
    _delay.dispose();
    super.dispose();
  }

  void _emit({
    AnimationPreset? preset,
    double? duration,
    double? delay,
    EasingType? easing,
  }) {
    final cur = widget.spec ?? const AnimationSpec();
    widget.onChanged(cur.copyWith(
      preset: preset,
      duration: duration,
      delay: delay,
      easing: easing,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;
    final preset = spec?.preset;
    final easing = spec?.easing ?? EasingType.easeInOut;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (spec != null)
                InkWell(
                  onTap: widget.onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 预设动画
          DropdownButtonFormField<AnimationPreset>(
            value: preset,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: '预设',
            ),
            items: const [
              DropdownMenuItem(
                  value: AnimationPreset.fade, child: Text('淡入')),
              DropdownMenuItem(
                  value: AnimationPreset.slide, child: Text('滑动')),
              DropdownMenuItem(
                  value: AnimationPreset.scale, child: Text('缩放')),
              DropdownMenuItem(
                  value: AnimationPreset.bounce, child: Text('弹跳')),
              DropdownMenuItem(
                  value: AnimationPreset.rotate, child: Text('旋转')),
              DropdownMenuItem(
                  value: AnimationPreset.elastic, child: Text('弹性')),
            ],
            onChanged: (v) {
              if (v != null) _emit(preset: v);
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: '时长(ms)',
                  ),
                  onChanged: (v) {
                    final n = num.tryParse(v);
                    if (n != null) _emit(duration: n.toDouble());
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _delay,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: '延迟(ms)',
                  ),
                  onChanged: (v) {
                    final n = num.tryParse(v);
                    if (n != null) _emit(delay: n.toDouble());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
              if (v != null) _emit(easing: v);
            },
          ),
        ],
      ),
    );
  }
}

/// 触发动画列表编辑器：事件 → 动画配置。
class _TriggeredAnimationsEditor extends ConsumerStatefulWidget {
  const _TriggeredAnimationsEditor({required this.node});

  final UiNode node;

  @override
  ConsumerState<_TriggeredAnimationsEditor> createState() =>
      _TriggeredAnimationsEditorState();
}

class _TriggeredAnimationsEditorState
    extends ConsumerState<_TriggeredAnimationsEditor> {
  late final TextEditingController _eventController;

  @override
  void initState() {
    super.initState();
    _eventController = TextEditingController();
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final triggered = widget.node.animations?.triggered ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '触发动画',
          style: theme.textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (triggered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '尚无触发动画。下方输入事件名并添加。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        for (int i = 0; i < triggered.length; i++)
          _TriggeredItem(
            node: widget.node,
            index: i,
            item: triggered[i],
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _eventController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '事件名（如 onTap）',
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              icon: const Icon(Icons.add, size: 18),
              tooltip: '添加触发动画',
              onPressed: () {
                final event = _eventController.text.trim();
                if (event.isEmpty) return;
                final cur =
                    widget.node.animations ?? const AnimationsConfig();
                final newList = [
                  ...cur.triggered,
                  TriggeredAnimation(
                    event: event,
                    animation: const AnimationSpec(
                      preset: AnimationPreset.fade,
                      duration: 300,
                    ),
                  ),
                ];
                ref.read(uiMutatorProvider.notifier).updateAnimations(
                      widget.node.id,
                      cur.copyWith(triggered: newList),
                    );
                _eventController.clear();
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 单个触发动画项：事件名 + 时长 + 移除按钮。
class _TriggeredItem extends ConsumerWidget {
  const _TriggeredItem({
    required this.node,
    required this.index,
    required this.item,
  });

  final UiNode node;
  final int index;
  final TriggeredAnimation item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.flash_on, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${item.event} · ${item.animation.preset?.name ?? "自定义"} · ${item.animation.duration}ms',
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () {
              final cur = node.animations;
              if (cur == null) return;
              final newList = List<TriggeredAnimation>.from(cur.triggered)
                ..removeAt(index);
              ref.read(uiMutatorProvider.notifier).updateAnimations(
                    node.id,
                    cur.copyWith(triggered: newList),
                  );
            },
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
