import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/function_def.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/ui_tree.dart';
import '../../data/models/variable_ref.dart';
import '../functions/function_providers.dart';
import '../node_graph/type_checker.dart';
import '../project/project_providers.dart';
import 'scope_resolver.dart';

/// 变量选择结果（含可选加载态策略）。
///
/// 仅当 [ref] 指向页面级函数 outputs（含时间线）或组件上下文变量时，
/// [loadingStrategy] / [placeholderText] 才有意义；其余来源仅用 [ref]。
class VariablePickResult {
  final VariableRef ref;
  final LoadingStrategy loadingStrategy;
  final String? placeholderText;

  const VariablePickResult({
    required this.ref,
    this.loadingStrategy = LoadingStrategy.typeDefault,
    this.placeholderText,
  });

  /// 转为 [Binding]（UI 属性侧存储形式）。
  Binding toBinding() => Binding(
        ref: ref,
        loadingStrategy: loadingStrategy,
        placeholderText: placeholderText,
      );
}

/// 变量选择卡片（底部 BottomSheet）。
///
/// 在节点编辑页参数或 UI 属性触发 `#` 时弹出，按**四源**（控制流上游节点输出 /
/// 函数变量 / 项目变量 / 组件上下文变量）分组展示可选变量，支持搜索过滤、
/// 类型提示与跨来源同名冲突标注。选中后返回 [VariableRef]。
///
/// **UI 侧 vs 节点侧**：
/// - 节点参数侧（[nodeId] 非空）：解析控制流上游作用域；通常不传
///   [componentVars] / [pageFuncOutputs]（函数图无组件树/页面上下文）。
/// - UI 属性侧（[nodeId] 为空）：传入 [componentVars]（当前组件所在容器链
///   暴露的字段）与 [pageFuncOutputs]（当前页面绑定的 onLoad 等函数 outputs）。
///
/// Material 3，移动端友好：高度初始 60% 屏幕，可拖拽至近全屏。
class VariablePickerSheet extends ConsumerStatefulWidget {
  const VariablePickerSheet({
    super.key,
    required this.functionId,
    this.nodeId = '',
    this.expectedType,
    this.initialQuery = '',
    this.componentVars = const [],
    this.pageFuncOutputs = const [],
  });

  final String functionId;

  /// 触发 `#` 的当前节点 id（用于解析控制流上游作用域）。
  ///
  /// 为空时跳过上游解析（UI 属性侧调用）。
  final String nodeId;

  /// 期望类型（用于类型提示与不匹配项灰显 / ⚠ 标注）。null 视为不约束。
  final PortType? expectedType;

  /// 初始搜索词（由 `#名称` 快速引用未唯一命中时预填）。
  final String initialQuery;

  /// 当前组件所在容器链暴露的组件上下文字段（仅 UI 侧传入）。
  final List<ComponentContextVar> componentVars;

  /// 当前页面绑定的页面级函数 outputs（仅 UI 侧传入，含时间线）。
  final List<PageFuncOutputOption> pageFuncOutputs;

  /// 以底部 BottomSheet 形式弹出卡片；返回用户选中的 [VariablePickResult]，
  /// 用户取消（下拉关闭 / 返回）时返回 null。
  static Future<VariablePickResult?> show(
    BuildContext context, {
    required String functionId,
    String nodeId = '',
    PortType? expectedType,
    String? initialQuery,
    List<ComponentContextVar> componentVars = const [],
    List<PageFuncOutputOption> pageFuncOutputs = const [],
  }) {
    return showModalBottomSheet<VariablePickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VariablePickerSheet(
        functionId: functionId,
        nodeId: nodeId,
        expectedType: expectedType,
        initialQuery: initialQuery ?? '',
        componentVars: componentVars,
        pageFuncOutputs: pageFuncOutputs,
      ),
    );
  }

  @override
  ConsumerState<VariablePickerSheet> createState() =>
      _VariablePickerSheetState();
}

class _VariablePickerSheetState extends ConsumerState<VariablePickerSheet> {
  late final TextEditingController _search;
  String _query = '';

