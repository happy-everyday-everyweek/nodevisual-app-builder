import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/db_schema.dart' as db;
import '../../data/models/project.dart';
import 'database_providers.dart';

/// 支持的列类型（小写字面量，对应 IR schema）。
const List<String> _kColumnTypes = ['text', 'integer', 'real', 'blob'];

/// 数据库段视图：表结构定义编辑器。
///
/// 列出当前项目的所有表（[db.DbTable]），每张表以卡片展示表名 + 列数，
/// 点击卡片展开预览列；通过菜单重命名表 / 编辑列（BottomSheet）/ 删除表；
/// 顶部 + 按钮新建空表。移动端优先，列编辑通过 BottomSheet 完成。
class DatabaseSegmentView extends ConsumerStatefulWidget {
  const DatabaseSegmentView({super.key});

  @override
  ConsumerState<DatabaseSegmentView> createState() =>
      _DatabaseSegmentViewState();
}

class _DatabaseSegmentViewState extends ConsumerState<DatabaseSegmentView> {
  /// 已展开预览的表名集合（本地 UI 状态）。
  final Set<String> _expandedTableNames = <String>{};

  void _toggleExpand(String name) {
    setState(() {
      if (_expandedTableNames.contains(name)) {
        _expandedTableNames.remove(name);
      } else {
        _expandedTableNames.add(name);
      }
    });
  }

  // ---- 新建表 ----

