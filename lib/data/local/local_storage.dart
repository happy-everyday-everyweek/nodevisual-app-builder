import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../models/project.dart';

/// 本地存储抽象（SQLite 索引 + 文件系统项目快照）。
///
/// 职责划分：
/// - **SQLite**：保存项目元数据（[ProjectMeta]）索引，便于列表展示与检索。
/// - **文件系统**：保存完整 [Project] JSON 快照（按项目 id 命名）。
/// - **SharedPreferences**：记录最近打开的项目 id 等轻量偏好。
///
/// Task 1 阶段提供接口与基础实现骨架，后续 Task 将补充迁移、
/// 增量保存与冲突处理逻辑。
abstract class LocalStorage {
  /// 初始化底层资源（打开数据库、创建目录与表）。
  Future<void> init();

  /// 列出所有项目元数据。
  Future<List<ProjectMeta>> listProjects();

  /// 加载完整项目快照；不存在返回 null。
  Future<Project?> loadProject(String projectId);

  /// 保存项目（同时更新元数据索引与文件快照）。
  Future<void> saveProject(Project project);

  /// 删除项目（元数据 + 文件快照）。
  Future<void> deleteProject(String projectId);

  /// 读取最近打开项目 id。
  Future<String?> getLastProjectId();

  /// 设置最近打开项目 id（null 表示清除）。
  Future<void> setLastProjectId(String? id);
}

/// 基于 [sqflite] + [path_provider] 的 [LocalStorage] 实现。
class SqliteLocalStorage implements LocalStorage {
  SqliteLocalStorage();

  Database? _db;
  String? _projectsDirPath;

  /// 打开数据库句柄（惰性初始化）。
  Future<Database> _database() async {
    if (_db != null) return _db!;
    final docsDir = await getApplicationDocumentsDirectory();
    _projectsDirPath = p.join(docsDir.path, AppConstants.projectsDirName);
    await Directory(_projectsDirPath!).create(recursive: true);
    _db = await openDatabase(
      p.join(docsDir.path, AppConstants.sqliteDbName),
      version: AppConstants.sqliteDbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            version TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// 项目快照文件完整路径。
  Future<String> _projectFilePath(String projectId) async {
    final dir = _projectsDirPath ??
        p.join((await getApplicationDocumentsDirectory()).path,
            AppConstants.projectsDirName);
    if (_projectsDirPath == null) {
      _projectsDirPath = dir;
      await Directory(dir).create(recursive: true);
    }
    return p.join(dir, '$projectId.json');
  }

  @override
  Future<void> init() async {
    await _database();
  }

  @override
  Future<List<ProjectMeta>> listProjects() async {
    final db = await _database();
    final rows = await db.query('projects', orderBy: 'updated_at DESC');
    return rows
        .map((row) => ProjectMeta(
              id: row['id'] as String,
              name: row['name'] as String,
              description: row['description'] as String?,
              createdAt: row['created_at'] as String,
              updatedAt: row['updated_at'] as String,
              version: row['version'] as String,
            ))
        .toList();
  }

  @override
  Future<Project?> loadProject(String projectId) async {
    final path = await _projectFilePath(projectId);
    final file = File(path);
    if (!file.existsSync()) return null;
    final raw = await file.readAsString();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return Project.fromJson(decoded);
  }

  @override
  Future<void> saveProject(Project project) async {
    final db = await _database();
    final meta = project.meta;
    await db.insert(
      'projects',
      {
        'id': meta.id,
        'name': meta.name,
        'description': meta.description,
        'created_at': meta.createdAt,
        'updated_at': meta.updatedAt,
        'version': meta.version,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final path = await _projectFilePath(meta.id);
    final file = File(path);
    await file.writeAsString(jsonEncode(project.toJson()));
  }

  @override
  Future<void> deleteProject(String projectId) async {
    final db = await _database();
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
    final path = await _projectFilePath(projectId);
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<String?> getLastProjectId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.prefKeyLastProjectId);
  }

  @override
  Future<void> setLastProjectId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(AppConstants.prefKeyLastProjectId);
    } else {
      await prefs.setString(AppConstants.prefKeyLastProjectId, id);
    }
  }
}
