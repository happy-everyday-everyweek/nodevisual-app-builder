import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/models/project.dart';
import '../../data/repositories/project_repository.dart';
import '../publish/github_publisher.dart';
import 'project_marketplace_entry.dart';

/// 项目市场客户端。
///
/// 负责从市场仓库拉取项目索引（projects.json），以及从项目源仓库
/// 下载 ir.json 并克隆为本地项目。同时支持将本地已发布项目作为
/// 条目提交到市场仓库（通过 fork + PR 流程）。
///
/// 与 [MarketplaceClient]（插件市场客户端）平行存在，但服务于项目分发：
/// - [fetchIndex]：拉取 projects.json 索引；
/// - [cloneProject]：从 GitHub 仓库下载 ir.json，导入为本地项目；
/// - [publishToMarketplace]：将项目条目提交到市场仓库（fork + PR）。
class ProjectMarketplaceClient {
  ProjectMarketplaceClient({
    String? projectsIndexRawUrl,
    String? marketplaceRepoOwner,
    String? marketplaceRepoName,
    http.Client? httpClient,
  })  : _projectsIndexRawUrl = projectsIndexRawUrl ??
            _kDefaultProjectsIndexRawUrl,
        _marketplaceRepoOwner =
            marketplaceRepoOwner ?? _kDefaultMarketplaceRepoOwner,
        _marketplaceRepoName =
            marketplaceRepoName ?? _kDefaultMarketplaceRepoName,
        _httpClient = httpClient ?? http.Client();

  /// 默认项目市场索引 raw URL（指向 marketplace 仓库的 projects.json）。
  static const String _kDefaultProjectsIndexRawUrl =
      'https://raw.githubusercontent.com/happy-everyday-everyweek/'
      'nodevisual-plugin-marketplace/main/projects.json';

  /// 默认 marketplace 仓库 owner。
  static const String _kDefaultMarketplaceRepoOwner =
      'happy-everyday-everyweek';

  /// 默认 marketplace 仓库 name。
  static const String _kDefaultMarketplaceRepoName =
      'nodevisual-plugin-marketplace';

  final String _projectsIndexRawUrl;
  final String _marketplaceRepoOwner;
  final String _marketplaceRepoName;
  final http.Client _httpClient;

  static const Uuid _uuid = Uuid();

  /// 拉取项目市场索引。
  ///
  /// 网络错误或非 200 响应时返回空索引（而非抛出），调用方据空状态显示对应 UI。
  /// 失败原因会输出到日志，便于排查 CORS / 404 / 网络问题。
  Future<ProjectMarketplaceIndex> fetchIndex() async {
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _httpClient.get(Uri.parse(_projectsIndexRawUrl));
        if (response.statusCode == 200) {
          return ProjectMarketplaceIndex.parse(response.body);
        }
        developer.log(
          'projects.json 请求失败 (attempt $attempt): '
          '${response.statusCode} ${response.reasonPhrase}',
          name: 'ProjectMarketplaceClient',
        );
      } catch (e, st) {
        developer.log(
          '拉取 projects.json 失败 (attempt $attempt): $e',
          name: 'ProjectMarketplaceClient',
          error: e,
          stackTrace: st,
        );
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return const ProjectMarketplaceIndex();
  }

