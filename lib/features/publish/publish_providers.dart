import 'dart:convert';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/project.dart';
import '../../data/models/project_version.dart';
import '../build_pipeline/build_artifact.dart';
import '../build_pipeline/build_target.dart';
import '../build_pipeline/builders/web_runtime_template.dart';
import '../project/project_providers.dart';
import 'artifact_bytes.dart';
import 'github_device_flow.dart';
import 'github_publisher.dart';

/// GitHub 认证状态机。
sealed class GithubAuthState {
  const GithubAuthState();
}

/// 未授权。
class GithubAuthIdle extends GithubAuthState {
  const GithubAuthIdle();
}

/// 授权中（等待用户在浏览器输入 user_code）。
class GithubAuthPending extends GithubAuthState {
  const GithubAuthPending({
    required this.userCode,
    required this.verificationUri,
  });

  /// 用户在浏览器输入的 8 位 code。
  final String userCode;

  /// 授权页 URL。
  final String verificationUri;
}

/// 授权成功（已获取 access_token）。
class GithubAuthAuthenticated extends GithubAuthState {
  const GithubAuthAuthenticated({
    required this.accessToken,
    required this.user,
  });

  final String accessToken;
  final GithubUser user;
}

/// 授权失败。
class GithubAuthError extends GithubAuthState {
  const GithubAuthError(this.message);
  final String message;
}

/// GitHub 认证状态控制器。
///
/// access_token 仅保存在内存（StateNotifier 实例），不写入 SharedPreferences
/// 或 SQLite，避免持久化敏感凭证。每次 App 重启需重新授权。
final githubAuthProvider =
    StateNotifierProvider<GithubAuthNotifier, GithubAuthState>(
  (ref) => GithubAuthNotifier(),
);

class GithubAuthNotifier extends StateNotifier<GithubAuthState> {
  GithubAuthNotifier() : super(const GithubAuthIdle());

  final GithubDeviceFlow _flow = GithubDeviceFlow();

  /// 发起 Device Flow 授权。
  ///
  /// 流程：
  /// 1. 申请 device_code，更新为 [GithubAuthPending]（UI 显示 user_code 并
  ///    自动打开浏览器到 verification_uri）；
  /// 2. 轮询 token，成功后获取用户信息并更新为 [GithubAuthAuthenticated]。
  Future<void> signIn() async {
    try {
      final token = await _flow.authenticate(
        onDeviceCode: (dc) {
          state = GithubAuthPending(
            userCode: dc.userCode,
            verificationUri: dc.verificationUri,
          );
          // 自动打开浏览器。
          launchUrl(Uri.parse(dc.verificationUri));
        },
      );
      final publisher = GithubPublisher(accessToken: token);
      final user = await publisher.getCurrentUser();
      state = GithubAuthAuthenticated(accessToken: token, user: user);
    } on GithubDeviceFlowException catch (e) {
      state = GithubAuthError(e.message);
    } catch (e) {
      state = GithubAuthError('授权失败：$e');
    }
  }

  /// 取消授权（用户主动取消或失败重试）。
  void reset() {
    state = const GithubAuthIdle();
  }

  /// 登出（清除 token）。
  void signOut() {
    state = const GithubAuthIdle();
  }
}

/// 项目版本历史 provider（按发布时间倒序）。
///
/// 通过 invalidate 刷新（发布成功后调用）。
final projectVersionsProvider =
    FutureProvider.family<List<ProjectVersion>, String>(
  (ref, projectId) async {
    final repo = ref.watch(projectRepositoryProvider);
    return repo.listVersions(projectId);
  },
);

/// 发布状态机。
sealed class PublishState {
  const PublishState();
}

class PublishIdle extends PublishState {
  const PublishIdle();
}

class PublishRunning extends PublishState {
  const PublishRunning(this.phase, this.message);
  final String phase;
  final String message;
}

class PublishDone extends PublishState {
  const PublishDone({
    required this.releaseUrl,
    required this.repoUrl,
    required this.version,
  });
  final String releaseUrl;
  final String repoUrl;
  final ProjectVersion version;
}

