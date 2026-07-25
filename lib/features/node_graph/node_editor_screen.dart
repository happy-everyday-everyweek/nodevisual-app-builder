import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/models/func_param.dart';
import '../../data/models/function_def.dart';
import '../../data/models/node.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/project_variable.dart';
import '../../data/models/variable_ref.dart';
import '../plugins/plugin_config_sheet.dart';
import '../plugins/plugin_registry.dart';
import '../plugins/plugin_spec.dart';
import '../project/project_providers.dart';
import '../variables/scope_resolver.dart';
import '../variables/variable_picker_sheet.dart';
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
              functionId: functionId,
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
    required this.functionId,
    required this.nodeId,
  });

  final Node node;
  final NodeKindSpec? spec;
  final FunctionDef functionDef;
  final Project? project;
  final String functionId;
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
            // 插件配置入口（仅 plugin 类节点显示，最小侵入，不影响 # 引用）。
            if (spec!.pluginId != null) ...[
              _PluginConfigCard(pluginId: spec!.pluginId!),
              const SizedBox(height: 20),
            ],
            // 入参/出参节点：取代侧边栏签名编辑，直接在节点编辑页编辑函数签名。
            if (spec!.kind == 'function_input') ...[
              _SectionTitle(title: '入参签名'),
              const SizedBox(height: 4),
              _SignatureEditor(
                nodeId: nodeId,
                params: functionDef.inputs,
                isInputs: true,
              ),
              const SizedBox(height: 20),
            ] else if (spec!.kind == 'function_output') ...[
              _SectionTitle(title: '出参签名'),
              const SizedBox(height: 4),
              _SignatureEditor(
                nodeId: nodeId,
                params: functionDef.outputs,
                isInputs: false,
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: '返回值映射'),
              const SizedBox(height: 4),
              ...[
                for (final p in spec!.paramSchema)
                  _buildParamField(context, ref, p),
              ],
              const SizedBox(height: 20),
            ] else ...[
              _SectionTitle(title: '参数'),
              const SizedBox(height: 4),
              ...[
                for (final p in spec!.paramSchema)
                  _buildParamField(context, ref, p),
              ],
              // function_call 动态入参：按目标函数 inputs 签名生成参数字段。
              if (spec!.kind == 'function_call') ...[
                ..._buildFunctionCallInputFields(context, ref),
              ],
              const SizedBox(height: 20),
            ],
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
          // variable_set 的 varId：按 target 动态填充候选变量。
          // - target == 'funcVar'：当前函数的 funcVars（自然限定为本函数变量）
          // - target == 'projVar'：项目的 projectVars
          labelOptions:
              spec?.kind == 'variable_set' && p.name == 'varId'
                  ? _variableSetVarIdOptions()
                  : null,
          onChanged: (v) => _commitParam(ref, p.name, v),
        );
      case ParamInputType.listStrings:
        return _ListStringsParamField(
          spec: p,
          values: _stringListFrom(node.params[p.name]),
          onChanged: (list) => _commitParam(ref, p.name, list),
        );
      case ParamInputType.keyValueMap:
        return _KeyValueMapParamField(
          spec: p,
          rawMap: node.params[p.name],
          functionDef: functionDef,
          project: project,
          functionId: functionId,
          nodeId: nodeId,
          // function_output 节点的 values 字段：键建议来自函数 outputs 名。
          suggestedKeys: spec?.kind == 'function_output'
              ? functionDef.outputs.map((o) => o.name).toList(growable: false)
              : const [],
          onChanged: (m) => _commitParam(ref, p.name, m),
        );
      case ParamInputType.text:
      case ParamInputType.number:
        return _RefOrTextField(
          spec: p,
          rawValue: node.params[p.name],
          functionDef: functionDef,
          project: project,
          functionId: functionId,
          nodeId: nodeId,
          onChanged: (v) => _commitParam(ref, p.name, v),
          onSetRef: (r) => _commitParam(ref, p.name, r.toJson()),
          onClearRef: () => _commitParam(ref, p.name, null),
        );
    }
  }

  /// 为 variable_set 节点的 varId 参数构造候选变量列表。
  ///
  /// 按 node.params['target'] 决定来源：
  /// - 'funcVar'（默认）：当前函数的 funcVars（id → "名称 : 类型"）。
  ///   自然限定为本函数变量（节点所在函数），符合"设置变量节点设置的函数变量
  ///   只能设置节点所在函数的变量"的语义。
  /// - 'projVar'：项目的 projectVars（id → "名称 : 类型"）。
  List<({String value, String label})> _variableSetVarIdOptions() {
    final target = node.params['target']?.toString() ?? 'funcVar';
    if (target == 'projVar') {
      final vars = project?.projectVars ?? const <ProjectVariable>[];
      return [
        for (final v in vars)
          (value: v.id, label: '${v.name} : ${v.type.toJson()}'),
      ];
    }
    // funcVar：仅当前函数的变量。
    return [
      for (final v in functionDef.funcVars)
        (value: v.id, label: '${v.name} : ${v.type.toJson()}'),
    ];
  }

  /// function_call 动态入参字段：按目标函数 [FunctionDef.inputs] 生成。
  ///
  /// 每个入参渲染为一个 `_RefOrTextField`，参数键名为入参名（与执行器
  /// `_execFunctionCall` 的 `params.entries` 透传逻辑对齐）。
  /// 目标函数无签名或未选择时返回空列表。
  List<Widget> _buildFunctionCallInputFields(
    BuildContext context,
    WidgetRef ref,
  ) {
    final project = this.project;
    if (project == null) return const [];
    final targetId = node.params['targetFunctionId']?.toString() ?? '';
    if (targetId.isEmpty) return const [];
    FunctionDef? target;
    for (final f in project.functions) {
      if (f.id == targetId) {
        target = f;
        break;
      }
    }
    if (target == null || target.inputs.isEmpty) return const [];
    return [
      for (final input in target.inputs)
        _RefOrTextField(
          spec: ParamSpec(
            name: input.name,
            label: '${input.name}${input.description != null && input.description!.isNotEmpty ? ' — ${input.description}' : ''}',
            inputType: ParamInputType.text,
            acceptsRef: true,
            expectedType: input.type,
            defaultValue: input.defaultValue,
          ),
          rawValue: node.params[input.name],
          functionDef: functionDef,
          project: project,
          functionId: functionId,
          nodeId: nodeId,
          onChanged: (v) => _commitParam(ref, input.name, v),
          onSetRef: (r) => _commitParam(ref, input.name, r.toJson()),
          onClearRef: () => _commitParam(ref, input.name, null),
        ),
    ];
  }

  /// 提交参数变更，并在节点配置了 dynamicOutputs / projectOutputs 时同步
  /// 重新派生输出。
  ///
  /// 单次 [GraphMutator.updateNode] 提交，避免多次落盘的中间态。
  /// 多输出母节点（如 if 的 cases / includeDefault）参数变更后同步增删
  /// branch 子节点（通用子母节点设计）。
  void _commitParam(WidgetRef ref, String name, Object? value) {
    final spec = this.spec;
    if (spec == null) return;
    final newParams = Map<String, dynamic>.from(node.params);
    newParams[name] = value;
    List<ControlOutput>? ctrl;
    List<DataOutput>? data;
    // projectOutputs（function_call）优先：按目标函数签名动态生成命名数据输出。
    if (spec.projectOutputs != null) {
      final fns = project?.functions ?? const <FunctionDef>[];
      final outs = spec.projectOutputs!(newParams, fns);
      ctrl = outs.controlOutputs;
      data = outs.dataOutputs;
    } else if (spec.dynamicOutputs != null) {
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
    // 多输出母节点的参数变更可能影响控制流输出端口 → 同步 branch 子节点。
    // 仅对 dynamicOutputs 节点（如 if）有效；静态输出节点（如 loop）幂等无操作。
    if (spec.dynamicOutputs != null) {
      ref.read(graphMutatorProvider.notifier).syncBranches(nodeId);
    }
  }
}

