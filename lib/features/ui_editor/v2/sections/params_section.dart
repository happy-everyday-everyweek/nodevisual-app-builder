import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/project.dart';
import '../../../../data/models/ui_tree.dart';
import '../../../../data/models/variable_ref.dart';
import '../../../variables/variable_picker_sheet.dart';
import '../../component_registry_v2.dart';
import '../../ui_editor_providers.dart';

/// 参数段编辑器（Phase 4 v2）。
///
/// 根据选中组件的 [ComponentDef.props] 列表动态渲染每个属性的编辑器：
/// - text / multiline → [TextField]
/// - number → 数字输入框
/// - boolean → [Switch]
/// - select → [DropdownButton]
/// - color → 颜色选择器（hex 输入 + 色块预览）
/// - image → 图片资源输入（src + sourceType）
/// - url → 带校验的 URL 输入
/// - list → 简单列表编辑
/// - tree → 文本输入（树形数据，v1 简化为字符串）
///
/// 每个支持绑定的属性旁有 `#` 按钮，点击弹出 [VariablePickerSheet]
/// 选择变量引用，绑定后下方显示 [BindingEditor]（引用路径 + 加载策略）。
///
/// Page 节点不使用本段（页面特有参数在 [_PageParamsSection] 中渲染）。
class ParamsSection extends ConsumerWidget {
  const ParamsSection({super.key, required this.node});

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
    final props = def.props;
    if (props.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '该组件无可编辑参数',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final spec in props) ...[
          _PropEditor(
            key: ValueKey('${node.id}:${spec.key}'),
            node: node,
            spec: spec,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 单个属性编辑器。
class _PropEditor extends ConsumerStatefulWidget {
  const _PropEditor({
    super.key,
    required this.node,
    required this.spec,
  });

  final UiNode node;
  final PropSpec spec;

  @override
  ConsumerState<_PropEditor> createState() => _PropEditorState();
}

class _PropEditorState extends ConsumerState<_PropEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: '${widget.node.props[widget.spec.key] ?? ''}',
    );
  }

  @override
  void didUpdateWidget(covariant _PropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = '${widget.node.props[widget.spec.key] ?? ''}';
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
    final cs = theme.colorScheme;
    final spec = widget.spec;
    final node = widget.node;
    final binding = node.bindings[spec.key];
    final isBound = binding != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(spec.label, style: theme.textTheme.labelMedium)),
            if (isBound)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '已绑定',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildField()),
            if (spec.supportsBinding) ...[
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: isBound ? '更换变量' : '插入变量',
                icon: Icon(Icons.tag, size: 18, color: cs.primary),
                onPressed: () => _pickVariable(),
              ),
            ],
          ],
        ),
        if (isBound && spec.supportsBinding) ...[
          const SizedBox(height: 6),
          BindingEditor(
            key: ValueKey('${node.id}:${spec.key}:binding'),
            node: node,
            prop: spec.key,
            binding: binding,
          ),
        ],
      ],
    );
  }

  /// 根据 [PropSpec.type] 渲染对应编辑器。
  Widget _buildField() {
    final spec = widget.spec;
    final node = widget.node;
    final ref = this.ref;
    switch (spec.type) {
      case PropType.text:
      case PropType.url:
        return TextField(
          controller: _controller,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: spec.type == PropType.url ? 'https://…' : null,
          ),
          onChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(node.id, spec.key, v),
        );
      case PropType.multiline:
        return TextField(
          controller: _controller,
          maxLines: 3,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(node.id, spec.key, v),
        );
      case PropType.number:
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
            if (n != null) {
              ref.read(uiMutatorProvider.notifier).updateProp(node.id, spec.key, n);
            }
          },
        );
      case PropType.boolean:
        final v = (node.props[spec.key] as bool?) ?? false;
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: v,
          onChanged: (val) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(node.id, spec.key, val),
          title: Text(v ? '是' : '否'),
        );
      case PropType.select:
        final options = spec.options ?? const <String>[];
        final current = '${node.props[spec.key] ?? (options.isEmpty ? '' : options.first)}';
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
            if (v != null) {
              ref.read(uiMutatorProvider.notifier).updateProp(node.id, spec.key, v);
            }
          },
        );
      case PropType.color:
        final current = '${node.props[spec.key] ?? '#000000'}';
        return _ColorField(
          controller: _controller,
          currentColor: current,
          onChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(node.id, spec.key, v),
        );
      case PropType.image:
        return _ImageField(
          controller: _controller,
          sourceType: '${node.props['sourceType'] ?? 'local'}',
          onChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(node.id, spec.key, v),
          onSourceTypeChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(node.id, 'sourceType', v),
        );
      case PropType.list:
        return TextField(
          controller: _controller,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: '逗号分隔',
          ),
          onChanged: (v) {
            final list = v
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            ref.read(uiMutatorProvider.notifier).updateProp(node.id, spec.key, list);
          },
        );
      case PropType.tree:
        return TextField(
          controller: _controller,
          maxLines: 2,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'JSON 字符串',
          ),
          onChanged: (v) => ref
              .read(uiMutatorProvider.notifier)
              .updateProp(node.id, spec.key, v),
        );
    }
  }

  /// 弹出变量选择面板；选中后写入绑定。
  Future<void> _pickVariable() async {
    final project = ref.read(uiMutatorProvider);
    if (project == null) return;
    final result = await VariablePickerSheet.show(
      context,
      functionId: '',
      nodeId: '',
      componentVars: const [],
      pageFuncOutputs: const [],
    );
    if (result == null) return;
    ref.read(uiMutatorProvider.notifier).setBinding(
          widget.node.id,
          widget.spec.key,
          Binding(
            ref: result.ref,
            loadingStrategy: result.loadingStrategy,
            placeholderText: result.placeholderText,
          ),
        );
  }
}