class PublishError extends PublishState {
  const PublishError(this.message);
  final String message;
}

/// 发布编排控制器。
///
/// 协调：构建产物 → 创建仓库 / push → 创建 tag + Release → 落盘版本历史。
final publishStateProvider =
    StateNotifierProvider<PublishNotifier, PublishState>(
  (ref) => PublishNotifier(ref),
);

class PublishNotifier extends StateNotifier<PublishState> {
  PublishNotifier(this._ref) : super(const PublishIdle());

  final Ref _ref;

  /// 执行发布。
  ///
  /// [semver] 用户确认的版本号（应当 > 当前 meta.semver）。
  /// [releaseNotes] 发布说明。
  /// [artifacts] 步骤 1 构建的产物（用于 Release 附件上传）。
  Future<void> publish({
    required String semver,
    String? releaseNotes,
    required List<BuildArtifact> artifacts,
  }) async {
    final auth = _ref.read(githubAuthProvider);
    if (auth is! GithubAuthAuthenticated) {
      state = const PublishError('请先连接 GitHub 账号');
      return;
    }
    final project = _ref.read(currentProjectProvider);
    if (project == null) {
      state = const PublishError('未加载项目');
      return;
    }

    state = const PublishRunning('准备', '正在准备发布资源...');
    try {
      final publisher = GithubPublisher(accessToken: auth.accessToken);
      final owner = auth.user.login;

      // 1. 仓库：首次新建，后续复用。
      String repoUrl;
      String repoName;
      if (project.meta.githubRepoUrl != null) {
        repoUrl = project.meta.githubRepoUrl!;
        repoName = _repoNameFromUrl(repoUrl);
      } else {
        state = const PublishRunning('创建仓库', '正在创建 GitHub 仓库...');
        repoUrl = await publisher.createRepo(
          name: project.meta.name,
          description: project.meta.description,
        );
        repoName = _repoNameFromUrl(repoUrl);
      }

      // 2. 推送 main 分支：IR + README。
      state = const PublishRunning('推送源代码', '正在推送 main 分支...');
      final irJson = const JsonEncoder.withIndent('  ').convert(project.toJson());
      final readme = _generateReadme(project, semver);
      final mainCommitSha = await publisher.pushFiles(
        owner: owner,
        repo: repoName,
        branch: 'main',
        commitMessage: 'chore: 发布 v$semver',
        files: {
          'ir.json': irJson,
          'README.md': readme,
        },
      );

      // 3. 推送 gh-pages 分支：Web 构建产物（孤儿分支，与 main 独立）。
      //    Web 文件直接由 WebRuntimeTemplate 生成（与 WebBuilder 内部一致），
      //    保证 gh-pages 部署的 Web 与本地构建产物完全一致。
      state = const PublishRunning('部署 Web', '正在推送 gh-pages 分支...');
      final webFiles = _generateWebFiles(project);
      await publisher.pushFiles(
        owner: owner,
        repo: repoName,
        branch: 'gh-pages',
        commitMessage: 'deploy: Web 构建产物 v$semver',
        files: webFiles,
        orphan: true,
      );

      // 4. 创建 tag + Release，上传 APK / Windows 产物。
      //    Web 产物不作为 Release 附件（已通过 gh-pages 部署）。
      state = const PublishRunning('创建 Release', '正在创建 GitHub Release...');
      final releaseAssets = <GithubReleaseAsset>[];
      for (final a in artifacts) {
        if (a.target == BuildTarget.web) continue; // Web 已部署到 Pages
        final bytes = await _readArtifactBytes(a);
        if (bytes == null) continue;
        releaseAssets.add(GithubReleaseAsset(
          name: a.displayName,
          bytes: bytes,
          contentType: 'application/octet-stream',
        ));
      }
      final releaseUrl = await publisher.createRelease(
        owner: owner,
        repo: repoName,
        semver: semver,
        commitSha: mainCommitSha,
        releaseNotes: releaseNotes,
        artifacts: releaseAssets,
      );

      // 5. 落盘版本历史 + 更新 ProjectMeta。
      final now = DateTime.now().toIso8601String();
      final version = ProjectVersion(
        projectId: project.meta.id,
        semver: semver,
        publishedAt: now,
        commitSha: mainCommitSha,
        releaseUrl: releaseUrl,
        githubRepoUrl: repoUrl,
        notes: releaseNotes,
      );
      final repo = _ref.read(projectRepositoryProvider);
      await repo.saveVersion(version);

      // 更新项目元数据：semver + githubRepoUrl。
      final updatedProject = project.copyWith(
        meta: project.meta.copyWith(
          semver: semver,
          githubRepoUrl: repoUrl,
        ),
      );
      await repo.saveProject(updatedProject);
      _ref.read(currentProjectProvider.notifier).state = updatedProject;
      _ref.invalidate(projectVersionsProvider);

      state = PublishDone(
        releaseUrl: releaseUrl,
        repoUrl: repoUrl,
        version: version,
      );
    } catch (e) {
      state = PublishError('发布失败：$e');
    }
  }