// ---- 参数控件 ----

/// 文本 / 数值参数；当值为 `#` 引用（[VariableRef]）时切换为只读展示 +
/// 类型校验图标 + 清除 / 重新选择按钮，否则可编辑文本 + # 按钮。
///
/// **# 交互（Task 7）**：
/// - 点击 # 按钮 → 弹出 [VariablePickerSheet] 卡片选择变量；
/// - 在输入框输入 `#` → 防抖后弹出卡片；
/// - 输入 `#名称` → 防抖后调用 [ScopeResolver.matchByName]：唯一命中直建引用，
///   不唯一 / 未命中则弹出卡片（预填搜索词）；
/// - 引用态下显示引用目标 + 清除（改回字面值）/ 重新选择按钮；
/// - 类型不匹配时在参数下方显示 ⚠ 提示（用 [checkRefType]）。
class _RefOrTextField extends StatefulWidget {
  const _RefOrTextField({
    required this.spec,
    required this.rawValue,
    required this.functionDef,
    required this.project,
    required this.functionId,
    required this.nodeId,
    required this.onChanged,
    required this.onSetRef,
    required this.onClearRef,
  });

  final ParamSpec spec;
  final Object? rawValue;
  final FunctionDef functionDef;
  final Project? project;
  final String functionId;
  final String nodeId;

