import 'package:uuid/uuid.dart';

import '../local/local_storage.dart';
import '../models/project.dart';
import '../models/project_version.dart';

/// 项目列表摘要（轻量信息，仅用于列表展示）。
///
/// 与完整 [Project] 区分：列表页只需要 id、名称与更新时间，
/// 避免一次性加载所有项目快照。
class ProjectSummary {
  /// 项目唯一标识。
  final String id;

  /// 项目名称。
  final String name;

  /// 最近更新时间（ISO8601 字符串）。
  final String updatedAt;

  const ProjectSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  @override
  String toString() => 'ProjectSummary($name#$id)';
}

/// 项目仓库，封装 [LocalStorage] 提供项目级 CRUD 操作。
///
/// 作为领域层与存储层之间的门面：上层（providers/UI）只依赖
/// [ProjectRepository]，不直接接触 [LocalStorage] 细节。
/// v1 阶段项目以单文件快照形式存储（`projects/<id>.json`），
/// 后续可按 spec 拆分为 `project.json + functions/ + db.json + ui.json`。
class ProjectRepository {
  ProjectRepository(this._storage);

  final LocalStorage _storage;
  final Uuid _uuid = const Uuid();

  /// 存储初始化 future（幂等，仅初始化一次）。
  Future<void>? _initFuture;

  /// 确保底层存储已初始化（多次调用安全）。
  Future<void> _ensureInit() {
    _initFuture ??= _storage.init();
    return _initFuture!;
  }

  /// 创建新项目：生成 uuid，初始为空 functions/db/ui，落盘后返回。
  Future<Project> createProject(String name) async {
    await _ensureInit();
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    final project = Project(
      meta: ProjectMeta(id: id, name: name, createdAt: now, updatedAt: now),
    );
    await _storage.saveProject(project);
    await _storage.setLastProjectId(id);
    return project;
  }

  /// 打开（读取）项目；不存在返回 null。
  Future<Project?> openProject(String id) async {
    await _ensureInit();
    final project = await _storage.loadProject(id);
    if (project != null) {
      await _storage.setLastProjectId(id);
    }
    return project;
  }

  /// 保存项目（同时刷新 updatedAt 时间戳并落盘）。
  Future<void> saveProject(Project project) async {
    await _ensureInit();
    final updated = project.copyWith(
      meta: project.meta.copyWith(updatedAt: DateTime.now().toIso8601String()),
    );
    await _storage.saveProject(updated);
  }

  /// 列出所有项目摘要（按 updatedAt 倒序，由存储层保证）。
  Future<List<ProjectSummary>> listProjects() async {
    await _ensureInit();
    final metas = await _storage.listProjects();
    return metas
        .map(
          (m) => ProjectSummary(
            id: m.id,
            name: m.name,
            updatedAt: m.updatedAt,
          ),
        )
        .toList();
  }

  /// 删除项目；若被删除项是最近打开项目，则清除该记录。
  Future<void> deleteProject(String id) async {
    await _ensureInit();
    await _storage.deleteProject(id);
    final lastId = await _storage.getLastProjectId();
    if (lastId == id) {
      await _storage.setLastProjectId(null);
    }
  }

  // ---- 版本管理 ----

  /// 列出指定项目的所有版本历史（按发布时间倒序）。
  Future<List<ProjectVersion>> listVersions(String projectId) async {
    await _ensureInit();
    return _storage.listVersions(projectId);
  }

  /// 追加一条版本发布记录（用于发布成功后落盘）。
  Future<void> saveVersion(ProjectVersion version) async {
    await _ensureInit();
    await _storage.saveVersion(version);
  }
}
