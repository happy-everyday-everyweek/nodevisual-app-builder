import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/models/function_def.dart';
import '../../data/models/node.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/variable_ref.dart';
import '../project/project_providers.dart';
import 'graph_providers.dart';
import 'node_kinds.dart';
import 'type_checker.dart';

/// 节点编辑页（数据平面入口）。
///
/// 点击画布节点进入，配置该节点的参数与 `#` 引用、查看其动态命名输出
/// （控制流输出 + 数据输出），并在引用类型不匹配时提示。
///
/// 双平面模型：本页只处理"数据平面"（参数 + 引用 + 输出声明），
/// 不触碰控制流连线（连线由画布交互维护）。
class NodeEditorScreen extends ConsumerWidget {
  const NodeEditorScreen({
    super.key,
    required this.projectId,
    required this.functionId,
    required this.nodeId,
  });

  final String projectId;
  final String functionId;
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fn = ref.watch(graphMutatorProvider);
    final project = ref.watch(currentProjectProvider);
    final theme = Theme.of(context);

    Node? node;
    if (fn != null) {
      for (final n in fn.nodes) {
        if (n.id == nodeId) {
          node = n;
          break;
        }
      }
    }

    final spec = node == null ? null : NodeKindRegistry.getSpec(node.kind);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回画布',
          onPressed: () => context.go(
            AppConstants.functionEditorRoute(projectId, functionId),
          ),
        ),
        title: Text(
          spec?.displayName ?? node?.kind ?? '节点',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (spec != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _CategoryChip(category: spec.category),
              ),
            ),
        ],
      ),
      body: node == null
          ? _buildMissing(context, theme)
          : _NodeEditorBody(
              node: node,
              spec: spec,
              functionDef: fn!,
              project: project,
              nodeId: nodeId,
            ),
    );
  }

  Widget _buildMissing(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 48, color: theme.colorScheme.outline,),
            const SizedBox(height: 12),
            const Text('节点不存在或已被删除'),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => context.go(
                AppConstants.functionEditorRoute(projectId, functionId),
              ),
              child: const Text('返回画布'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeEditorBody extends ConsumerWidget {
  const _NodeEditorBody({
    required this.node,
    required this.spec,
    required this.functionDef,
    required this.project,
    required this.nodeId,
  });

  final Node node;
  final NodeKindSpec? spec;
  final FunctionDef functionDef;
  final Project? project;
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (spec == null) _buildUnsupportedNote(theme),
          if (spec != null) ...[
            _SectionTitle(title: '参数'),
            const SizedBox(height: 4),
            ...[
              for (final p in spec!.paramSchema)
                _buildParamField(context, ref, p),
            ],
            const SizedBox(height: 20),
          ],
          _SectionTitle(title: '控制流输出'),
          const SizedBox(height: 4),
          _ControlOutputsCard(outputs: node.controlOutputs),
          const SizedBox(height: 20),
          _SectionTitle(title: '数据输出'),
          const SizedBox(height: 4),
          _DataOutputsCard(outputs: node.dataOutputs),
        ],
      ),
    );
  }

  Widget _buildUnsupportedNote(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: theme.colorScheme.error,),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('此节点类型暂不支持参数编辑（仅展示输出）。'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 是否渲染某参数（loop 按 mode 仅显示相关字段）。
  bool _shouldRender(ParamSpec p) {
    if (spec?.kind == 'loop') {
      final mode = node.params['mode']?.toString() ?? 'count';
      if (p.name == 'count' && mode != 'count') return false;
      if (p.name == 'condition' && mode != 'condition') return false;
    }
    return true;
  }

  Widget _buildParamField(BuildContext context, WidgetRef ref, ParamSpec p) {
    if (!_shouldRender(p)) return const SizedBox.shrink();
    switch (p.inputType) {
      case ParamInputType.bool:
        return _BoolParamField(
          spec: p,
          value: node.params[p.name] == true,
          onChanged: (v) => _commitParam(ref, p.name, v),
        );
      case ParamInputType.dropdown:
        return _DropdownParamField(
          spec: p,
          value: node.params[p.name]?.toString() ?? '',
          functions: p.name == 'targetFunctionId' && spec?.kind == 'function_call'
              ? project?.functions ?? const []
              : const [],
          onChanged: (v) => _commitParam(ref, p.name, v),
        );
      case ParamInputType.listStrings:
        return _ListStringsParamField(
          spec: p,
          values: _stringListFrom(node.params[p.name]),
          onChanged: (list) => _commitParam(ref, p.name, list),
        );
      case ParamInputType.text:
      case ParamInputType.number:
        return _RefOrTextField(
          spec: p,
          rawValue: node.params[p.name],
          functionDef: functionDef,
          project: project,
          onChanged: (v) => _commitParam(ref, p.name, v),
          onClearRef: () => _commitParam(ref, p.name, null),
        );
    }
  }

  /// 提交参数变更，并在节点配置了 dynamicOutputs 时同步重新派生输出。
  ///
  /// 单次 [GraphMutator.updateNode] 提交，避免多次落盘的中间态。
  void _commitParam(WidgetRef ref, String name, Object? value) {
    final spec = this.spec;
    if (spec == null) return;
    final newParams = Map<String, dynamic>.from(node.params);
    newParams[name] = value;
    List<ControlOutput>? ctrl;
    List<DataOutput>? data;
    if (spec.dynamicOutputs != null) {
      final outs = spec.dynamicOutputs!(newParams);
      ctrl = outs.controlOutputs;
      data = outs.dataOutputs;
    }
    ref.read(graphMutatorProvider.notifier).updateNode(
          nodeId,
          params: newParams,
          controlOutputs: ctrl,
          dataOutputs: data,
        );
  }
}

