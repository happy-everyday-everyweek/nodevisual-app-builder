import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// GitHub 发布器：负责创建仓库、推送文件、创建 tag 与 Release。
///
/// 通过 GitHub REST API + Git Database API 实现（无需本地 git）：
/// 1. 创建仓库（首次）/ 复用现有仓库（后续）。
/// 2. 推送 main 分支：IR JSON + README.md（用户仓库的"源代码"）。
/// 3. 推送 gh-pages 分支：Web 构建产物（直接作为 GitHub Pages 源）。
/// 4. 创建 tag `v<semver>` 与 GitHub Release，APK / Windows 产物作为附件。
///
/// **认证**：通过 Device Flow 获取的 access_token（Bearer）。
/// **权限**：scope 为 `repo workflow`，可读写仓库、workflow。
class GithubPublisher {
  GithubPublisher({required this.accessToken});

  final String accessToken;

  static const String _apiBase = 'https://api.github.com';
  static const String _uploadBase = 'https://uploads.github.com';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// 获取当前授权用户信息。
  Future<GithubUser> getCurrentUser() async {
    final resp = await http.get(Uri.parse('$_apiBase/user'), headers: _headers);
    if (resp.statusCode != 200) {
      throw GithubPublisherException('获取用户信息失败：${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return GithubUser(
      login: json['login'] as String,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  /// 创建新仓库（公开）。返回仓库 HTML URL。
  ///
  /// 仓库名规则：slugify(projectName)，转小写、替换非法字符为 '-'。
  Future<String> createRepo({
    required String name,
    String? description,
  }) async {
    final slug = _slugify(name);
    final resp = await http.post(
      Uri.parse('$_apiBase/user/repos'),
      headers: _headers,
      body: jsonEncode({
        'name': slug,
        'description': description ?? 'NodeVisual 项目：$name',
        'private': false,
        'auto_init': true, // 自动初始化 README，便于首次提交有 base
        'has_issues': true,
        'has_pages': true,
      }),
    );
    if (resp.statusCode != 201) {
      throw GithubPublisherException('创建仓库失败：${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['html_url'] as String;
  }

  /// 推送文件到指定分支（覆盖同名文件，保留其他文件）。
  ///
  /// [files]：路径 → 内容（UTF-8 字符串）。空 map 会创建空提交（仅初始化分支）。
  /// [branch]：目标分支名（如 main / gh-pages）。
  /// [commitMessage]：提交信息。
  /// [orphan]：true 表示创建孤儿分支（与现有历史无关，用于 gh-pages）。
  ///
  /// 返回 commit SHA。
  Future<String> pushFiles({
    required String owner,
    required String repo,
    required String branch,
    required String commitMessage,
    required Map<String, String> files,
    bool orphan = false,
  }) async {
    // 1. 获取分支 HEAD commit SHA（若分支不存在则从默认分支创建）。
    String? parentSha;
    String? baseTreeSha;
    if (!orphan) {
      final refResp = await http.get(
        Uri.parse('$_apiBase/repos/$owner/$repo/git/refs/heads/$branch'),
        headers: _headers,
      );
      if (refResp.statusCode == 200) {
        final refJson = jsonDecode(refResp.body) as Map<String, dynamic>;
        parentSha = refJson['object']['sha'] as String;
        final commitResp = await http.get(
          Uri.parse('$_apiBase/repos/$owner/$repo/git/commits/$parentSha'),
          headers: _headers,
        );
        final commitJson = jsonDecode(commitResp.body) as Map<String, dynamic>;
        baseTreeSha = commitJson['tree']['sha'] as String;
      }
    }

    // 2. 为每个文件创建 blob。
    final treeEntries = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      final blobResp = await http.post(
        Uri.parse('$_apiBase/repos/$owner/$repo/git/blobs'),
        headers: _headers,
        body: jsonEncode({
          'content': entry.value,
          'encoding': 'utf-8',
        }),
      );
      if (blobResp.statusCode != 201) {
        throw GithubPublisherException(
            '创建 blob 失败（${entry.key}）：${blobResp.statusCode} ${blobResp.body}');
      }
      final blobJson = jsonDecode(blobResp.body) as Map<String, dynamic>;
      treeEntries.add({
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': blobJson['sha'],
      });
    }

    // 3. 创建 tree（base_tree 用于追加/覆盖；无 base_tree 用于孤儿/初次）。
    final treeBody = <String, dynamic>{
      'tree': treeEntries,
    };
    if (baseTreeSha != null) {
      treeBody['base_tree'] = baseTreeSha;
    }
    final treeResp = await http.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/git/trees'),
      headers: _headers,
      body: jsonEncode(treeBody),
    );
    if (treeResp.statusCode != 201) {
      throw GithubPublisherException(
          '创建 tree 失败：${treeResp.statusCode} ${treeResp.body}');
    }
    final treeJson = jsonDecode(treeResp.body) as Map<String, dynamic>;
    final treeSha = treeJson['sha'] as String;

    // 4. 创建 commit。
    final commitBody = <String, dynamic>{
      'message': commitMessage,
      'tree': treeSha,
    };
    if (parentSha != null) {
      commitBody['parents'] = [parentSha];
    }
    final commitResp = await http.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/git/commits'),
      headers: _headers,
      body: jsonEncode(commitBody),
    );
    if (commitResp.statusCode != 201) {
      throw GithubPublisherException(
          '创建 commit 失败：${commitResp.statusCode} ${commitResp.body}');
    }
    final commitJson = jsonDecode(commitResp.body) as Map<String, dynamic>;
    final newCommitSha = commitJson['sha'] as String;

    // 5. 创建/更新分支 ref 指向新 commit。
    final refResp = await http.put(
      Uri.parse('$_apiBase/repos/$owner/$repo/git/refs/heads/$branch'),
      headers: _headers,
      body: jsonEncode({'sha': newCommitSha}),
    );
    if (refResp.statusCode != 200 && refResp.statusCode != 201) {
      throw GithubPublisherException(
          '更新分支 ref 失败：${refResp.statusCode} ${refResp.body}');
    }

    return newCommitSha;
  }

  /// 创建 git tag + GitHub Release，并将产物作为附件上传。
  ///
  /// [commitSha]：tag 指向的 commit SHA。
  /// [artifacts]：附件列表（文件名 → 二进制内容 + MIME 类型）。
  ///
  /// 返回 Release HTML URL。
  Future<String> createRelease({
    required String owner,
    required String repo,
    required String semver,
    required String commitSha,
    String? releaseNotes,
    List<GithubReleaseAsset> artifacts = const [],
  }) async {
    final tagName = 'v$semver';

    // 1. 创建 tag object。
    final tagResp = await http.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/git/tags'),
      headers: _headers,
      body: jsonEncode({
        'tag': tagName,
        'message': releaseNotes ?? 'Release $tagName',
        'object': commitSha,
        'type': 'commit',
      }),
    );
    if (tagResp.statusCode != 201) {
      throw GithubPublisherException(
          '创建 tag 失败：${tagResp.statusCode} ${tagResp.body}');
    }
    final tagJson = jsonDecode(tagResp.body) as Map<String, dynamic>;
    final tagSha = tagJson['sha'] as String;

    // 2. 创建 tag ref（refs/tags/v<semver>）。
    final refResp = await http.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/git/refs'),
      headers: _headers,
      body: jsonEncode({
        'ref': 'refs/tags/$tagName',
        'sha': tagSha,
      }),
    );
    if (refResp.statusCode != 201) {
      // 已存在 tag 时 ref 创建会失败，可忽略（继续创建 release）。
    }

    // 3. 创建 GitHub Release。
    final releaseResp = await http.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/releases'),
      headers: _headers,
      body: jsonEncode({
        'tag_name': tagName,
        'target_commitish': commitSha,
        'name': tagName,
        'body': releaseNotes ?? 'NodeVisual 项目 $tagName 发布',
        'draft': false,
        'prerelease': false,
      }),
    );
    if (releaseResp.statusCode != 201) {
      throw GithubPublisherException(
          '创建 Release 失败：${releaseResp.statusCode} ${releaseResp.body}');
    }
    final releaseJson = jsonDecode(releaseResp.body) as Map<String, dynamic>;
    final releaseId = releaseJson['id'] as int;
    final releaseUrl = releaseJson['html_url'] as String;

