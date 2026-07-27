import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ui_tree.dart';
import '../ui_editor_providers.dart';
import '../widgets/grid9_selector.dart';

/// 布局属性面板：编辑选中组件的 [LayoutConfig]。
///
/// 支持双模布局编辑：
/// - **相对布局（9宫格）**：选择归属 cell、设置距边距离与方向
/// - **绝对布局**：设置 x/y 坐标（px 或 %）
///
/// 两种模式均可编辑宽高（含单位与 minPx/maxPx clamp）与 4 方向外间距。
/// 所有变更通过 [UiMutator.updateLayout] 实时提交。
///
/// 当节点未启用布局时（[UiNode.layout] 为 null），显示"启用布局"按钮，
/// 创建默认相对布局配置。
class LayoutPanel extends ConsumerWidget {
  const LayoutPanel({super.key, required this.nodeId});

  /// 被编辑的节点 id。
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(uiMutatorProvider);
    if (project == null) return const SizedBox.shrink();

    final found = ref.read(uiMutatorProvider.notifier).findNode(nodeId);
    if (found == null) return const SizedBox.shrink();

    final node = found.node;
    final layout = node.layout;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LayoutSectionHeader(title: '布局', icon: Icons.view_quilt_rounded),
          if (layout == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '未启用布局配置，组件使用默认流式布局。'
                '启用后将按 9 宫格相对布局或绝对坐标定位。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('启用布局'),
              onPressed: () => _commit(ref, _defaultLayout()),
            ),
          ] else ...[
            _buildModeSelector(context, ref, layout),
            const SizedBox(height: 12),
            if (layout.mode == LayoutMode.relative)
              _buildRelativeEditors(context, ref, layout)
            else
              _buildAbsoluteEditors(context, ref, layout),
            const Divider(),
            _buildSizeEditors(context, ref, layout),
            const Divider(),
            _buildMarginEditors(context, ref, layout),
            const Divider(),
            TextButton.icon(
              icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
              label: Text('清除布局', style: TextStyle(color: cs.error)),
              onPressed: () =>
                  ref.read(uiMutatorProvider.notifier).updateLayout(nodeId, null),
            ),
          ],
        ],
      ),
    );
  }

  /// 默认布局配置（启用布局时创建）。
  static LayoutConfig _defaultLayout() => const LayoutConfig(
        mode: LayoutMode.relative,
        cell: GridCell.center(),
        width: SizeSpec(value: 100, unit: SizeUnit.percent),
        height: SizeSpec(value: 50, unit: SizeUnit.px),
      );

  void _commit(WidgetRef ref, LayoutConfig layout) {
    ref.read(uiMutatorProvider.notifier).updateLayout(nodeId, layout);
  }

  // ---- 模式选择 ----

  Widget _buildModeSelector(
    BuildContext context,
    WidgetRef ref,
    LayoutConfig layout,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('布局模式', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        SegmentedButton<LayoutMode>(
          segments: const [
            ButtonSegment(
              value: LayoutMode.relative,
              label: Text('9宫格'),
              icon: Icon(Icons.grid_view, size: 18),
            ),
            ButtonSegment(
              value: LayoutMode.absolute,
              label: Text('绝对坐标'),
              icon: Icon(Icons.my_location, size: 18),
            ),
          ],
          selected: {layout.mode},
          onSelectionChanged: (selected) =>
              _commit(ref, layout.copyWith(mode: selected.first)),
        ),
      ],
    );
  }

  // ---- 相对布局编辑器 ----

  Widget _buildRelativeEditors(
    BuildContext context,
    WidgetRef ref,
    LayoutConfig layout,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('归属宫格', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          '点击选择组件在 9 宫格中的归属位置，长按格子查看堆叠方向说明。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Grid9Selector(
          selectedCell: layout.cell?.cell,
          onCellSelected: (cell) => _commit(ref, layout.copyWith(cell: cell)),
        ),
        const SizedBox(height: 12),
        Text('距边距离', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _LayoutTextField(
                label: '距离',
                value: layout.distance?.value ?? 0,
                onChanged: (v) => _commit(
                  ref,
                  layout.copyWith(
                    distance: (layout.distance ??
                            const DistanceSpec(
                              edge: DistanceEdge.top,
                              value: 0,
                            ))
                        .copyWith(value: v),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _UnitDropdown<SizeUnit>(
                label: '单位',
                value: layout.distance?.unit ?? SizeUnit.percent,
                items: const [
                  (SizeUnit.px, 'px'),
                  (SizeUnit.percent, '%'),
                ],
                onChanged: (unit) => _commit(
                  ref,
                  layout.copyWith(
                    distance: (layout.distance ??
                            const DistanceSpec(
                              edge: DistanceEdge.top,
                              value: 0,
                            ))
                        .copyWith(unit: unit),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _UnitDropdown<DistanceEdge>(
                label: '方向',
                value: layout.distance?.edge ?? DistanceEdge.top,
                items: const [
                  (DistanceEdge.top, '上'),
                  (DistanceEdge.bottom, '下'),
                  (DistanceEdge.left, '左'),
                  (DistanceEdge.right, '右'),
                  (DistanceEdge.center, '中心'),
                ],
                onChanged: (edge) => _commit(
                  ref,
                  layout.copyWith(
                    distance: (layout.distance ??
                            const DistanceSpec(
                              edge: DistanceEdge.top,
                              value: 0,
                            ))
                        .copyWith(edge: edge),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- 绝对布局编辑器 ----

  Widget _buildAbsoluteEditors(
    BuildContext context,
    WidgetRef ref,
    LayoutConfig layout,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('坐标位置', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _LayoutTextField(
                label: 'X',
                value: layout.x?.value ?? 0,
                onChanged: (v) => _commit(
                  ref,
                  layout.copyWith(
                    x: (layout.x ?? const PositionSpec(value: 0))
                        .copyWith(value: v),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 84,
              child: _UnitDropdown<SizeUnit>(
                label: '单位',
                value: layout.x?.unit ?? SizeUnit.percent,
                items: const [
                  (SizeUnit.px, 'px'),
                  (SizeUnit.percent, '%'),
                ],
                onChanged: (unit) => _commit(
                  ref,
                  layout.copyWith(
                    x: (layout.x ?? const PositionSpec(value: 0))
                        .copyWith(unit: unit),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _LayoutTextField(
                label: 'Y',
                value: layout.y?.value ?? 0,
                onChanged: (v) => _commit(
                  ref,
                  layout.copyWith(
                    y: (layout.y ?? const PositionSpec(value: 0))
                        .copyWith(value: v),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 84,
              child: _UnitDropdown<SizeUnit>(
                label: '单位',
                value: layout.y?.unit ?? SizeUnit.percent,
                items: const [
                  (SizeUnit.px, 'px'),
                  (SizeUnit.percent, '%'),
                ],
                onChanged: (unit) => _commit(
                  ref,
                  layout.copyWith(
                    y: (layout.y ?? const PositionSpec(value: 0))
                        .copyWith(unit: unit),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- 尺寸编辑器 ----

  Widget _buildSizeEditors(
    BuildContext context,
    WidgetRef ref,
    LayoutConfig layout,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('尺寸', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        _SizeField(
          label: '宽',
          spec: layout.width,
          onChanged: (spec) => _commit(ref, layout.copyWith(width: spec)),
        ),
        const SizedBox(height: 6),
        _SizeField(
          label: '高',
          spec: layout.height,
          onChanged: (spec) => _commit(ref, layout.copyWith(height: spec)),
        ),
      ],
    );
  }

  // ---- 外间距编辑器 ----

  Widget _buildMarginEditors(
    BuildContext context,
    WidgetRef ref,
    LayoutConfig layout,
  ) {
    final theme = Theme.of(context);
    final margin = layout.margin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('外间距', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        _MarginField(
          label: '上',
          edge: margin.top,
          onChanged: (e) => _commit(ref, layout.copyWith(margin: margin.copyWith(top: e))),
        ),
        const SizedBox(height: 6),
        _MarginField(
          label: '下',
          edge: margin.bottom,
          onChanged: (e) => _commit(ref, layout.copyWith(margin: margin.copyWith(bottom: e))),
        ),
        const SizedBox(height: 6),
        _MarginField(
          label: '左',
          edge: margin.left,
          onChanged: (e) => _commit(ref, layout.copyWith(margin: margin.copyWith(left: e))),
        ),
        const SizedBox(height: 6),
        _MarginField(
          label: '右',
          edge: margin.right,
          onChanged: (e) => _commit(ref, layout.copyWith(margin: margin.copyWith(right: e))),
        ),
      ],
    );
  }
}

// ============================================================================
// 私有辅助 Widget
// ============================================================================

/// 面板分区标题（与 segment_view 中的 _SectionHeader 样式一致）。
class _LayoutSectionHeader extends StatelessWidget {
  const _LayoutSectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(title, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// 数值输入框（带标签），自动同步外部值变更。
class _LayoutTextField extends StatefulWidget {
  const _LayoutTextField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_LayoutTextField> createState() => _LayoutTextFieldState();
}

class _LayoutTextFieldState extends State<_LayoutTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
  }

  @override
  void didUpdateWidget(covariant _LayoutTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _formatValue(widget.value);
    // 仅在外部值与输入框当前文本不一致时同步，避免编辑过程中光标跳动。
    if (_controller.text != current) {
      _controller.text = current;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _formatValue(double v) {
    // 去除多余的 .0，使整数显示更简洁。
    if (v == v.roundToDouble()) return '${v.round()}';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: widget.label,
        labelStyle: theme.textTheme.labelSmall,
      ),
      onChanged: (v) {
        final n = double.tryParse(v);
        if (n != null) widget.onChanged(n);
      },
    );
  }
}

/// 下拉选择框（带标签），用于单位、方向等枚举值选择。
class _UnitDropdown<T> extends StatelessWidget {
  const _UnitDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
        labelStyle: theme.textTheme.labelSmall,
      ),
      items: [
        for (final (val, text) in items)
          DropdownMenuItem<T>(value: val, child: Text(text)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// 尺寸编辑器（值 + 单位 + 可选 minPx/maxPx）。
///
/// 当单位为 [SizeUnit.percent] 时展开 minPx/maxPx 输入；为 [SizeUnit.px] 时隐藏。
class _SizeField extends StatefulWidget {
  const _SizeField({
    required this.label,
    required this.spec,
    required this.onChanged,
  });

  final String label;
  final SizeSpec spec;
  final ValueChanged<SizeSpec> onChanged;

  @override
  State<_SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<_SizeField> {
  late final TextEditingController _valueController;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;

  @override
  void initState() {
    super.initState();
    _valueController =
        TextEditingController(text: _formatValue(widget.spec.value));
    _minController = TextEditingController(
      text: widget.spec.minPx != null ? _formatValue(widget.spec.minPx!) : '',
    );
    _maxController = TextEditingController(
      text: widget.spec.maxPx != null ? _formatValue(widget.spec.maxPx!) : '',
    );
  }

  @override
  void didUpdateWidget(covariant _SizeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final valueText = _formatValue(widget.spec.value);
    if (_valueController.text != valueText) {
      _valueController.text = valueText;
    }
    final minText =
        widget.spec.minPx != null ? _formatValue(widget.spec.minPx!) : '';
    if (_minController.text != minText) {
      _minController.text = minText;
    }
    final maxText =
        widget.spec.maxPx != null ? _formatValue(widget.spec.maxPx!) : '';
    if (_maxController.text != maxText) {
      _maxController.text = maxText;
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  static String _formatValue(double v) {
    if (v == v.roundToDouble()) return '${v.round()}';
    return '$v';
  }

  void _commit({
    double? value,
    SizeUnit? unit,
    Object? minPx = _sentinel,
    Object? maxPx = _sentinel,
  }) {
    widget.onChanged(
      widget.spec.copyWith(
        value: value,
        unit: unit,
        minPx: minPx,
        maxPx: maxPx,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPercent = widget.spec.unit == SizeUnit.percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _valueController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: widget.label,
                  labelStyle: theme.textTheme.labelSmall,
                ),
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) _commit(value: n);
                },
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 84,
              child: _UnitDropdown<SizeUnit>(
                label: '单位',
                value: widget.spec.unit,
                items: const [
                  (SizeUnit.px, 'px'),
                  (SizeUnit.percent, '%'),
                ],
                onChanged: (unit) => _commit(unit: unit),
              ),
            ),
          ],
        ),
        if (isPercent) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _minController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelText: '最小(px)',
                    labelStyle: theme.textTheme.labelSmall,
                    hintText: '不限',
                  ),
                  onChanged: (v) {
                    if (v.isEmpty) {
                      _commit(minPx: null);
                    } else {
                      final n = double.tryParse(v);
                      if (n != null) _commit(minPx: n);
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _maxController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    labelText: '最大(px)',
                    labelStyle: theme.textTheme.labelSmall,
                    hintText: '不限',
                  ),
                  onChanged: (v) {
                    if (v.isEmpty) {
                      _commit(maxPx: null);
                    } else {
                      final n = double.tryParse(v);
                      if (n != null) _commit(maxPx: n);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 单方向外间距编辑器（值 + 单位）。
class _MarginField extends StatefulWidget {
  const _MarginField({
    required this.label,
    required this.edge,
    required this.onChanged,
  });

  final String label;
  final EdgeValue edge;
  final ValueChanged<EdgeValue> onChanged;

  @override
  State<_MarginField> createState() => _MarginFieldState();
}

class _MarginFieldState extends State<_MarginField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: _formatValue(widget.edge.value));
  }

  @override
  void didUpdateWidget(covariant _MarginField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _formatValue(widget.edge.value);
    if (_controller.text != current) {
      _controller.text = current;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _formatValue(double v) {
    if (v == v.roundToDouble()) return '${v.round()}';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Center(
            child: Text(widget.label, style: theme.textTheme.labelMedium),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 3,
          child: TextField(
            controller: _controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: '0',
            ),
            onChanged: (v) {
              final n = double.tryParse(v);
              if (n != null) widget.onChanged(widget.edge.copyWith(value: n));
            },
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 84,
          child: _UnitDropdown<SizeUnit>(
            label: '单位',
            value: widget.edge.unit,
            items: const [
              (SizeUnit.px, 'px'),
              (SizeUnit.percent, '%'),
            ],
            onChanged: (unit) =>
                widget.onChanged(widget.edge.copyWith(unit: unit)),
          ),
        ),
      ],
    );
  }
}

const Object _sentinel = Object();