// ---- 参数控件 ----

/// 文本 / 数值参数；当值为 `#` 引用（[VariableRef]）时切换为只读展示 +
/// 类型校验图标 + 清除按钮，否则可编辑文本 + # 按钮（v1 插入 "##" 占位）。
class _RefOrTextField extends StatelessWidget {
  const _RefOrTextField({
    required this.spec,
    required this.rawValue,
    required this.functionDef,
    required this.project,
    required this.onChanged,
    required this.onClearRef,
  });

  final ParamSpec spec;
  final Object? rawValue;
  final FunctionDef functionDef;
  final Project? project;
  final ValueChanged<String> onChanged;
  final VoidCallback onClearRef;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = _tryParseRef(rawValue);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(spec.label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600,),),
              const Spacer(),
              if (spec.acceptsRef && ref != null)
                _RefTypeBadge(
                  ref: ref,
                  expectedType: spec.expectedType ?? PortType.any,
                  functionDef: functionDef,
                  project: project,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (ref != null)
            _RefDisplay(ref: ref, onClear: onClearRef)
          else
            _SyncedTextField(
              value: _stringOf(rawValue),
              keyboardType: spec.inputType == ParamInputType.number
                  ? TextInputType.number
                  : TextInputType.text,
              acceptsRef: spec.acceptsRef,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

/// 自同步文本输入框（避免每次重建丢失光标）。
///
/// 仅在未聚焦时把外部 [value] 回填到控制器；编辑时由控制器主导。
/// # 按钮在末尾追加 "##" 占位（v1，Task 7 升级为卡片选择）。
class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    required this.value,
    required this.onChanged,
    this.keyboardType,
    this.acceptsRef = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool acceptsRef;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insertRef() {
    final next = '${_controller.text}##';
    _controller.text = next;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: next.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: widget.acceptsRef
            ? IconButton(
                tooltip: '插入引用占位 (#)',
                icon: const Icon(Icons.tag, size: 18),
                onPressed: _insertRef,
              )
            : null,
      ),
    );
  }
}

/// 已配置引用时的只读展示 + 清除按钮。
class _RefDisplay extends StatelessWidget {
  const _RefDisplay({required this.ref, required this.onClear});

  final VariableRef ref;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _refLabel(ref),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '清除引用',
            icon: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  static String _refLabel(VariableRef ref) {
    switch (ref.source) {
      case VariableSource.upstream:
        return '#${ref.nodeId}.${ref.outputName}';
      case VariableSource.funcVar:
        return '#func:${ref.varId}';
      case VariableSource.projVar:
        return '#proj:${ref.varId}';
    }
  }
}

/// 引用类型校验图标（✓ 匹配 / ⚠ 不匹配 + 提示）。
class _RefTypeBadge extends StatelessWidget {
  const _RefTypeBadge({
    required this.ref,
    required this.expectedType,
    required this.functionDef,
    required this.project,
  });

  final VariableRef ref;
  final PortType expectedType;
  final FunctionDef functionDef;
  final Project? project;

  @override
  Widget build(BuildContext context) {
    final result = checkRefType(ref, expectedType, functionDef, project);
    final ok = result.ok;
    final color = ok ? Colors.green : Theme.of(context).colorScheme.error;
    return Tooltip(
      message: ok ? '类型匹配' : result.reason,
      child: Icon(ok ? Icons.check_circle : Icons.warning_amber,
          size: 18, color: color,),
    );
  }
}

