import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../models/project.dart';
import 'local_storage.dart';

/// 基于 [SharedPreferences] 的 [LocalStorage] 实现（Web 平台）。
///
/// Web 平台不支持 [sqflite] 与 [path_provider]，改用 [SharedPreferences]
/// （底层 localStorage）存储项目元数据索引与项目快照 JSON。
///
/// 数据布局（与 [SqliteLocalStorage] 语义对齐）：
/// - `web.projects.index`：JSON 数组，每项为 [ProjectMeta] 序列化。
/// - `web.project.<id>`：单个 [Project] 完整快照 JSON。
/// - `prefKeyLastProjectId`：最近打开项目 id（复用 [AppConstants] 键）。
class SharedPreferencesLocalStorage implements LocalStorage {
  SharedPreferencesLocalStorage();

  static const String _indexKey = 'web.projects.index';
  static const String _projectKeyPrefix = 'web.project.';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _projectKey(String id) => '$_projectKeyPrefix$id';

  Future<List<ProjectMeta>> _readIndex() async {
    final prefs = await _sp();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ProjectMeta.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeIndex(List<ProjectMeta> metas) async {
    final prefs = await _sp();
    final encoded =
        jsonEncode(metas.map((m) => m.toJson()).toList());
    await prefs.setString(_indexKey, encoded);
  }

  @override
  Future<void> init() async {
    await _sp();
  }

  @override
  Future<List<ProjectMeta>> listProjects() async {
    final metas = await _readIndex();
    metas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return metas;
  }

  @override
  Future<Project?> loadProject(String projectId) async {
    final prefs = await _sp();
    final raw = prefs.getString(_projectKey(projectId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return Project.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveProject(Project project) async {
    final prefs = await _sp();
    // 写入快照
    await prefs.setString(
      _projectKey(project.meta.id),
      jsonEncode(project.toJson()),
    );
    // 更新索引（upsert）
    final metas = await _readIndex();
    final idx = metas.indexWhere((m) => m.id == project.meta.id);
    if (idx >= 0) {
      metas[idx] = project.meta;
    } else {
      metas.add(project.meta);
    }
    await _writeIndex(metas);
  }

  @override
  Future<void> deleteProject(String projectId) async {
    final prefs = await _sp();
    await prefs.remove(_projectKey(projectId));
    final metas = await _readIndex();
    metas.removeWhere((m) => m.id == projectId);
    await _writeIndex(metas);
  }

  @override
  Future<String?> getLastProjectId() async {
    final prefs = await _sp();
    return prefs.getString(AppConstants.prefKeyLastProjectId);
  }

  @override
  Future<void> setLastProjectId(String? id) async {
    final prefs = await _sp();
    if (id == null) {
      await prefs.remove(AppConstants.prefKeyLastProjectId);
    } else {
      await prefs.setString(AppConstants.prefKeyLastProjectId, id);
    }
  }
}