  void reset() {
    state = const PublishIdle();
  }

  /// 读取产物字节（兼容内存产物与文件系统产物）。
  ///
  /// 内存产物（Web 平台）：直接返回 [BuildArtifact.bytes]。
  /// 文件产物（Android/Windows）：通过跨端 helper 读取文件（Web 平台
  /// 该路径返回 null）。
  Future<Uint8List?> _readArtifactBytes(BuildArtifact a) async {
    if (a.bytes != null) return a.bytes;
    if (a.path.startsWith('memory:')) return null;
    return readArtifactFileBytes(a.path);
  }

  /// 生成 gh-pages 分支的 Web 文件 map。
  ///
  /// 与 [WebBuilder.build] 内部生成的文件一致：
  /// - index.html / runtime.js / ir.json / manifest.json / README.md
  Map<String, String> _generateWebFiles(Project project) {
    return {
      'index.html': WebRuntimeTemplate.indexHtml(project.meta.name),
      'runtime.js': WebRuntimeTemplate.runtimeJs(),
      'ir.json': const JsonEncoder.withIndent('  ').convert(project.toJson()),
      'README.md': WebRuntimeTemplate.readmeMd(project.meta.name),
    };
  }

  /// 从 GitHub 仓库 URL 提取仓库名。
  ///
  /// 形如 `https://github.com/owner/repo` → `repo`。
  String _repoNameFromUrl(String url) {
    final parts = Uri.parse(url).pathSegments;
    return parts.isNotEmpty ? parts.last : '';
  }

  /// 生成仓库 README 内容。
  String _generateReadme(Project project, String semver) {
    final buf = StringBuffer();
    buf.writeln('# ${project.meta.name}');
    buf.writeln();
    if (project.meta.description != null &&
        project.meta.description!.isNotEmpty) {
      buf.writeln(project.meta.description);
      buf.writeln();
    }
    buf.writeln('## 版本');
    buf.writeln();
    buf.writeln('当前版本：**v$semver**');
    buf.writeln();
    buf.writeln('## 在线访问');
    buf.writeln();
    buf.writeln('Web 版本已部署到 GitHub Pages：');
    buf.writeln('打开仓库 Settings → Pages，Source 选择 `gh-pages` 分支，'
        '保存后稍候片刻即可通过 '
        '`https://<owner>.github.io/<repo>/` 访问。');
    buf.writeln();
    buf.writeln('## 移动端 / 桌面端下载');
    buf.writeln();
    buf.writeln('Android（.nvapk）/ Windows（.nvexe）产物请前往 '
        '[Releases](../../releases) 下载，'
        '由 NodeVisual Runner 应用运行。');
    buf.writeln();
    buf.writeln('---');
    buf.writeln('由 NodeVisual App Builder 生成。');
    return buf.toString();
  }
}