  /// 待确认的引用（需要加载态策略配置时暂存）。
  ///
  /// 仅当选择含时间线的引用（页面级函数 outputs）或组件上下文变量时，
  /// 暂存该项并展开加载态策略配置面板；其余来源直接返回。
  _PendingPick? _pending;
  LoadingStrategy _strategy = LoadingStrategy.typeDefault;
  final TextEditingController _placeholderCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery.trim().toLowerCase();
  }

  @override
  void dispose() {
    _search.dispose();
    _placeholderCtrl.dispose();
    super.dispose();
  }

  /// 引用是否需要加载态策略配置（含时间线 / 容器渲染时机未定）。
  bool _needsStrategy(VariableRef ref) =>
      ref.isPageFunc || ref.source == VariableSource.component;

  void _onItemTapped(BuildContext context, _PickerItem item) {
    if (!_needsStrategy(item.ref)) {
      Navigator.of(context).pop(VariablePickResult(ref: item.ref));
      return;
    }
    setState(() {
      _pending = _PendingPick(item: item);
      _strategy = LoadingStrategy.typeDefault;
      _placeholderCtrl.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final fn =
        project == null ? null : findFunction(project, widget.functionId);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHandle(theme),
              _buildHeader(theme),
              _buildSearch(theme),
              const Divider(height: 1),
              Expanded(
                child: fn == null
                    ? _buildMissing(theme)
                    : _buildList(context, theme, fn, project, scrollController),
              ),
              if (_pending != null)
                _buildStrategyPanel(context, theme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final expected = widget.expectedType;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          Icon(Icons.tag, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '选择变量',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (expected != null && expected != PortType.any)
            _TypeChip(
              type: expected,
              theme: theme,
              hint: '期望',
            ),
        ],
      ),
    );
  }

  Widget _buildSearch(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _search,
        autofocus: widget.initialQuery.isEmpty,
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() {
          _query = v.trim().toLowerCase();
        }),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: '搜索变量名…',
          border: const OutlineInputBorder(),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildMissing(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            const Text('函数不存在或未打开项目'),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    ThemeData theme,
    FunctionDef fn,
    Project? project,
    ScrollController scrollController,
  ) {
    final items = _buildItems(fn, project);
    final filtered =
        _query.isEmpty ? items : items.where(_matches).toList(growable: false);

    if (items.isEmpty) {
      return _buildEmpty(theme, '暂无可选变量');
    }
    if (filtered.isEmpty) {
      return _buildEmpty(theme, '无匹配项');
    }

    // 按分组顺序渲染：上游 → 函数变量 → 项目变量 → 组件上下文。
    final children = <Widget>[];
    for (final group in _Group.values) {
      final groupItems = filtered.where((it) => it.group == group).toList();
      if (groupItems.isEmpty) continue;
      children.add(_GroupHeader(label: _groupLabel(group), theme: theme));
      for (final it in groupItems) {
        children.add(_ItemTile(
          item: it,
          theme: theme,
          mismatch: _isMismatch(it, fn, project),
          selected: _pending?.item.ref == it.ref,
          onTap: () => _onItemTapped(context, it),
        ));
      }
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  List<_PickerItem> _buildItems(FunctionDef fn, Project? project) {
    final items = <_PickerItem>[];

    // 上游节点输出（仅节点侧 nodeId 非空时解析）。
    if (widget.nodeId.isNotEmpty) {
      final upstream = ScopeResolver.resolveUpstreamOutputs(fn, widget.nodeId);
      for (final u in upstream) {
        items.add(_PickerItem(
          title: '${u.nodeLabel} › ${u.outputName}',
          subtitle: u.outputName,
          sourceLabel: '上游',
          type: u.type,
          ref: u.toRef(),
          group: _Group.upstream,
        ));
      }
    }

    // 函数变量：当前函数局部变量 + 页面级函数 outputs。
    for (final v in fn.funcVars) {
      items.add(_PickerItem(
        title: v.name,
        subtitle: v.name,
        sourceLabel: '函数变量',
        type: v.type,
        ref: VariableRef.funcVar(varId: v.id),
        group: _Group.funcVar,
      ));
    }
    for (final p in widget.pageFuncOutputs) {
      items.add(_PickerItem(
        title: '${p.funcName} › ${p.outputName}',
        subtitle: p.outputName,
        sourceLabel: '页面函数（含加载态）',
        type: p.type,
        ref: p.toRef(),
        group: _Group.funcVar,
      ));
    }

    // 项目变量。
    if (project != null) {
      for (final v in project.projectVars) {
        items.add(_PickerItem(
          title: v.name,
          subtitle: v.name,
          sourceLabel: '项目变量',
          type: v.type,
          ref: VariableRef.projVar(varId: v.id),
          group: _Group.projVar,
        ));
      }
    }

    // 组件上下文变量（仅 UI 侧传入）。
    for (final c in widget.componentVars) {
      items.add(_PickerItem(
        title: '${c.componentLabel} › ${c.fieldName}',
        subtitle: c.fieldName,
        sourceLabel: '组件上下文',
        type: c.type,
        ref: c.toRef(),
        group: _Group.component,
      ));
    }

    return items;
  }

  bool _matches(_PickerItem it) {
    // 同时匹配标题与子标题（fieldName / outputName），便于 `item.name` 命中。
    final q = _query;
    return it.title.toLowerCase().contains(q) ||
        it.subtitle.toLowerCase().contains(q);
  }

  bool _isMismatch(_PickerItem it, FunctionDef fn, Project? project) {
    final expected = widget.expectedType;
    if (expected == null) return false;
    return !checkRefType(it.ref, expected, fn, project).ok;
  }

  Widget _buildEmpty(ThemeData theme, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      ),
    );
  }

  String _groupLabel(_Group g) {
    switch (g) {
      case _Group.upstream:
        return '上游节点输出';
      case _Group.funcVar:
        return '函数变量';
      case _Group.projVar:
        return '项目变量';
      case _Group.component:
        return '组件上下文';
    }
  }

  /// 加载态策略配置面板（仅当待确认引用含时间线 / 组件上下文时显示）。
  ///
  /// 提供三种策略：类型默认值 / 占位文字 / 留空。用户配置后点"确定"返回
  /// [VariablePickResult]；点"取消"清空 _pending 回到选择列表。
  Widget _buildStrategyPanel(BuildContext context, ThemeData theme) {
    final p = _pending!;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '加载态策略：${p.item.title}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '该变量在运行时可能尚未就绪（函数未执行完成 / 容器未渲染到对应项），'
            '请选择未就绪时的展示策略。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final s in LoadingStrategy.values)
            RadioListTile<LoadingStrategy>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: s,
              groupValue: _strategy,
              title: Text(_strategyLabel(s)),
              subtitle: Text(_strategyDesc(s),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              onChanged: (v) {
                if (v != null) setState(() => _strategy = v);
              },
            ),
          if (_strategy == LoadingStrategy.placeholder) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _placeholderCtrl,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '占位文字，如"加载中..."',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _pending = null),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(VariablePickResult(
                  ref: p.item.ref,
                  loadingStrategy: _strategy,
                  placeholderText: _strategy == LoadingStrategy.placeholder
                      ? (_placeholderCtrl.text.trim().isEmpty
                          ? null
                          : _placeholderCtrl.text.trim())
                      : null,
                )),
                child: const Text('确定'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _strategyLabel(LoadingStrategy s) {
    switch (s) {
      case LoadingStrategy.typeDefault:
        return '类型默认值';
      case LoadingStrategy.placeholder:
        return '占位文字';
      case LoadingStrategy.blank:
        return '留空（不渲染该属性）';
    }
  }

  String _strategyDesc(LoadingStrategy s) {
    switch (s) {
      case LoadingStrategy.typeDefault:
        return 'number→0, string→\'\', list→[], map→{}, bool→false';
      case LoadingStrategy.placeholder:
        return '显示自定义占位文字';
      case LoadingStrategy.blank:
        return '文本类返回空串，图片类不渲染';
    }
  }
}

/// 待确认引用（暂存选中项，等待加载态策略配置）。
class _PendingPick {
  final _PickerItem item;
  const _PendingPick({required this.item});
}

/// 分组标识。
enum _Group { upstream, funcVar, projVar, component }

/// 卡片中单个可选变量项。
class _PickerItem {
  final String title;
  /// 子标题（用于搜索匹配；通常是 outputName / fieldName / 变量名）。
  final String subtitle;
  final String sourceLabel;
  final PortType type;
  final VariableRef ref;
  final _Group group;

  const _PickerItem({
    required this.title,
    required this.subtitle,
    required this.sourceLabel,
    required this.type,
    required this.ref,
    required this.group,
  });
}

/// 分组标题。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 单个变量项的展示行。
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.theme,
    required this.mismatch,
    required this.onTap,
    this.selected = false,
  });

  final _PickerItem item;
  final ThemeData theme;
  final bool mismatch;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = mismatch ? theme.colorScheme.outline : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _TypeChip(type: item.type, theme: theme, dim: mismatch),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: fg,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.sourceLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (mismatch)
              Tooltip(
                message: '类型不匹配',
                child: Icon(Icons.warning_amber,
                    size: 18, color: theme.colorScheme.error),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 20, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 类型 chip（主题色），用于参数期望与变量类型展示。
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.theme,
    this.hint,
    this.dim = false,
  });

  final PortType type;
  final ThemeData theme;
  final String? hint;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final bg = dim
        ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.7);
    final fg = dim
        ? theme.colorScheme.outline
        : theme.colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        hint == null ? type.toJson() : '$hint: ${type.toJson()}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