/// 布尔参数（Switch）。
class _BoolParamField extends StatelessWidget {
  const _BoolParamField({
    required this.spec,
    required this.value,
    required this.onChanged,
  });

  final ParamSpec spec;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(spec.label),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 下拉参数（function_call 的 targetFunctionId 由项目函数列表填充）。
class _DropdownParamField extends StatelessWidget {
  const _DropdownParamField({
    required this.spec,
    required this.value,
    required this.functions,
    required this.onChanged,
  });

  final ParamSpec spec;
  final String value;
  final List<FunctionDef> functions;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <DropdownMenuItem<String>>[];
    final useFunctions = functions.isNotEmpty;

    if (useFunctions) {
      for (final f in functions) {
        items.add(DropdownMenuItem(value: f.id, child: Text(f.name)));
      }
      // 若当前值不在候选中（函数已删除），追加占位项避免崩溃。
      if (value.isNotEmpty && !functions.any((f) => f.id == value)) {
        items.add(
          DropdownMenuItem(
            value: value,
            child: Text(
              '$value（已删除）',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        );
      }
    } else {
      for (final opt in spec.options ?? const <String>[]) {
        items.add(DropdownMenuItem(value: opt, child: Text(opt)));
      }
    }

    final hasValue = value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(spec.label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600,),),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: hasValue ? value : null,
            items: items,
            hint: const Text('选择…'),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

/// 字符串列表参数（if 的 cases）。
class _ListStringsParamField extends StatelessWidget {
  const _ListStringsParamField({
    required this.spec,
    required this.values,
    required this.onChanged,
  });

  final ParamSpec spec;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(spec.label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600,),),
              const Spacer(),
              Text(
                '${values.length} 项',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < values.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _SyncedTextField(
                      value: values[i],
                      onChanged: (text) {
                        final next = List<String>.from(values);
                        next[i] = text;
                        onChanged(next);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: '删除分支',
                    icon: Icon(Icons.remove_circle_outline,
                        size: 20, color: theme.colorScheme.error,),
                    onPressed: () {
                      final next = List<String>.from(values);
                      if (next.length > 1) {
                        next.removeAt(i);
                      } else {
                        next[i] = '';
                      }
                      onChanged(next);
                    },
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                onChanged([...values, 'case_${values.length + 1}']);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加分支'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 输出展示 ----

class _ControlOutputsCard extends StatelessWidget {
  const _ControlOutputsCard({required this.outputs});

  final List<ControlOutput> outputs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (outputs.isEmpty) {
      return _EmptyHint(text: '无控制流输出', theme: theme);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in outputs)
          Chip(
            avatar: Icon(Icons.call_split,
                size: 14, color: theme.colorScheme.tertiary,),
            label: Text(o.name),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _DataOutputsCard extends StatelessWidget {
  const _DataOutputsCard({required this.outputs});

  final List<DataOutput> outputs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (outputs.isEmpty) {
      return _EmptyHint(text: '无数据输出', theme: theme);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in outputs)
          Chip(
            avatar: Icon(Icons.data_object,
                size: 14, color: theme.colorScheme.primary,),
            label: Text('${o.name} : ${o.type.toJson()}'),
            labelStyle: const TextStyle(fontFamily: 'monospace'),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: theme.colorScheme.outline),
      ),
    );
  }
}

// ---- 通用小组件 ----

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final NodeCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label(category),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  static String _label(NodeCategory c) {
    switch (c) {
      case NodeCategory.variable:
        return '变量';
      case NodeCategory.operation:
        return '运算';
      case NodeCategory.flow:
        return '流程';
      case NodeCategory.database:
        return '数据库';
      case NodeCategory.function:
        return '函数';
      case NodeCategory.plugin:
        return '插件';
    }
  }
}

// ---- 工具函数 ----

/// 从原始值尝试解析为 [VariableRef]（节点参数中存储的引用 JSON）。
VariableRef? _tryParseRef(Object? v) {
  if (v is Map && v['source'] is String) {
    try {
      return VariableRef.fromJson(Map<String, dynamic>.from(v));
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// 把原始值转为文本展示字符串。
String _stringOf(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

/// 从原始值解析字符串列表（[ParamInputType.listStrings]）。
List<String> _stringListFrom(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList(growable: true);
  }
  return const ['true', 'false'];
}