  Future<void> _showCreateTableDialog() async {
    final name = await _showTextInputDialog(
      title: '新建表',
      hint: '表名',
      initial: '',
    );
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final ok = ref.read(dbMutatorProvider.notifier).createTable(trimmed);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('表名已存在或为空，创建失败')),
      );
      return;
    }
    setState(() => _expandedTableNames.add(trimmed));
  }

  // ---- 重命名表 ----

  Future<void> _showRenameTableDialog(db.DbTable table) async {
    final name = await _showTextInputDialog(
      title: '重命名表',
      hint: '表名',
      initial: table.name,
    );
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == table.name) return;
    final ok =
        ref.read(dbMutatorProvider.notifier).renameTable(table.name, trimmed);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目标表名已存在，重命名失败')),
      );
      return;
    }
    // 同步展开态到新表名。
    if (_expandedTableNames.remove(table.name)) {
      setState(() => _expandedTableNames.add(trimmed));
    }
  }

  // ---- 编辑列（BottomSheet）----

  void _showEditColumnsSheet(db.DbTable table) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _EditColumnsSheet(tableName: table.name),
    );
  }

  // ---- 删除表 ----

  Future<void> _confirmDeleteTable(db.DbTable table) async {
    final ok = await _showConfirmDialog(
      title: '删除表',
      content: '确定删除表「${table.name}」吗？此操作不可撤销。',
    );
    if (ok != true) return;
    ref.read(dbMutatorProvider.notifier).deleteTable(table.name);
    _expandedTableNames.remove(table.name);
  }

  // ---- 通用对话框 ----

  Future<String?> _showTextInputDialog({
    required String title,
    required String hint,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ---- 构建 UI ----

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(dbMutatorProvider);
    final theme = Theme.of(context);

    if (project == null) {
      return const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: Text('未打开项目')),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 72),
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: project.db.isEmpty
                  ? _buildEmpty(theme)
                  : _buildList(project, theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    // Tab 名称"数据库"已在顶部 CapsuleTopBar 指明，这里仅保留新建按钮，避免重复。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            onPressed: _showCreateTableDialog,
            icon: const Icon(Icons.add),
            tooltip: '新建表',
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '数据库段为空',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '点击右上角 + 新建第一张表',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildList(Project project, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: project.db.length,
      itemBuilder: (ctx, i) => _buildTableCard(project.db[i], theme),
    );
  }

  Widget _buildTableCard(db.DbTable table, ThemeData theme) {
    final expanded = _expandedTableNames.contains(table.name);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(table.name),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.table_chart_outlined,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      table.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _MiniChip(
                    label: '${table.columns.length} 列',
                    color: theme.colorScheme.tertiary,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: '更多',
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          leading: Icon(Icons.drive_file_rename_outline),
                          title: Text('重命名表'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'editColumns',
                        child: ListTile(
                          leading: Icon(Icons.view_column_outlined),
                          title: Text('编辑列'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('删除表'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                    onSelected: (v) {
                      switch (v) {
                        case 'rename':
                          _showRenameTableDialog(table);
                          break;
                        case 'editColumns':
                          _showEditColumnsSheet(table);
                          break;
                        case 'delete':
                          _confirmDeleteTable(table);
                          break;
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            if (table.columns.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  '暂无列，点击「编辑列」添加',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in table.columns)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.data_array,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                c.name,
                                style: theme.textTheme.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _MiniChip(
                              label: c.type,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 列编辑 BottomSheet
// ============================================================================

/// 列编辑 BottomSheet：增删列、改列名、改列类型。
///
/// 通过 [dbMutatorProvider] 监听项目变化，实时反映已提交的列结构；
/// 每次（增/删/改名/改类型）操作即时写回并持久化。
class _EditColumnsSheet extends ConsumerWidget {
  const _EditColumnsSheet({required this.tableName});

  final String tableName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // watch 以在项目变更时重建（列增删/改名/改类型后即时刷新）。
    final project = ref.watch(dbMutatorProvider);
    final mutator = ref.read(dbMutatorProvider.notifier);
    // 声明为 final，使空检查后的非空提升在下方闭包（onPressed）中依然有效。
    final db.DbTable? table =
        project == null ? null : mutator.findTable(tableName);

    // 表已被删除（外部并发修改），关闭 sheet。
    if (table == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '编辑列「${table.name}」',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '共 ${table.columns.length} 列',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in table.columns)
                  _ColumnRow(
                    key: ValueKey('${table.name}:${c.name}'),
                    tableName: table.name,
                    column: c,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final existing =
                    table.columns.map((c) => c.name).toSet();
                var i = 1;
                var name = 'column_1';
                while (existing.contains(name)) {
                  i++;
                  name = 'column_$i';
                }
                mutator.addColumn(
                  table.name,
                  db.Column(name: name, type: 'text'),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加列'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单行列编辑器：列名（失焦/提交时改名）+ 类型下拉 + 删除按钮。
class _ColumnRow extends ConsumerStatefulWidget {
  const _ColumnRow({
    super.key,
    required this.tableName,
    required this.column,
  });

  final String tableName;
  final db.Column column;

  @override
  ConsumerState<_ColumnRow> createState() => _ColumnRowState();
}

class _ColumnRowState extends ConsumerState<_ColumnRow> {
  late final TextEditingController _nameController;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.column.name);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _ColumnRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 非聚焦时把外部值回填到控制器，避免重名等被忽略的改名残留输入。
    if (!_focus.hasFocus && _nameController.text != widget.column.name) {
      _nameController.text = widget.column.name;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      _commitName();
    }
  }

  void _commitName() {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == widget.column.name) return;
    ref
        .read(dbMutatorProvider.notifier)
        .renameColumn(widget.tableName, widget.column.name, newName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _nameController,
              focusNode: _focus,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '列名',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commitName(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _kColumnTypes.contains(widget.column.type)
                  ? widget.column.type
                  : _kColumnTypes.first,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in _kColumnTypes)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(dbMutatorProvider.notifier)
                    .changeColumnType(widget.tableName, widget.column.name, v);
              },
            ),
          ),
          IconButton(
            tooltip: '删除列',
            icon: Icon(
              Icons.remove_circle_outline,
              size: 20,
              color: theme.colorScheme.error,
            ),
            onPressed: () {
              ref
                  .read(dbMutatorProvider.notifier)
                  .removeColumn(widget.tableName, widget.column.name);
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 通用小组件
// ============================================================================

/// 小尺寸标签 Chip（仅展示，颜色取自主题）。
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}
