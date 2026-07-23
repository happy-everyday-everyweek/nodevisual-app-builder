import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/folder.dart';
import '../../data/models/function_def.dart';
import '../../data/models/project.dart';
import '../project/project_providers.dart';

const Uuid _uuid = Uuid();

// ============================================================================
// 纯函数工具方法（文件夹树 / 标签 / 路径）
// ============================================================================

/// 获取某文件夹的直接子文件夹列表。
List<Folder> getChildFolders(Project project, String? parentId) {
  return project.folders
      .where((f) => f.parentId == parentId)
      .toList(growable: false);
}

/// 递归获取某文件夹下所有后代文件夹（不含自身）。
///
/// 使用迭代而非递归实现，避免深嵌套时的栈溢出风险。
List<Folder> getDescendantFolders(Project project, String folderId) {
  final result = <Folder>[];
  final queue = <String>[folderId];
  final visited = <String>{folderId};
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    final children = project.folders.where((f) => f.parentId == current);
    for (final child in children) {
      if (visited.add(child.id)) {
        result.add(child);
        queue.add(child.id);
      }
    }
  }
  return result;
}

/// 获取某文件夹下直属的函数列表（folderId 严格等于该 id）。
List<FunctionDef> getFunctionsInFolder(Project project, String? folderId) {
  return project.functions
      .where((fn) => fn.folderId == folderId)
      .toList(growable: false);
}

/// 计算某文件夹从根到自身的路径（含自身），顶层文件夹路径长度为 1。
///
/// folderId 为 null（根目录）或不存在时返回空列表。
List<Folder> getFolderPath(Project project, String? folderId) {
  if (folderId == null) return const [];
  final path = <Folder>[];
  final byId = {for (final f in project.folders) f.id: f};
  String? current = folderId;
  final guard = <String>{};
  while (current != null && byId.containsKey(current) && guard.add(current)) {
    path.insert(0, byId[current]!);
    current = byId[current]!.parentId;
  }
  return path;
}

/// 收集项目中所有已使用过的标签（去重，保留出现顺序）。
List<String> collectAllTags(Project project) {
  final seen = <String>{};
  for (final fn in project.functions) {
    for (final tag in fn.tags) {
      seen.add(tag);
    }
  }
  return seen.toList(growable: false);
}

/// 查找函数；不存在返回 null。
FunctionDef? findFunction(Project project, String id) {
  for (final fn in project.functions) {
    if (fn.id == id) return fn;
  }
  return null;
}

/// 查找文件夹；不存在返回 null。
Folder? findFolder(Project project, String id) {
  for (final f in project.folders) {
    if (f.id == id) return f;
  }
  return null;
}

// ============================================================================
// 项目状态变更器
// ============================================================================

/// 当前选中函数 id（null 表示未选中）。
final selectedFunctionIdProvider = StateProvider<String?>((ref) => null);

/// 当前选中文件夹 id（null 表示根目录）。
///
/// 用于"新建函数/文件夹"的默认归属：新建时默认放入当前文件夹，
/// 用户可在新建对话框中改选其他文件夹。
final currentFolderIdProvider = StateProvider<String?>((ref) => null);

/// 项目变更器：封装对当前项目的所有修改操作。
///
/// state 始终镜像 [currentProjectProvider]（在 [build] 中 watch），
/// 所有变更方法只写入 [currentProjectProvider]，随后触发异步持久化。
/// UI 通过 `ref.watch(projectMutatorProvider)` 获取当前项目，
/// 通过 `ref.read(projectMutatorProvider.notifier).xxx()` 执行变更。
class ProjectMutator extends Notifier<Project?> {
  @override
  Project? build() {
    // 镜像 currentProjectProvider：外部加载项目后这里自动同步。
    return ref.watch(currentProjectProvider);
  }

  /// 将新项目快照写回 currentProjectProvider 并异步落盘。
  void _commit(Project newProject) {
    ref.read(currentProjectProvider.notifier).state = newProject;
    // 持久化失败不阻塞 UI；仓库内部会刷新 updatedAt。
    final repo = ref.read(projectRepositoryProvider);
    repo.saveProject(newProject);
  }

  Project? get _project => ref.read(currentProjectProvider);

  // ---- 函数 CRUD ----

  /// 创建函数；返回新函数 id。folderId 为 null 表示放在根目录。
  String createFunction(String name, {String? folderId}) {
    final p = _project;
    if (p == null) {
      throw StateError('未打开任何项目，无法创建函数');
    }
    final id = _uuid.v4();
    final fn = FunctionDef(id: id, name: name, folderId: folderId);
    _commit(p.copyWith(functions: [...p.functions, fn]));
    return id;
  }

  /// 重命名函数。
  void renameFunction(String id, String newName) {
    final p = _project;
    if (p == null) return;
    _commit(p.copyWith(
      functions: p.functions
          .map((f) => f.id == id ? f.copyWith(name: newName) : f)
          .toList(growable: false),
    ),);
  }