  /// 从 GitHub 仓库克隆项目到本地。
  ///
  /// 流程：
  /// 1. 从 `raw.githubusercontent.com/{owner}/{repo}/{branch}/ir.json`
  ///    下载项目 IR 快照；
  /// 2. 解析为 [Project]，重置 id 与时间戳（作为新本地项目）；
  /// 3. 通过 [ProjectRepository] 保存到本地存储；
  /// 4. 返回新创建的本地项目。
  ///
  /// [entry] 为项目市场条目，提供 repoUrl / branch 等信息。
  /// 失败时抛出异常（由调用方捕获并提示用户）。
  Future<Project> cloneProject(
    ProjectMarketplaceEntry entry,
    ProjectRepository repo,
  ) async {
    final repoInfo = _parseGitHubRepo(entry.repoUrl);
    if (repoInfo == null) {
      throw Exception('无法解析仓库地址: ${entry.repoUrl}');
    }

    final rawUrl =
        'https://raw.githubusercontent.com/${repoInfo.owner}/${repoInfo.repo}/'
        '${entry.branch}/ir.json';

    final response = await _httpClient.get(Uri.parse(rawUrl));
    if (response.statusCode != 200) {
      throw Exception('下载项目 IR 失败 (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('ir.json 格式错误');
    }

    final project = Project.fromJson(decoded);
    // 重置 id 与时间戳，作为新本地项目（避免与原项目冲突）。
    final now = DateTime.now().toIso8601String();
    final newId = _uuid.v4();
    final localProject = project.copyWith(
      meta: project.meta.copyWith(
        id: newId,
        createdAt: now,
        updatedAt: now,
        // 保留 githubRepoUrl 用于后续 pull 更新。
      ),
    );
    await repo.saveProject(localProject);
    return localProject;
  }

  /// 解析 GitHub 仓库 URL，提取 owner / repo。
  _GitHubRepo? _parseGitHubRepo(String url) {
    final match = RegExp(r'github\.com/([^/]+)/([^/]+)/?').firstMatch(url);
    if (match != null) {
      return _GitHubRepo(
        owner: match.group(1)!,
        repo: match.group(2)!.replaceAll('.git', ''),
      );
    }
    return null;
  }

  /// 将已发布项目作为条目提交到市场仓库（fork + PR 流程）。
  ///
  /// 前置条件：项目已经发布到 GitHub（[Project.meta.githubRepoUrl] 非空，
  /// 且仓库 main 分支根目录有 ir.json）。
  ///
  /// 流程：
  /// 1. 使用 [publisher]（已认证）fork 上游 marketplace 仓库到用户命名空间；
  /// 2. 从 fork 读取现有 projects.json（不存在则视为空索引）；
  /// 3. 追加或更新当前项目条目（以 `owner/repo` 为 id 去重）；
  /// 4. 在 fork 创建新分支 `add-{repo}-{semver}`，push 更新后的 projects.json；
  /// 5. 从 fork 分支向上游 main 创建 PR，返回 PR URL。
  ///
  /// [entry] 为要发布的项目市场条目（由调用方根据项目元数据构造）。
  /// [publisher] 为已认证的 GitHub 发布器（需 access_token）。
  /// [userLogin] 为当前 GitHub 用户 login（用于构造 PR head `user:branch`）。
  ///
  /// 返回创建的 PR URL。
  Future<String> publishToMarketplace({
    required ProjectMarketplaceEntry entry,
    required GithubPublisher publisher,
    required String userLogin,
  }) async {
    // 1. Fork marketplace 仓库。
    final forkFullName = await publisher.forkRepo(
      owner: _marketplaceRepoOwner,
      repo: _marketplaceRepoName,
    );
    // forkFullName 形如 `user/nodevisual-plugin-marketplace`。
    final forkOwner = forkFullName.split('/').first;

    // 等待 fork 完成初始化（fork 是异步操作，立即读取可能 404）。
    // 简单重试：最多 5 次，每次间隔 2 秒。
    String? existingJson;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        existingJson = await publisher.getFileContent(
          owner: forkOwner,
          repo: _marketplaceRepoName,
          path: 'projects.json',
          branch: 'main',
        );
        break;
      } on GithubPublisherException {
        // fork 尚未就绪，等待后重试。
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    // 2. 解析现有索引并更新条目。
    ProjectMarketplaceIndex index;
    if (existingJson != null && existingJson.isNotEmpty) {
      try {
        index = ProjectMarketplaceIndex.parse(existingJson);
      } on FormatException {
        // 索引格式错误时，重建空索引（避免阻塞发布）。
        index = const ProjectMarketplaceIndex();
      }
    } else {
      index = const ProjectMarketplaceIndex();
    }

    // 以 id 去重：已存在则替换，否则追加。
    final entries = [...index.projects.where((e) => e.id != entry.id), entry];
    final updatedIndex = ProjectMarketplaceIndex(
      version: index.version,
      name: index.name,
      projects: entries,
    );
    const encoder = JsonEncoder.withIndent('  ');
    final updatedJson = encoder.convert(updatedIndex.toJson());

    // 3. 在 fork 创建新分支并 push projects.json。
    //    分支名：add-{repo}-{semver}（避免与已有 PR 冲突）。
    final repoInfo = _parseGitHubRepo(entry.repoUrl);
    final branchName = 'add-${repoInfo?.repo ?? entry.id}-${entry.version}'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-')
        .toLowerCase();

    await publisher.pushFiles(
      owner: forkOwner,
      repo: _marketplaceRepoName,
      branch: branchName,
      commitMessage: 'chore: 添加/更新项目 ${entry.name} v${entry.version}',
      files: {'projects.json': updatedJson},
    );

    // 4. 创建 PR：fork 分支 → 上游 main。
    final prUrl = await publisher.createPullRequest(
      owner: _marketplaceRepoOwner,
      repo: _marketplaceRepoName,
      head: '$forkOwner:$branchName',
      base: 'main',
      title: '项目: ${entry.name} v${entry.version}',
      body: '## 项目信息\n\n'
          '- **名称**：${entry.name}\n'
          '- **作者**：${entry.author}\n'
          '- **版本**：v${entry.version}\n'
          '- **源仓库**：${entry.repoUrl}\n'
          '- **描述**：${entry.description.isEmpty ? "（无）" : entry.description}\n\n'
          '## 说明\n\n'
          '此 PR 由 NodeVisual 应用自动生成，将项目发布到市场。\n'
          '合并后其他用户可在市场"项目"栏目克隆本项目。',
    );

    return prUrl;
  }

  void dispose() {
    _httpClient.close();
  }
}

/// GitHub 仓库信息。
class _GitHubRepo {
  final String owner;
  final String repo;
  const _GitHubRepo({required this.owner, required this.repo});
}
