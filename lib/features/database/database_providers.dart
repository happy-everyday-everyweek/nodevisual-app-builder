import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/db_schema.dart';
import '../../data/models/project.dart';
import '../functions/function_providers.dart';
import '../project/project_providers.dart';

/// 数据库段变更器：管理 [Project.db]（[DbTable] 列表）。
///
/// state 始终镜像 [projectMutatorProvider]（在 [build] 中 watch），
/// 所有变更方法把新 [Project] 快照写回 [currentProjectProvider] 并异步落盘。
/// UI 通过 `ref.watch(dbMutatorProvider)` 获取当前项目，
/// 通过 `ref.read(dbMutatorProvider.notifier).xxx()` 执行变更。
///
/// 注意：[DbTable] 模型无 id 字段，故以表名（[DbTable.name]）作为唯一标识。
/// 本变更器所有方法均以表名定位表；重命名时传入旧表名 + 新表名。
class DbMutator extends Notifier<Project?> {
  @override
  Project? build() {
    return ref.watch(projectMutatorProvider);
  }

  Project? get _project => ref.read(currentProjectProvider);

  void _commit(Project newProject) {
    ref.read(currentProjectProvider.notifier).state = newProject;
    // 持久化失败不阻塞 UI；仓库内部会刷新 updatedAt。
    ref.read(projectRepositoryProvider).saveProject(newProject);
  }

  /// 按表名查找表；不存在返回 null。
  DbTable? findTable(String tableName) {
    final p = _project;
    if (p == null) return null;
    for (final t in p.db) {
      if (t.name == tableName) return t;
    }
    return null;
  }

  /// 创建空表；返回是否成功（表名为空、已存在或项目未打开时返回 false）。
  bool createTable(String name) {
    final p = _project;
    if (p == null) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (findTable(trimmed) != null) return false;
    _commit(p.copyWith(db: [...p.db, DbTable(name: trimmed)]));
    return true;
  }

  /// 重命名表；返回是否成功（新名为空、与原名相同、或目标名已存在时返回 false）。
  bool renameTable(String oldName, String newName) {
    final p = _project;
    if (p == null) return false;
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == oldName) return false;
    if (findTable(trimmed) != null) return false;
    _commit(p.copyWith(
      db: p.db
          .map((t) => t.name == oldName ? t.copyWith(name: trimmed) : t)
          .toList(growable: false),
    ));
    return true;
  }

  /// 增加列；同名列已存在则忽略。
  void addColumn(String tableName, Column column) {
    final p = _project;
    if (p == null) return;
    _commit(p.copyWith(
      db: p.db.map((t) {
        if (t.name != tableName) return t;
        if (t.columns.any((c) => c.name == column.name)) return t;
        return t.copyWith(columns: [...t.columns, column]);
      }).toList(growable: false),
    ),);
  }

  /// 移除列。
  void removeColumn(String tableName, String columnName) {
    final p = _project;
    if (p == null) return;
    _commit(p.copyWith(
      db: p.db.map((t) {
        if (t.name != tableName) return t;
        return t.copyWith(
          columns: t.columns
              .where((c) => c.name != columnName)
              .toList(growable: false),
        );
      }).toList(growable: false),
    ),);
  }

  /// 重命名列；新名为空、与原名相同、或与同表其它列重名时忽略。
  void renameColumn(String tableName, String oldName, String newName) {
    final p = _project;
    if (p == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == oldName) return;
    _commit(p.copyWith(
      db: p.db.map((t) {
        if (t.name != tableName) return t;
        if (t.columns.any((c) => c.name == trimmed)) return t;
        return t.copyWith(
          columns: t.columns
              .map((c) => c.name == oldName ? c.copyWith(name: trimmed) : c)
              .toList(growable: false),
        );
      }).toList(growable: false),
    ),);
  }

  /// 修改列类型。
  void changeColumnType(String tableName, String columnName, String newType) {
    final p = _project;
    if (p == null) return;
    _commit(p.copyWith(
      db: p.db.map((t) {
        if (t.name != tableName) return t;
        return t.copyWith(
          columns: t.columns
              .map((c) => c.name == columnName ? c.copyWith(type: newType) : c)
              .toList(growable: false),
        );
      }).toList(growable: false),
    ),);
  }

  /// 删除表。
  void deleteTable(String tableName) {
    final p = _project;
    if (p == null) return;
    _commit(p.copyWith(
      db: p.db.where((t) => t.name != tableName).toList(growable: false),
    ),);
  }
}

/// 数据库段变更器 provider。
///
/// UI 应通过本 provider 监听当前项目状态，并通过其 notifier 执行变更。
final dbMutatorProvider =
    NotifierProvider<DbMutator, Project?>(DbMutator.new);