  /// 字面值文本变更（逐字符提交）。
  final ValueChanged<String> onChanged;

  /// 选中变量引用后提交（参数值存为 [VariableRef] 的 JSON）。
  final ValueChanged<VariableRef> onSetRef;

  /// 清除引用、改回字面值（参数值置 null）。
  final VoidCallback onClearRef;

  @override
  State<_RefOrTextField> createState() => _RefOrTextFieldState();
}

class _RefOrTextFieldState extends State<_RefOrTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  Timer? _debounce;

  /// 卡片是否已弹出（防止重复弹出 / 编辑期重复触发）。
  bool _picking = false;

  /// 卡片由 `#` 输入触发时，取消需清回字面值；由 # 按钮触发时不清空。
  bool _clearOnCancel = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _stringOf(widget.rawValue));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _RefOrTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在非聚焦（非编辑态）时回填外部值，避免编辑时光标跳动。
    if (!_focus.hasFocus) {
      final external = _stringOf(widget.rawValue);
      if (_controller.text != external) {
        _controller.text = external;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  VariableRef? get _ref => _tryParseRef(widget.rawValue);

  PortType get _expectedType => widget.spec.expectedType ?? PortType.any;

  void _onTextChanged(String text) {
    widget.onChanged(text);
    if (_picking) return;
    _debounce?.cancel();
    if (!text.startsWith('#')) {
      _clearOnCancel = false;
      return;
    }
    _clearOnCancel = true;
    final name = text.substring(1);
    if (name.isEmpty) {
      // 仅有 '#'，稍后弹卡片。
      _debounce = Timer(const Duration(milliseconds: 200), () {
        _openSheet();
      });
    } else {
      // '#名称' 快速匹配。
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _tryQuickRef(name);
      });
    }
  }

  /// `#名称` 快速引用：唯一命中直建引用，否则弹卡片（预填搜索词）。
  void _tryQuickRef(String name) {
    if (!mounted || _picking) return;
    final refs = ScopeResolver.matchByName(
      widget.functionDef,
      widget.project,
      widget.nodeId,
      name,
    );
    if (refs.length == 1) {
      widget.onSetRef(refs.first);
    } else {
      _openSheet(initialQuery: name);
    }
  }

  Future<void> _openSheet({String? initialQuery}) async {
    if (_picking) return;
    _picking = true;
    _debounce?.cancel();
    final clearOnCancel = _clearOnCancel;
    _clearOnCancel = false;
    final selected = await VariablePickerSheet.show(
      context,
      functionId: widget.functionId,
      nodeId: widget.nodeId,
      expectedType: widget.spec.expectedType,
      initialQuery: initialQuery,
    );
    _picking = false;
    if (!mounted) return;
    if (selected != null) {
      widget.onSetRef(selected.ref);
    } else if (clearOnCancel) {
      // 取消 `#` 触发：清回字面值。
      _controller.text = '';
      widget.onChanged('');
    }
  }

  void _onRefButton() {
    // # 按钮：直接弹卡片；取消不清空已有字面值。
    _clearOnCancel = false;
    _openSheet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = _ref;
    final typeResult = ref == null
        ? null
        : checkRefType(ref, _expectedType, widget.functionDef, widget.project);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(widget.spec.label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600,),),
              const Spacer(),
              if (widget.spec.acceptsRef && ref != null)
                _RefTypeBadge(
                  ref: ref,
                  expectedType: _expectedType,
                  functionDef: widget.functionDef,
                  project: widget.project,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (ref != null)
            _RefDisplay(
              ref: ref,
              functionDef: widget.functionDef,
              project: widget.project,
              onClear: widget.onClearRef,
              onReselect: _onRefButton,
            )
          else
            _buildTextField(),
          if (ref != null && typeResult != null && !typeResult.ok)
            _TypeMismatchHint(reason: typeResult.reason, theme: theme),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: widget.spec.inputType == ParamInputType.number
          ? TextInputType.number
          : TextInputType.text,
      onChanged: _onTextChanged,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: widget.spec.acceptsRef
            ? IconButton(
                tooltip: '插入变量引用 (#)',
                icon: const Icon(Icons.tag, size: 18),
                onPressed: _onRefButton,
              )
            : null,
      ),
    );
  }
}