  /// 设置函数标签（整体替换，内部去重）。
  void setFunctionTags(String id, List<String> tags) {
    final p = _project;
    if (p == null) return;
    final deduped = <String>[];
    final seen = <String>{};
    for (final t in tags) {
      final trimmed = t.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        deduped.add(trimmed);
      }
    }
    _commit(p.copyWith(
      functions: p.functions
          .map((f) => f.id == id ? f.copyWith(tags: deduped) : f)
          .toList(growable: false),
    ),);
  }

  /// 增加单个标签（去重）。
  void addTag(String funcId, String tag) {
    final p = _project;
    if (p == null) return;
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    _commit(p.copyWith(
      functions: p.functions.map((f) {
        if (f.id != funcId) return f;
        if (f.tags.contains(trimmed)) return f;
        return f.copyWith(tags: [...f.tags, trimmed]);
      }).toList(growable: false),
    ),);
  }

  /// 移除单个标签。
  void removeTag(String funcId, String tag) {
    final p = _project;
    if (p == null) return;
    _commit(p.copyWith(
      functions: p.functions
          .map((f) => f.id == funcId
              ? f.copyWith(tags: f.tags.where((t) => t != tag).toList())
              : f,)
          .toList(growable: false),
    ),);
  }

  /// 移动函数到指定文件夹；folderId 为 null 表示移到根目录。
  void moveFunctionToFolder(String funcId, String? folderId) {
    final p = _project;
    if (p == null) return;
    // 防御：目标文件夹必须存在（null 视为根目录合法）。
    if (folderId != null && findFolder(p, folderId) == null) return;
    _commit(p.copyWith(
      functions: p.functions
          .map((f) => f.id == funcId ? f.copyWith(folderId: folderId) : f)
          .toList(growable: false),
    ),);
  }

  /// 删除函数；若其被选中，清除选中态。
  void deleteFunction(String id) {
    final p = _project;
    if (p == null) return;
    if (ref.read(selectedFunctionIdProvider) == id) {
      ref.read(selectedFunctionIdProvider.notifier).state = null;
    }
    _commit(p.copyWith(
      functions: p.functions.where((f) => f.id != id).toList(growable: false),
    ),);
  }

  // ---- 文件夹 CRUD ----

  /// 创建文件夹；返回新文件夹 id。parentId 为 null 表示顶层。
  String createFolder(String name, {String? parentId}) {
    final p = _project;
    if (p == null) {
      throw StateError('未打开任何项目，无法创建文件夹');
    }
    final id = _uuid.v4();
    final folder = Folder(id: id, name: name, parentId: parentId);
    var newFolders = [...p.folders, folder];
    // 同步父文件夹的 childrenIds。
    if (parentId != null) {
      newFolders = newFolders
          .map((f) => f.id == parentId
              ? f.copyWith(childrenIds: [...f.childrenIds, id])
              : f,)
          .toList(growable: false);
    }
    _commit(p.copyWith(folders: newFolders));
    return id;
  }

  /// 重命名文件夹。
  void renameFolder(String id, String newName) {
    final p = _project;
    if (p == null) return;
    _commit(p.copyWith(
      folders: p.folders
          .map((f) => f.id == id ? f.copyWith(name: newName) : f)
          .toList(growable: false),
    ),);
  }

  /// 删除文件夹。
  ///
  /// 删除策略：该文件夹自身移除；其直属函数 folderId 置空（上浮到根目录）；
  /// 其子文件夹上移到被删文件夹的父级（parentId 改为被删文件夹的 parentId），
  /// 并更新父级 childrenIds。
  void deleteFolder(String id) {
    final p = _project;
    if (p == null) return;
    final target = findFolder(p, id);
    if (target == null) return;
    final grandParentId = target.parentId;

    // 该文件夹的直接子文件夹 id 列表（用于追加到祖父级 childrenIds）。
    final directChildIds = p.folders
        .where((f) => f.parentId == id)
        .map((f) => f.id)
        .toList(growable: false);

    // 新文件夹列表：跳过被删文件夹；其直接子文件夹 parentId 改写为 grandParentId。
    // 深层后代保持原 parentId（其直接父文件夹未被删除，仅上移，祖先链未断）。
    var newFolders = <Folder>[];
    for (final f in p.folders) {
      if (f.id == id) continue; // 删除自身
      if (f.parentId == id) {
        // 直接子文件夹上移到祖父级
        newFolders.add(f.copyWith(parentId: grandParentId));
      } else {
        newFolders.add(f);
      }
    }

    // 更新祖父级 childrenIds：移除被删文件夹 id，追加其直接子文件夹 id。
    if (grandParentId != null) {
      newFolders = newFolders.map((f) {
        if (f.id != grandParentId) return f;
        final newChildren = <String>[];
        for (final cid in f.childrenIds) {
          if (cid == id) continue;
          newChildren.add(cid);
        }
        newChildren.addAll(directChildIds);
        return f.copyWith(childrenIds: newChildren);
      }).toList(growable: false);
    }

    // 该文件夹直属函数 folderId 置空（上浮到根目录）。
    final newFunctions = p.functions.map((fn) {
      if (fn.folderId == id) return fn.copyWith(folderId: null);
      return fn;
    }).toList(growable: false);

    _commit(p.copyWith(folders: newFolders, functions: newFunctions));
  }
}

/// 项目变更器 provider。
///
/// UI 应通过本 provider 监听当前项目状态，并通过其 notifier 执行变更。
final projectMutatorProvider =
    NotifierProvider<ProjectMutator, Project?>(ProjectMutator.new);
