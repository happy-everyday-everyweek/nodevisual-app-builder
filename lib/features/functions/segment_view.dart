import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/models/folder.dart';
import '../../data/models/function_def.dart';
import '../../data/models/project.dart';
import 'function_providers.dart';

/// 函数段视图。
///
/// 顶部搜索框 + 标签筛选；中部文件夹树（可展开/折叠）+ 函数列表；
/// 底部显示选中函数简要信息与"打开编辑器"入口。
/// 新建函数/文件夹、重命名、编辑标签、移动、删除均通过弹窗完成。
class FunctionsSegmentView extends ConsumerStatefulWidget {
  const FunctionsSegmentView({super.key});

  @override
  ConsumerState<FunctionsSegmentView> createState() =>
      _FunctionsSegmentViewState();
}

class _FunctionsSegmentViewState extends ConsumerState<FunctionsSegmentView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// 已展开的文件夹 id 集合（本地 UI 状态）。
  final Set<String> _expandedFolderIds = <String>{};

  /// 当前选中的标签筛选集合。
  final Set<String> _selectedTags = <String>{};

  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _isFiltering =>
      _searchQuery.trim().isNotEmpty || _selectedTags.isNotEmpty;

  /// 是否应该以平铺方式显示搜索/筛选结果。
  bool _functionMatches(FunctionDef fn) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty && !fn.name.toLowerCase().contains(q)) {
      return false;
    }
    if (_selectedTags.isNotEmpty) {
      for (final t in _selectedTags) {
        if (!fn.tags.contains(t)) {
          return false;
        }
      }
    }
    return true;
  }

  void _toggleExpand(String folderId) {
    setState(() {
      if (_expandedFolderIds.contains(folderId)) {
        _expandedFolderIds.remove(folderId);
      } else {
        _expandedFolderIds.add(folderId);
      }
    });
  }

  void _selectFunction(String? id) {
    ref.read(selectedFunctionIdProvider.notifier).state = id;
  }

  void _setCurrentFolder(String? id) {
    ref.read(currentFolderIdProvider.notifier).state = id;
  }

  // ---- 新建 ----

  Future<void> _showCreateMenu() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('新建'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'function'),
            child: const ListTile(
              leading: Icon(Icons.functions),
              title: Text('新建函数'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'folder'),
            child: const ListTile(
              leading: Icon(Icons.create_new_folder_outlined),
              title: Text('新建文件夹'),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'function':
        await _showCreateFunctionDialog();
        break;
      case 'folder':
        await _showCreateFolderDialog();
        break;
    }
  }

  Future<void> _showCreateFunctionDialog() async {
    final project = ref.read(projectMutatorProvider);
    if (project == null) return;
    final defaultFolderId = ref.read(currentFolderIdProvider);
    final result = await _showNameAndFolderDialog(
      title: '新建函数',
      hint: '函数名',
      initialName: '',
      project: project,
      initialFolderId: defaultFolderId,
      allowRoot: true,
    );
    if (result == null) return;
    final mutator = ref.read(projectMutatorProvider.notifier);
    final id = mutator.createFunction(result.name, folderId: result.folderId);
    _selectFunction(id);
    // 自动展开目标文件夹，便于看到新建结果。
    if (result.folderId != null) {
      setState(() => _expandedFolderIds.add(result.folderId!));
    }
  }

  Future<void> _showCreateFolderDialog() async {
    final project = ref.read(projectMutatorProvider);
    if (project == null) return;
    final defaultFolderId = ref.read(currentFolderIdProvider);
    final result = await _showNameAndFolderDialog(
      title: '新建文件夹',
      hint: '文件夹名',
      initialName: '',
      project: project,
      initialFolderId: defaultFolderId,
      allowRoot: true,
    );
    if (result == null) return;
    final mutator = ref.read(projectMutatorProvider.notifier);
    final id = mutator.createFolder(result.name, parentId: result.folderId);
    setState(() => _expandedFolderIds.add(id));
    if (result.folderId != null) {
      setState(() => _expandedFolderIds.add(result.folderId!));
    }
  }

  // ---- 函数操作 ----

  Future<void> _showRenameFunctionDialog(FunctionDef fn) async {
    final name = await _showTextInputDialog(
      title: '重命名函数',
      hint: '函数名',
      initial: fn.name,
    );
    if (name == null || name.trim().isEmpty) return;
    ref.read(projectMutatorProvider.notifier).renameFunction(fn.id, name.trim());
  }

  Future<void> _showEditTagsDialog(FunctionDef fn) async {
    final controller = TextEditingController(text: fn.tags.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标签',
            hintText: '多个标签用英文逗号分隔',
            border: OutlineInputBorder(),
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
    );
    controller.dispose();
    if (result == null) return;
    final tags = result.split(',').map((e) => e.trim()).toList();
    ref.read(projectMutatorProvider.notifier).setFunctionTags(fn.id, tags);
  }

  Future<void> _showMoveFunctionDialog(FunctionDef fn) async {
    final project = ref.read(projectMutatorProvider);
    if (project == null) return;
    final result = await _showNameAndFolderDialog(
      title: '移动到文件夹',
      hint: '',
      initialName: '',
      project: project,
      initialFolderId: fn.folderId,
      allowRoot: true,
      nameReadOnly: true,
    );
    if (result == null) return;
    ref
        .read(projectMutatorProvider.notifier)
        .moveFunctionToFolder(fn.id, result.folderId);
  }

  Future<void> _confirmDeleteFunction(FunctionDef fn) async {
    final ok = await _showConfirmDialog(
      title: '删除函数',
      content: '确定删除函数「${fn.name}」吗？此操作不可撤销。',
    );
    if (ok != true) return;
    ref.read(projectMutatorProvider.notifier).deleteFunction(fn.id);
  }

  // ---- 文件夹操作 ----

  Future<void> _showRenameFolderDialog(Folder folder) async {
    final name = await _showTextInputDialog(
      title: '重命名文件夹',
      hint: '文件夹名',
      initial: folder.name,
    );
    if (name == null || name.trim().isEmpty) return;
    ref
        .read(projectMutatorProvider.notifier)
        .renameFolder(folder.id, name.trim());
  }

  Future<void> _confirmDeleteFolder(Folder folder) async {
    final ok = await _showConfirmDialog(
      title: '删除文件夹',
      content: '确定删除文件夹「${folder.name}」吗？\n'
          '其下直属函数将移至根目录，子文件夹将上移一级。',
    );
    if (ok != true) return;
    if (ref.read(currentFolderIdProvider) == folder.id) {
      _setCurrentFolder(null);
    }
    ref.read(projectMutatorProvider.notifier).deleteFolder(folder.id);
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

  /// 名称 + 父文件夹选择器对话框。返回 (name, folderId)。
  Future<_NameFolderResult?> _showNameAndFolderDialog({
    required String title,
    required String hint,
    required String initialName,
    required Project project,
    required String? initialFolderId,
    required bool allowRoot,
    bool nameReadOnly = false,
  }) async {
    final nameController = TextEditingController(text: initialName);
    String? selectedFolderId = initialFolderId;
    return showDialog<_NameFolderResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final folderName = selectedFolderId == null
              ? '根目录'
              : (findFolder(project, selectedFolderId!)?.name ?? '根目录');
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hint.isNotEmpty)
                  TextField(
                    controller: nameController,
                    autofocus: !nameReadOnly,
                    readOnly: nameReadOnly,
                    decoration: InputDecoration(
                      hintText: hint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('所属文件夹',
                      style: Theme.of(ctx).textTheme.labelMedium,),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () async {
                    final picked = await _pickFolder(
                      project: project,
                      initialFolderId: selectedFolderId,
                      allowRoot: allowRoot,
                    );
                    if (picked != null) {
                      setState(() => selectedFolderId = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8,),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(folderName)),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
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
                  if (!nameReadOnly && nameController.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    _NameFolderResult(
                      name: nameController.text.trim(),
                      folderId: selectedFolderId,
                    ),
                  );
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(nameController.dispose);
  }

  /// 文件夹选择器：返回选中的 folderId（null 表示根目录）。
  /// 返回 null 表示用户取消。
  Future<String?> _pickFolder({
    required Project project,
    required String? initialFolderId,
    required bool allowRoot,
  }) async {
    // 用哨兵值表示"取消"。
    const cancelSentinel = '__cancel__';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        // 构建 folder id -> depth 的映射，用于缩进。
        final depthMap = <String, int>{};
        void assignDepth(String? parentId, int depth) {
          for (final f
              in project.folders.where((f) => f.parentId == parentId)) {
            depthMap[f.id] = depth;
            assignDepth(f.id, depth + 1);
          }
        }

        assignDepth(null, 0);
        final sortedFolders = project.folders.toList()
          ..sort((a, b) {
            final da = depthMap[a.id] ?? 0;
            final db = depthMap[b.id] ?? 0;
            if (da != db) return da.compareTo(db);
            return a.name.compareTo(b.name);
          });

        return AlertDialog(
          title: const Text('选择文件夹'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (allowRoot)
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('根目录'),
                    selected: initialFolderId == null,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                for (final f in sortedFolders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Padding(
                      padding: EdgeInsets.only(
                          left: (depthMap[f.id] ?? 0) * 16.0,),
                      child: Text(f.name),
                    ),
                    selected: f.id == initialFolderId,
                    onTap: () => Navigator.pop(ctx, f.id),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, cancelSentinel),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    if (result == null || result == cancelSentinel) return null;
    return result.isEmpty ? null : result;
  }

  // ---- 构建 UI ----

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectMutatorProvider);
    final theme = Theme.of(context);
    final selectedId = ref.watch(selectedFunctionIdProvider);
    // 监听当前文件夹，确保"当前文件夹"高亮随选中变化刷新。
    ref.watch(currentFolderIdProvider);

    if (project == null) {
      return const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(child: Text('未打开项目')),
        ),
      );
    }

    final allTags = collectAllTags(project);
    final selectedFn =
        selectedId == null ? null : findFunction(project, selectedId);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 72),
        child: Column(
          children: [
            _buildHeader(theme),
            _buildSearchField(theme),
            if (allTags.isNotEmpty)
              _buildTagFilters(theme, allTags),
            Expanded(
              child: _isFiltering
                  ? _buildFlatList(project, theme, selectedId)
                  : _buildTreeList(project, theme, selectedId),
            ),
            if (selectedFn != null)
              _buildSelectedPanel(project, theme, selectedFn),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    // Tab 名称"函数"已在顶部 CapsuleTopBar 指明，这里仅保留新建按钮，避免重复。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            onPressed: _showCreateMenu,
            icon: const Icon(Icons.add),
            tooltip: '新建',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: '搜索函数名',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildTagFilters(ThemeData theme, List<String> allTags) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in allTags)
              FilterChip(
                label: Text(tag),
                selected: _selectedTags.contains(tag),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedTags.add(tag);
                    } else {
                      _selectedTags.remove(tag);
                    }
                  });
                },
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  /// 平铺搜索/筛选结果。
  Widget _buildFlatList(Project project, ThemeData theme, String? selectedId) {
    final matched = project.functions.where(_functionMatches).toList();
    if (matched.isEmpty) {
      return Center(
        child: Text(
          '无匹配函数',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: matched.length,
      itemBuilder: (ctx, i) {
        final fn = matched[i];
        return _FunctionTile(
          function: fn,
          depth: 0,
          selected: fn.id == selectedId,
          showFolderPath: true,
          project: project,
          onTap: () => _selectFunction(fn.id),
          onRename: () => _showRenameFunctionDialog(fn),
          onEditTags: () => _showEditTagsDialog(fn),
          onMove: () => _showMoveFunctionDialog(fn),
          onDelete: () => _confirmDeleteFunction(fn),
        );
      },
    );
  }

  /// 文件夹树 + 函数列表。
  Widget _buildTreeList(Project project, ThemeData theme, String? selectedId) {
    final widgets = <Widget>[];

    // 顶层文件夹。
    for (final folder in getChildFolders(project, null)) {
      widgets.addAll(_buildFolderSubtree(project, folder, 0, selectedId));
    }
    // 根目录函数。
    for (final fn in getFunctionsInFolder(project, null)) {
      widgets.add(_FunctionTile(
        function: fn,
        depth: 0,
        selected: fn.id == selectedId,
        project: project,
        onTap: () => _selectFunction(fn.id),
        onRename: () => _showRenameFunctionDialog(fn),
        onEditTags: () => _showEditTagsDialog(fn),
        onMove: () => _showMoveFunctionDialog(fn),
        onDelete: () => _confirmDeleteFunction(fn),
      ),);
    }

    if (widgets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.functions_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant,),
            const SizedBox(height: 8),
            Text(
              '暂无函数，点击右上角 + 新建',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: widgets,
    );
  }

  /// 递归构建某文件夹的子树 widget 列表（含文件夹头 + 展开后的内容）。
  List<Widget> _buildFolderSubtree(
    Project project,
    Folder folder,
    int depth,
    String? selectedId,
  ) {
    final widgets = <Widget>[];
    final expanded = _expandedFolderIds.contains(folder.id);
    final isCurrent = ref.read(currentFolderIdProvider) == folder.id;
    widgets.add(_FolderRow(
      folder: folder,
      depth: depth,
      expanded: expanded,
      isCurrent: isCurrent,
      onToggleExpand: () => _toggleExpand(folder.id),
      onTap: () => _setCurrentFolder(folder.id),
      onRename: () => _showRenameFolderDialog(folder),
      onDelete: () => _confirmDeleteFolder(folder),
      onCreateFunction: () async {
        _setCurrentFolder(folder.id);
        if (!expanded) _toggleExpand(folder.id);
        await _showCreateFunctionDialog();
      },
      onCreateFolder: () async {
        _setCurrentFolder(folder.id);
        if (!expanded) _toggleExpand(folder.id);
        await _showCreateFolderDialog();
      },
    ),);
    if (expanded) {
      for (final child in getChildFolders(project, folder.id)) {
        widgets.addAll(_buildFolderSubtree(project, child, depth + 1, selectedId));
      }
      for (final fn in getFunctionsInFolder(project, folder.id)) {
        widgets.add(_FunctionTile(
          function: fn,
          depth: depth + 1,
          selected: fn.id == selectedId,
          project: project,
          onTap: () => _selectFunction(fn.id),
          onRename: () => _showRenameFunctionDialog(fn),
          onEditTags: () => _showEditTagsDialog(fn),
          onMove: () => _showMoveFunctionDialog(fn),
          onDelete: () => _confirmDeleteFunction(fn),
        ),);
      }
    }
    return widgets;
  }

  /// 底部选中函数信息面板。
  Widget _buildSelectedPanel(
      Project project, ThemeData theme, FunctionDef fn,) {
    final folderPath = getFolderPath(project, fn.folderId);
    final pathText = folderPath.isEmpty
        ? '根目录'
        : folderPath.map((f) => f.name).join(' / ');
    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.functions, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fn.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '取消选中',
                  onPressed: () => _selectFunction(null),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '所在：$pathText',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (fn.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in fn.tags)
                    _MiniTagChip(label: tag, color: theme.colorScheme.primary),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.go(
                  AppConstants.functionEditorRoute(project.meta.id, fn.id),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打开编辑器'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 名称 + 文件夹选择结果。
class _NameFolderResult {
  const _NameFolderResult({required this.name, required this.folderId});

  final String name;
  final String? folderId;
}

/// 文件夹行（树节点头）。
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.depth,
    required this.expanded,
    required this.isCurrent,
    required this.onToggleExpand,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onCreateFunction,
    required this.onCreateFolder,
  });

  final Folder folder;
  final int depth;
  final bool expanded;
  final bool isCurrent;
  final VoidCallback onToggleExpand;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onCreateFunction;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = 16.0 + depth * 16.0;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 22,
                ),
                onPressed: onToggleExpand,
                tooltip: expanded ? '折叠' : '展开',
                visualDensity: VisualDensity.compact,
              ),
              Icon(
                expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 22,
                color: isCurrent
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folder.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                    color: isCurrent ? theme.colorScheme.primary : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: '更多',
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'createFunction',
                    child: ListTile(
                      leading: Icon(Icons.functions),
                      title: Text('在此新建函数'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'createFolder',
                    child: ListTile(
                      leading: Icon(Icons.create_new_folder_outlined),
                      title: Text('新建子文件夹'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('重命名'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('删除'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (v) {
                  switch (v) {
                    case 'createFunction':
                      onCreateFunction();
                      break;
                    case 'createFolder':
                      onCreateFolder();
                      break;
                    case 'rename':
                      onRename();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 函数项。
class _FunctionTile extends StatelessWidget {
  const _FunctionTile({
    required this.function,
    required this.depth,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onEditTags,
    required this.onMove,
    required this.onDelete,
    this.project,
    this.showFolderPath = false,
  });

  final FunctionDef function;
  final int depth;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onEditTags;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final Project? project;
  final bool showFolderPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent = 16.0 + depth * 16.0;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: EdgeInsets.only(left: indent, right: 4),
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : null,
        child: Row(
          children: [
            const SizedBox(width: 38), // 与文件夹的展开箭头对齐
            Icon(
              Icons.functions,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    function.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected ? theme.colorScheme.primary : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showFolderPath &&
                      project != null &&
                      function.folderId != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      getFolderPath(project!, function.folderId)
                          .map((f) => f.name)
                          .join(' / '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (function.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        for (final tag in function.tags.take(4))
                          _MiniTagChip(
                              label: tag, color: theme.colorScheme.tertiary,),
                        if (function.tags.length > 4)
                          _MiniTagChip(
                            label: '+${function.tags.length - 4}',
                            color: theme.colorScheme.outline,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: '更多',
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    leading: Icon(Icons.drive_file_rename_outline),
                    title: Text('重命名'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'tags',
                  child: ListTile(
                    leading: Icon(Icons.label_outline),
                    title: Text('编辑标签'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'move',
                  child: ListTile(
                    leading: Icon(Icons.drive_file_move_outline),
                    title: Text('移动到'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('删除'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (v) {
                switch (v) {
                  case 'rename':
                    onRename();
                    break;
                  case 'tags':
                    onEditTags();
                    break;
                  case 'move':
                    onMove();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 小尺寸标签 Chip（仅展示，颜色取自主题）。
class _MiniTagChip extends StatelessWidget {
  const _MiniTagChip({required this.label, required this.color});

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