/// 自同步文本输入框（避免每次重建丢失光标）。
///
/// 仅在未聚焦时把外部 [value] 回填到控制器；编辑时由控制器主导。
/// 用于字符串列表参数（[ParamInputType.listStrings]）的逐项编辑。
class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

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

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: widget.onChanged,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// 已配置引用时的只读展示 + 重新选择 / 清除按钮。
class _RefDisplay extends StatelessWidget {
  const _RefDisplay({
    required this.ref,
    required this.functionDef,
    required this.project,
    required this.onClear,
    required this.onReselect,
  });

  final VariableRef ref;
  final FunctionDef functionDef;
  final Project? project;
  final VoidCallback onClear;

  /// 重新打开变量选择卡片（保留引用态切换）。
  final VoidCallback onReselect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              _refDisplayLabel(ref, functionDef, project),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '重新选择',
            icon: Icon(Icons.refresh, size: 16, color: theme.colorScheme.primary),
            onPressed: onReselect,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: '清除引用 / 改回字面值',
            icon: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// 引用类型不匹配时参数下方的 ⚠ 提示行。
class _TypeMismatchHint extends StatelessWidget {
  const _TypeMismatchHint({required this.reason, required this.theme});

  final String reason;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber,
              size: 14, color: theme.colorScheme.error),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              reason,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
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

/// 下拉参数（function_call 的 targetFunctionId 由项目函数列表填充；
/// variable_set 的 varId 由 labelOptions 动态填充）。
class _DropdownParamField extends StatelessWidget {
  const _DropdownParamField({
    required this.spec,
    required this.value,
    required this.functions,
    required this.onChanged,
    this.labelOptions,
  });

  final ParamSpec spec;
  final String value;
  final List<FunctionDef> functions;
  final ValueChanged<String> onChanged;

  /// 动态候选选项（value → label），优先于 [functions] 与 [spec.options]。
  ///
  /// 用于 variable_set 的 varId：按 target 来源动态填充候选变量。
  final List<({String value, String label})>? labelOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <DropdownMenuItem<String>>[];
    final useFunctions = functions.isNotEmpty;
    final useLabelOptions = labelOptions != null && labelOptions!.isNotEmpty;

