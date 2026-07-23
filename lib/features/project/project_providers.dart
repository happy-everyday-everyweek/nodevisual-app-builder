import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/local_storage.dart';
import '../../data/models/project.dart';
import '../../data/repositories/project_repository.dart';

/// 编辑器段（segment）枚举：函数 / 数据库 / UI。
///
/// 顶层胶囊 Top 栏据此切换 [EditorShellScreen] 的内容区。
enum EditorSegment { functions, database, ui }

/// 本地存储实例（基于 SQLite + 文件系统）。
///
/// 作为单例 provider 暴露，仓库层依赖此 provider。
final localStorageProvider = Provider<LocalStorage>((ref) {
  return SqliteLocalStorage();
});

/// 项目仓库 provider。
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(ref.watch(localStorageProvider));
});

/// 项目列表 provider（FutureProvider，可 invalidate 刷新）。
final projectListProvider =
    FutureProvider<List<ProjectSummary>>((ref) async {
  final repo = ref.watch(projectRepositoryProvider);
  return repo.listProjects();
});

/// 当前打开的项目（null 表示未打开任何项目）。
final currentProjectProvider = StateProvider<Project?>((ref) => null);

/// 当前所在编辑器段（默认函数段）。
final currentSegmentProvider =
    StateProvider<EditorSegment>((ref) => EditorSegment.functions);