    // 4. 上传附件（APK / Windows 产物）。
    for (final asset in artifacts) {
      await _uploadAsset(
        owner: owner,
        repo: repo,
        releaseId: releaseId,
        asset: asset,
      );
    }

    return releaseUrl;
  }

  /// 上传单个 Release 附件。
  Future<void> _uploadAsset({
    required String owner,
    required String repo,
    required int releaseId,
    required GithubReleaseAsset asset,
  }) async {
    final uri = Uri.parse(
      '$_uploadBase/repos/$owner/$repo/releases/$releaseId/assets'
      '?name=${Uri.encodeQueryComponent(asset.name)}',
    );
    final resp = await http.post(
      uri,
      headers: {
        ..._headers,
        'Content-Type': asset.contentType,
      },
      body: asset.bytes,
    );
    if (resp.statusCode != 201) {
      throw GithubPublisherException(
          '上传附件 ${asset.name} 失败：${resp.statusCode} ${resp.body}');
    }
  }

  /// Fork 一个仓库到当前用户命名空间。
  ///
  /// 用于"发布到市场"流程：用户 fork marketplace 仓库，在自己的 fork 中
  /// 修改 projects.json，再向上游创建 PR。
  ///
  /// [owner] / [repo]：上游仓库的 owner / repo。
  /// 返回 fork 后的仓库全名 `user/repo`（同名时 GitHub 不报错，复用已有 fork）。
  Future<String> forkRepo({
    required String owner,
    required String repo,
  }) async {
    final resp = await http.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/forks'),
      headers: _headers,
    );
    // 202 表示 fork 已创建；200 表示已存在 fork（GitHub 复用）。
    if (resp.statusCode != 202 && resp.statusCode != 200) {
      throw GithubPublisherException(
          'Fork 仓库失败：${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['full_name'] as String;
  }

  /// 创建 Pull Request。
  ///
  /// [owner] / [repo]：目标（上游）仓库。
  /// [head]：PR 来源分支，格式 `user:branch`（跨 fork 时需带 user 前缀）。
  /// [base]：目标分支（上游仓库的分支名）。
  Future<String> createPullRequest({
    required String owner,
    required String repo,
    required String head,
    required String base,
    required String title,
    required String body,
  }) async {
    final resp = await http.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/pulls'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'body': body,
        'head': head,
        'base': base,
        'maintainer_can_modify': true,
      }),
    );
    if (resp.statusCode != 201) {
      throw GithubPublisherException(
          '创建 PR 失败：${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['html_url'] as String;
  }

  /// 获取仓库中某文件的内容（默认分支）。
  ///
  /// 用于"发布到市场"流程：读取上游 marketplace 仓库的 projects.json，
  /// 解析后追加/更新当前项目条目，再 push 到 fork。
  ///
  /// 文件不存在时返回 null（首次发布到空市场）。
  Future<String?> getFileContent({
    required String owner,
    required String repo,
    required String path,
    String branch = 'main',
  }) async {
    final resp = await http.get(
      Uri.parse('$_apiBase/repos/$owner/$repo/contents/$path?ref=$branch'),
      headers: _headers,
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw GithubPublisherException(
          '获取文件 $path 失败：${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    // contents API 返回 base64 编码的内容。
    final encoding = json['encoding'] as String?;
    final content = json['content'] as String;
    if (encoding == 'base64') {
      // base64 解码为 UTF-8 字符串。
      final bytes = base64.decode(content.replaceAll(RegExp(r'\s'), ''));
      return utf8.decode(bytes);
    }
    return content;
  }

  /// 将项目名转为合法 GitHub 仓库名 slug。
  ///
  /// 规则：小写化 → 非字母数字字符替换为 '-' → 合并连续 '-' → 去除首尾 '-'。
  /// 若结果为空，返回 'nodevisual-project'。
  String _slugify(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceFirst(RegExp(r'^-+'), '')
        .replaceFirst(RegExp(r'-+$'), '');
    return slug.isEmpty ? 'nodevisual-project' : slug;
  }
}

/// GitHub 用户信息。
class GithubUser {
  const GithubUser({
    required this.login,
    this.name,
    this.avatarUrl,
  });

  final String login;
  final String? name;
  final String? avatarUrl;
}

/// Release 附件。
class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final String contentType;
}

/// Publisher 异常。
class GithubPublisherException implements Exception {
  const GithubPublisherException(this.message);
  final String message;

  @override
  String toString() => 'GithubPublisherException: $message';
}