    if (useLabelOptions) {
      for (final opt in labelOptions!) {
        items.add(DropdownMenuItem(value: opt.value, child: Text(opt.label)));
      }
      // 若当前值不在候选中（变量已删除 / target 切换后旧 varId 失效），
      // 追加占位项避免崩溃。
      if (value.isNotEmpty &&
          !labelOptions!.any((o) => o.value == value)) {
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
    } else if (useFunctions) {
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
            hint: Text(useLabelOptions && items.isEmpty
                ? '无可用变量'
                : '选择…'),
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

/// Map 键值对参数（return 的多返回值映射 / db_insert 的 data / ui_navigate 的 params）。
///
/// 每行：键（text） + 值（`#` 引用或字面值）。值单元格复用 `_RefOrTextField`
/// 的内部逻辑，但为简化实现，这里用一个简化的 `_KeyValueRow` 行控件：
/// 键与值分开编辑，值支持 `#` 引用。
class _KeyValueMapParamField extends StatelessWidget {
  const _KeyValueMapParamField({
    required this.spec,
    required this.rawMap,
    required this.functionDef,
    required this.project,
    required this.functionId,
    required this.nodeId,
    required this.suggestedKeys,
    required this.onChanged,
  });

  final ParamSpec spec;
  final Object? rawMap;
  final FunctionDef functionDef;
  final Project? project;
  final String functionId;
  final String nodeId;
  final List<String> suggestedKeys;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final map = _mapFrom(rawMap);
    final keys = map.keys.toList();
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
                '${map.length} 项',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < keys.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _KeyValueRow(
                keyText: keys[i],
                valueRaw: map[keys[i]],
                functionDef: functionDef,
                project: project,
                functionId: functionId,
                nodeId: nodeId,
                expectedType: spec.expectedType ?? PortType.any,
                suggestedKeys: suggestedKeys,
                onKeyChanged: (newKey) {
                  if (newKey.isEmpty || map.containsKey(newKey)) return;
                  final next = Map<String, dynamic>.from(map);
                  final v = next.remove(keys[i]);
                  next[newKey] = v;
                  onChanged(next);
                },
                onValueChanged: (v) {
                  final next = Map<String, dynamic>.from(map);
                  next[keys[i]] = v;
                  onChanged(next);
                },
                onSetRef: (r) {
                  final next = Map<String, dynamic>.from(map);
                  next[keys[i]] = r.toJson();
                  onChanged(next);
                },
                onClearRef: () {
                  final next = Map<String, dynamic>.from(map);
                  next[keys[i]] = null;
                  onChanged(next);
                },
                onRemove: () {
                  final next = Map<String, dynamic>.from(map);
                  next.remove(keys[i]);
                  onChanged(next);
                },
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                // 若有建议键且未全部使用，自动用下一个建议键；否则用默认键名。
                final unused = suggestedKeys
                    .where((k) => !map.containsKey(k))
                    .toList(growable: false);
                final newKey = unused.isNotEmpty
                    ? unused.first
                    : 'key_${map.length + 1}';
                onChanged({...map, newKey: null});
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加项'),
            ),
          ),
        ],
      ),
    );
  }

  /// 从原始值解析为 Map<String, dynamic>。
  Map<String, dynamic> _mapFrom(Object? v) {
    if (v is Map) {
      return Map<String, dynamic>.from(v);
    }
    return <String, dynamic>{};
  }
}

/// 键值对的单行：键输入 + 值输入（支持 # 引用）。
class _KeyValueRow extends StatefulWidget {
  const _KeyValueRow({
    required this.keyText,
    required this.valueRaw,
    required this.functionDef,
    required this.project,
    required this.functionId,
    required this.nodeId,
    required this.expectedType,
    required this.suggestedKeys,
    required this.onKeyChanged,
    required this.onValueChanged,
    required this.onSetRef,
    required this.onClearRef,
    required this.onRemove,
  });

  final String keyText;
  final Object? valueRaw;
  final FunctionDef functionDef;
  final Project? project;
  final String functionId;
  final String nodeId;
  final PortType expectedType;
  final List<String> suggestedKeys;
  final ValueChanged<String> onKeyChanged;
  final ValueChanged<String> onValueChanged;
  final ValueChanged<VariableRef> onSetRef;
  final VoidCallback onClearRef;
  final VoidCallback onRemove;

  @override
  State<_KeyValueRow> createState() => _KeyValueRowState();
}

