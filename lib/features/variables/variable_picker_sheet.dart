import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/function_def.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/variable_ref.dart';
import '../functions/function_providers.dart';
import '../node_graph/type_checker.dart';
import '../project/project_providers.dart';
import 'scope_resolver.dart';

/// 变量选择卡片（底部 BottomSheet）。
///
/// 在节点编辑页参数输入框触发 `#` 时弹出，按三来源（控制流上游节点输出 /
/// 函数变量 / 项目变量）分组展示可选变量，支持搜索过滤、类型提示与
/// 跨来源同名冲突标注。选中后返回 [VariableRef]。
///
/// Material 3，移动端友好：高度初始 60% 屏幕，可拖拽至近全屏。
class VariablePickerSheet extends ConsumerStatefulWidget {
  const VariablePickerSheet({
    super.key,
    required this.functionId,
    required this.nodeId,
    this.expectedType,
    this.initialQuery = '',
  });

  final String functionId;

  /// 触发 `#` 的当前节点 id（用于解析控制流上游作用域）。
  final String nodeId;

  /// 期望类型（用于类型提示与不匹配项灰显 / ⚠ 标注）。null 视为不约束。
  final PortType? expectedType;

  /// 初始搜索词（由 `#名称` 快速引用未唯一命中时预填）。
  final String initialQuery;

  /// 以底部 BottomSheet 形式弹出卡片；返回用户选中的 [VariableRef]，
  /// 用户取消（下拉关闭 / 返回）时返回 null。
  static Future<VariableRef?> show(
    BuildContext context, {
    required String functionId,
    required String nodeId,
    PortType? expectedType,
    String? initialQuery,
  }) {
    return showModalBottomSheet<VariableRef>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VariablePickerSheet(
        functionId: functionId,
        nodeId: nodeId,
        expectedType: expectedType,
        initialQuery: initialQuery ?? '',
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

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery.trim().toLowerCase();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

    // 按分组顺序渲染：上游 → 函数变量 → 项目变量。
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
          onTap: () => Navigator.of(context).pop(it.ref),
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
    final avail = ScopeResolver.resolveAllAvailable(fn, project, widget.nodeId);
    final items = <_PickerItem>[];
    for (final u in avail.upstream) {
      items.add(_PickerItem(
        title: '${u.nodeLabel} › ${u.outputName}',
        sourceLabel: '上游',
        type: u.type,
        ref: u.toRef(),
        group: _Group.upstream,
      ));
    }
    for (final v in avail.funcVars) {
      items.add(_PickerItem(
        title: v.name,
        sourceLabel: '函数变量',
        type: v.type,
        ref: VariableRef.funcVar(varId: v.id),
        group: _Group.funcVar,
      ));
    }
    for (final v in avail.projectVars) {
      items.add(_PickerItem(
        title: v.name,
        sourceLabel: '项目变量',
        type: v.type,
        ref: VariableRef.projVar(varId: v.id),
        group: _Group.projVar,
      ));
    }
    return items;
  }

  bool _matches(_PickerItem it) => it.title.toLowerCase().contains(_query);

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
    }
  }
}

/// 分组标识。
enum _Group { upstream, funcVar, projVar }

/// 卡片中单个可选变量项。
class _PickerItem {
  final String title;
  final String sourceLabel;
  final PortType type;
  final VariableRef ref;
  final _Group group;

  const _PickerItem({
    required this.title,
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
  });

  final _PickerItem item;
  final ThemeData theme;
  final bool mismatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = mismatch ? theme.colorScheme.outline : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
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