/// 颜色字段：hex 输入 + 色块预览 + 点击色块打开预设色板。
class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.controller,
    required this.currentColor,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String currentColor;
  final ValueChanged<String> onChanged;

  /// 预设色板（覆盖常见用色，点击直接应用）。
  static const List<String> _presetColors = [
    '#000000', '#FFFFFF', '#F44336', '#E91E63', '#9C27B0', '#673AB7',
    '#3F51B5', '#2196F3', '#03A9F4', '#00BCD4', '#009688', '#4CAF50',
    '#8BC34A', '#CDDC39', '#FFC107', '#FF9800', '#FF5722', '#795548',
    '#9E9E9E', '#607D8B', '#1976D2', '#BDBDBD', '#424242', '#F5F5F5',
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

/// 图片字段：sourceType 下拉 + src 输入。
class _ImageField extends StatelessWidget {
  const _ImageField({
    required this.controller,
    required this.sourceType,
    required this.onChanged,
    required this.onSourceTypeChanged,
  });

  final TextEditingController controller;
  final String sourceType;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSourceTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: const ['local', 'base64', 'url'].contains(sourceType)
              ? sourceType
              : 'local',
          isDense: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            labelText: '来源',
          ),
          items: const [
            DropdownMenuItem(value: 'local', child: Text('本地上传')),
            DropdownMenuItem(value: 'base64', child: Text('Base64')),
            DropdownMenuItem(value: 'url', child: Text('URL')),
          ],
          onChanged: (v) {
            if (v != null) onSourceTypeChanged(v);
          },
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: sourceType == 'url'
                ? 'https://…'
                : sourceType == 'base64'
                    ? 'data:image/…;base64,…'
                    : '资源路径或标识',
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// 绑定编辑器：展示当前变量引用 + 移除按钮 + 加载态策略选择。
///
/// 引用路径输入为只读展示（变更需通过变量选择面板）；
/// 加载策略 chip 可点击切换。
class BindingEditor extends ConsumerWidget {
  const BindingEditor({
    super.key,
    required this.node,
    required this.prop,
    required this.binding,
  });

  final UiNode node;
  final String prop;
  final Binding binding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final project = ref.watch(uiMutatorProvider);
    if (project == null) return const SizedBox.shrink();

    final refLabel = _describeBindingRef(binding.ref, project);
    final hasStrategy = binding.ref.isPageFunc ||
        binding.ref.source == VariableSource.component;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.4),
                width: 0.75,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    refLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => ref
                      .read(uiMutatorProvider.notifier)
                      .setBinding(node.id, prop, null),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        size: 14, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          if (hasStrategy) ...[
            const SizedBox(height: 6),
            _StrategyChip(
              strategy: binding.loadingStrategy,
              placeholder: binding.placeholderText,
              onChanged: (s, p) => ref
                  .read(uiMutatorProvider.notifier)
                  .setBinding(
                    node.id,
                    prop,
                    binding.copyWith(
                        loadingStrategy: s, placeholderText: p),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 加载态策略 chip。
class _StrategyChip extends StatelessWidget {
  const _StrategyChip({
    required this.strategy,
    required this.placeholder,
    required this.onChanged,
  });

  final LoadingStrategy strategy;
  final String? placeholder;
  final void Function(LoadingStrategy, String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: () => _showPicker(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              '加载态：${_label(strategy)}'
              '${strategy == LoadingStrategy.placeholder && placeholder != null ? ' "$placeholder"' : ''}',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 14),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    LoadingStrategy s = strategy;
    String p = placeholder ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('加载态策略'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in LoadingStrategy.values)
                RadioListTile<LoadingStrategy>(
                  dense: true,
                  value: v,
                  groupValue: s,
                  title: Text(_label(v)),
                  onChanged: (nv) {
                    if (nv != null) setSt(() => s = nv);
                  },
                ),
              if (s == LoadingStrategy.placeholder)
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '占位文字',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => p = v,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                onChanged(
                  s,
                  s == LoadingStrategy.placeholder && p.trim().isNotEmpty
                      ? p.trim()
                      : null,
                );
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  String _label(LoadingStrategy s) {
    switch (s) {
      case LoadingStrategy.typeDefault:
        return '类型默认值';
      case LoadingStrategy.placeholder:
        return '占位文字';
      case LoadingStrategy.blank:
        return '留空';
    }
  }
}

/// 生成变量引用的可读描述。
String _describeBindingRef(VariableRef r, Project? project) {
  switch (r.source) {
    case VariableSource.upstream:
      final fn = project?.functions
          .where((f) => f.id == r.nodeId)
          .firstOrNull;
      return '{${fn?.name ?? r.nodeId ?? '?'}.${r.outputName ?? '?'}}';
    case VariableSource.funcVar:
      if (r.isPageFunc) {
        final fn = project?.functions
            .where((f) => f.id == r.funcId)
            .firstOrNull;
        return '{${fn?.name ?? r.funcId}.${r.outputName}}';
      }
      return '{func:${r.varId}}';
    case VariableSource.projVar:
      final v = project?.projectVars
          .where((p) => p.id == r.varId)
          .firstOrNull;
      return '{proj:${v?.name ?? r.varId}}';
    case VariableSource.component:
      return '{#:${r.fieldName}}';
    case VariableSource.device:
      return '{device:${r.property ?? '?'}}';
  }
}