class _KeyValueRowState extends State<_KeyValueRow> {
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;
  late final FocusNode _valueFocus;
  Timer? _debounce;
  bool _picking = false;
  bool _clearOnCancel = false;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.keyText);
    _valueController = TextEditingController(text: _stringOf(widget.valueRaw));
    _valueFocus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _KeyValueRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_keyController.text != widget.keyText) {
      _keyController.text = widget.keyText;
    }
    if (!_valueFocus.hasFocus) {
      final ext = _stringOf(widget.valueRaw);
      if (_valueController.text != ext) {
        _valueController.text = ext;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _keyController.dispose();
    _valueController.dispose();
    _valueFocus.dispose();
    super.dispose();
  }

  VariableRef? get _ref => _tryParseRef(widget.valueRaw);

  void _onValueChanged(String text) {
    widget.onValueChanged(text);
    if (_picking) return;
    _debounce?.cancel();
    if (!text.startsWith('#')) {
      _clearOnCancel = false;
      return;
    }
    _clearOnCancel = true;
    final name = text.substring(1);
    if (name.isEmpty) {
      _debounce = Timer(const Duration(milliseconds: 200), _openSheet);
    } else {
      _debounce = Timer(const Duration(milliseconds: 300), () => _tryQuickRef(name));
    }
  }

  void _tryQuickRef(String name) {
    if (!mounted || _picking) return;
    final refs = ScopeResolver.matchByName(
      widget.functionDef,
      widget.project,
      widget.nodeId,
      name,
    );
    if (refs.length == 1) {
      widget.onSetRef(refs.first);
    } else {
      _openSheet(initialQuery: name);
    }
  }

  Future<void> _openSheet({String? initialQuery}) async {
    if (_picking) return;
    _picking = true;
    _debounce?.cancel();
    final clearOnCancel = _clearOnCancel;
    _clearOnCancel = false;
    final selected = await VariablePickerSheet.show(
      context,
      functionId: widget.functionId,
      nodeId: widget.nodeId,
      expectedType: widget.expectedType,
      initialQuery: initialQuery,
    );
    _picking = false;
    if (!mounted) return;
    if (selected != null) {
      widget.onSetRef(selected.ref);
    } else if (clearOnCancel) {
      _valueController.text = '';
      widget.onValueChanged('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = _ref;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: TextField(
            controller: _keyController,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '键',
            ),
            onChanged: widget.onKeyChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ref != null
              ? _RefDisplay(
                  ref: ref,
                  functionDef: widget.functionDef,
                  project: widget.project,
                  onClear: widget.onClearRef,
                  onReselect: _openSheet,
                )
              : TextField(
                  controller: _valueController,
                  focusNode: _valueFocus,
                  onChanged: _onValueChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: '值',
                    suffixIcon: IconButton(
                      tooltip: '插入变量引用 (#)',
                      icon: const Icon(Icons.tag, size: 18),
                      onPressed: () {
                        _clearOnCancel = false;
                        _openSheet();
                      },
                    ),
                  ),
                ),
        ),
        IconButton(
          tooltip: '删除项',
          icon: Icon(Icons.remove_circle_outline,
              size: 20, color: theme.colorScheme.error,),
          onPressed: widget.onRemove,
          visualDensity: VisualDensity.compact,
        ),
      ],
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

/// 插件配置入口卡片（仅 plugin 类节点显示）。
///
/// 展示关联插件的 displayName 与配置状态（必填 secret 字段是否已配置），
/// 点击"配置"按钮打开 [PluginConfigSheet]。**不影响参数区的 # 引用交互**。
class _PluginConfigCard extends ConsumerStatefulWidget {
  const _PluginConfigCard({required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<_PluginConfigCard> createState() => _PluginConfigCardState();
}

class _PluginConfigCardState extends ConsumerState<_PluginConfigCard> {
  bool _loading = true;
  bool _requiredReady = false;
  int _fieldCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  /// 读取配置并计算必填字段是否已就绪（用于状态提示）。
  Future<void> _refreshStatus() async {
    final storage = ref.read(pluginConfigStorageProvider);
    final registry = ref.read(pluginRegistryProvider);
    final entry = registry.get(widget.pluginId);
    final config = await storage.getPluginConfig(widget.pluginId);
    if (!mounted) return;
    bool ready = true;
    final fields = entry?.spec.configSchema ?? const <ConfigField>[];
    for (final f in fields) {
      if (f.required) {
        final v = config[f.key];
        if (v == null || v.toString().trim().isEmpty) {
          ready = false;
          break;
        }
      }
    }
    setState(() {
      _loading = false;
      _requiredReady = ready;
      _fieldCount = fields.length;
    });
  }

  Future<void> _openSheet() async {
    final saved = await PluginConfigSheet.show(context, pluginId: widget.pluginId);
    if (saved == true && mounted) {
      // 保存后刷新状态。
      setState(() => _loading = true);
      _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = ref.watch(pluginRegistryProvider).get(widget.pluginId);
    final spec = entry?.spec;
    if (spec == null) {
      return const SizedBox.shrink();
    }
    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.extension, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${spec.displayName} 配置',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusText(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _loading
                          ? theme.colorScheme.outline
                          : (_requiredReady
                              ? Colors.green
                              : theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _openSheet,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('配置'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText() {
    if (_loading) return '加载中…';
    if (_fieldCount == 0) return '无配置项';
    return _requiredReady ? '已配置' : '必填项未配置';
  }
}

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
        displayGroupLabel(displayGroupOf(category)),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
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

/// 生成引用的可读展示文本（尽量用名称而非 id）。
///
/// - upstream：`#节点展示名.输出名`（节点展示名取自 [NodeKindRegistry]，
///   未注册回退 kind；找不到节点 / 输出时回退 `#nodeId.outputName`）；
/// - funcVar：`#变量名`（找不到回退 `#func:varId`）；
/// - projVar：`#变量名`（找不到回退 `#proj:varId`）；
/// - component：`#组件展示名.字段名`（找不到回退 `#component:componentId.fieldName`）；
/// - device：`#设备 › 属性展示名`（属性展示名取自 [DeviceProperty.labelOf]）。
String _refDisplayLabel(VariableRef ref, FunctionDef fn, Project? project) {
  switch (ref.source) {
    case VariableSource.upstream:
      final nodeId = ref.nodeId;
      final outputName = ref.outputName;
      if (nodeId == null || outputName == null) {
        return '#<无效引用>';
      }
      for (final node in fn.nodes) {
        if (node.id != nodeId) continue;
        final spec = NodeKindRegistry.getSpec(node.kind);
        final label = spec?.displayName ?? node.kind;
        return '#$label.$outputName';
      }
      return '#$nodeId.$outputName';
    case VariableSource.funcVar:
      // 页面级函数 outputs：`#函数展示名.输出名`（找不到回退 `#pageFunc:funcId.outputName`）。
      if (ref.isPageFunc) {
        final funcId = ref.funcId!;
        final outputName = ref.outputName!;
        if (project != null) {
          for (final f in project.functions) {
            if (f.id == funcId) return '#${f.name}.$outputName';
          }
        }
        return '#pageFunc:$funcId.$outputName';
      }
      final varId = ref.varId;
      if (varId == null) return '#<无效引用>';
      for (final v in fn.funcVars) {
        if (v.id == varId) return '#${v.name}';
      }
      return '#func:$varId';
    case VariableSource.projVar:
      final varId = ref.varId;
      if (varId == null) return '#<无效引用>';
      if (project != null) {
        for (final v in project.projectVars) {
          if (v.id == varId) return '#${v.name}';
        }
      }
      return '#proj:$varId';
    case VariableSource.component:
      final componentId = ref.componentId;
      final fieldName = ref.fieldName;
      if (componentId == null || fieldName == null) {
        return '#<无效引用>';
      }
      return '#component:$componentId.$fieldName';
    case VariableSource.device:
      final property = ref.property;
      if (property == null) return '#<无效引用>';
      return '#设备 › ${DeviceProperty.labelOf(property)}';
  }
}

/// 从原始值解析字符串列表（[ParamInputType.listStrings]）。
List<String> _stringListFrom(Object? v) {
  if (v is List) {
    return v.map((e) => e.toString()).toList(growable: true);
  }
  return const ['true', 'false'];
}

/// 函数签名编辑器（入参/出参节点专用，取代侧边栏签名编辑）。
///
/// 渲染 [FuncParam] 列表，每行可编辑名称 / 类型 / 默认值（仅入参） / 描述 / 删除，
/// 底部"添加"按钮追加新参数。每次变更通过 [GraphMutator.syncFunctionSignature]
/// 同步到 [FunctionDef.inputs]/[outputs]，并刷新 function_input 节点的 dataOutputs。
class _SignatureEditor extends ConsumerStatefulWidget {
  const _SignatureEditor({
    required this.nodeId,
    required this.params,
    required this.isInputs,
  });

  /// IO 节点 id（用于 syncFunctionSignature 定位节点）。
  final String nodeId;

  /// 初始签名（来自 FunctionDef.inputs 或 outputs）。
  final List<FuncParam> params;

  /// true = 入参签名，false = 出参签名。
  final bool isInputs;

  @override
  ConsumerState<_SignatureEditor> createState() => _SignatureEditorState();
}

class _SignatureEditorState extends ConsumerState<_SignatureEditor> {
  late List<FuncParam> _params;

  @override
  void initState() {
    super.initState();
    _params = List<FuncParam>.from(widget.params);
  }

  void _commit() {
    ref.read(graphMutatorProvider.notifier).syncFunctionSignature(
          widget.nodeId,
          widget.isInputs,
          _params,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _params.length; i++)
          _FuncParamEditRow(
            param: _params[i],
            isOutput: !widget.isInputs,
            onChanged: (p) => setState(() {
              _params[i] = p;
              _commit();
            }),
            onRemove: () => setState(() {
              _params.removeAt(i);
              _commit();
            }),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(widget.isInputs ? '添加入参' : '添加出参'),
            onPressed: () => setState(() {
              _params.add(FuncParam(
                name: widget.isInputs
                    ? 'arg${_params.length + 1}'
                    : 'out${_params.length + 1}',
                type: PortType.any,
              ));
              _commit();
            }),
          ),
        ),
        if (_params.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              widget.isInputs ? '此函数无入参' : '此函数无出参',
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

/// 单个 FuncParam 编辑行（名称 / 类型 / 默认值 / 描述 / 删除）。
class _FuncParamEditRow extends StatelessWidget {
  const _FuncParamEditRow({
    required this.param,
    required this.isOutput,
    required this.onChanged,
    required this.onRemove,
  });

  final FuncParam param;
  final bool isOutput;
  final ValueChanged<FuncParam> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: TextEditingController(text: param.name),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '参数名',
                  ),
                  onChanged: (v) => onChanged(param.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<PortType>(
                  value: param.type,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '类型',
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: PortType.any, child: Text('any')),
                    DropdownMenuItem(
                        value: PortType.string, child: Text('string')),
                    DropdownMenuItem(
                        value: PortType.number, child: Text('number')),
                    DropdownMenuItem(
                        value: PortType.boolean, child: Text('boolean')),
                    DropdownMenuItem(
                        value: PortType.list, child: Text('list')),
                    DropdownMenuItem(
                        value: PortType.map, child: Text('map')),
                  ],
                  onChanged: (v) {
                    if (v != null) onChanged(param.copyWith(type: v));
                  },
                ),
              ),
              IconButton(
                tooltip: '删除',
                icon: Icon(Icons.remove_circle_outline,
                    size: 20, color: theme.colorScheme.error),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!isOutput)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextField(
                controller:
                    TextEditingController(text: _defaultText(param.defaultValue)),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '默认值（字面值；可空）',
                ),
                onChanged: (v) {
                  final parsed = _parseDefault(v);
                  onChanged(param.copyWith(defaultValue: parsed));
                },
              ),
            ),
          TextField(
            controller: TextEditingController(text: param.description ?? ''),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '描述（可选）',
            ),
            onChanged: (v) => onChanged(param.copyWith(description: v)),
          ),
        ],
      ),
    );
  }

  static String _defaultText(Object? v) {
    if (v == null) return '';
    return v.toString();
  }

  /// 简单解析默认值字面值字符串。
  ///
  /// - 空字符串 → null
  /// - "true"/"false" → bool
  /// - 数字 → num (int/double)
  /// - 其他 → 字符串原值
  static Object? _parseDefault(String v) {
    if (v.isEmpty) return null;
    if (v == 'true') return true;
    if (v == 'false') return false;
    final num? parsed = num.tryParse(v);
    if (parsed != null) return parsed;
    return v;
  }
}
