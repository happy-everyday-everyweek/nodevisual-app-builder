import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'built_in_plugins.dart';
import 'marketplace_entry.dart';
import 'plugin_manifest.dart';

/// 插件市场客户端。
///
/// 负责从市场仓库拉取索引（index.json），以及从插件源仓库
/// 下载 plugin.json 清单。所有网络请求通过 GitHub raw / codeload URL 完成。
///
/// 内置插件（OpenAI / Anthropic，repoUrl 以 `builtin://` 开头）的 manifest
/// 直接从 [builtInPluginManifests] 取，无需网络下载。
class MarketplaceClient {
  MarketplaceClient({
    String? marketplaceRawBaseUrl,
    http.Client? httpClient,
  })  : _marketplaceRawBaseUrl = marketplaceRawBaseUrl ??
            _kDefaultMarketplaceRawBase,
        _httpClient = httpClient ?? http.Client();

  /// 默认市场索引 raw URL（指向 marketplace 仓库的 index.json）。
  static const String _kDefaultMarketplaceRawBase =
      'https://raw.githubusercontent.com/happy-everyday-everyweek/'
      'nodevisual-plugin-marketplace/main/index.json';

  final String _marketplaceRawBaseUrl;
  final http.Client _httpClient;

  /// 拉取市场索引（合并远程索引与内置条目）。
  ///
  /// 内置条目（OpenAI / Anthropic）始终追加到结果中，确保用户即使在
  /// 远程索引不可用时也能看到这些插件。若远程索引中已存在同 id 条目，
  /// 内置条目优先（覆盖远程版本）。
  Future<MarketplaceIndex> fetchIndex() async {
    // 先尝试拉取远程索引；失败时降级为仅内置条目。
    List<MarketplaceEntry> remoteEntries = const [];
    try {
      final response = await _httpClient.get(Uri.parse(_marketplaceRawBaseUrl));
      if (response.statusCode == 200) {
        remoteEntries = MarketplaceIndex.parse(response.body).plugins;
      }
    } catch (_) {
      // 网络错误时仅使用内置条目。
    }

    // 合并：远程条目 + 内置条目（同 id 时内置优先）。
    final builtInIds = builtInMarketplaceEntries.map((e) => e.id).toSet();
    final merged = <MarketplaceEntry>[
      ...builtInMarketplaceEntries,
      ...remoteEntries.where((e) => !builtInIds.contains(e.id)),
    ];
    return MarketplaceIndex(
      version: 1,
      name: 'NodeVisual 市场',
      plugins: merged,
    );
  }

  /// 从插件源仓库下载并解析 plugin.json 清单。
  ///
  /// 内置插件（[entry.repoUrl] 以 `builtin://` 开头）直接返回
  /// [builtInPluginManifests] 中的 manifest，无需网络下载。
  /// 其他插件使用 GitHub codeload API 下载仓库 ZIP，解压后读取 plugin.json。
  /// 返回的 [PluginManifest] 带有 sourceRepoUrl 与 installedAt 元信息。
  Future<PluginManifest> downloadPluginManifest(MarketplaceEntry entry) async {
    // 内置插件：直接返回内置 manifest。
    if (isBuiltInRepo(entry.repoUrl)) {
      final pluginId = pluginIdFromBuiltInRepo(entry.repoUrl);
      final manifest = pluginId == null ? null : builtInPluginManifests[pluginId];
      if (manifest == null) {
        throw Exception('未知的内置插件: ${entry.repoUrl}');
      }
      return manifest.copyWith(
        sourceRepoUrl: entry.repoUrl,
        installedAt: DateTime.now().toIso8601String(),
      );
    }

    final repoInfo = _parseGitHubRepo(entry.repoUrl);
    if (repoInfo == null) {
      throw Exception('无法解析仓库地址: ${entry.repoUrl}');
    }

    // 优先尝试 raw URL 获取 plugin.json（轻量，无需下载整个仓库）
    final rawUrl =
        'https://raw.githubusercontent.com/${repoInfo.owner}/${repoInfo.repo}/'
        '${entry.branch}/plugin.json';

    try {
      final rawResponse = await _httpClient.get(Uri.parse(rawUrl));
      if (rawResponse.statusCode == 200) {
        return PluginManifest.parse(rawResponse.body).copyWith(
          sourceRepoUrl: entry.repoUrl,
          installedAt: DateTime.now().toIso8601String(),
        );
      }
    } catch (_) {
      // raw URL 失败时降级到 GitHub Contents API（Web 端 CORS 友好）。
    }

    // 降级 1：GitHub Contents API（api.github.com 带 CORS 头，Web 端可用）。
    // 返回 JSON，content 字段为 base64 编码的 plugin.json 内容。
    try {
      final manifest = await _fetchViaGitHubContentsApi(entry, repoInfo);
      if (manifest != null) return manifest;
    } catch (_) {
      // Contents API 失败（如速率限制、私有仓库）时再降级到 ZIP。
    }

    // 降级 2：下载仓库 ZIP，解压后读取 plugin.json。
    // 注意：codeload.github.com 不带 CORS 头，Web 端此路径通常失败；
    // 主要服务于桌面/移动端。
    return _downloadAndExtractManifest(entry, repoInfo);
  }

  /// 通过 GitHub Contents API 获取 plugin.json。
  ///
  /// api.github.com 返回 `Access-Control-Allow-Origin: *`，Web 端不受
  /// CORS 限制。响应 JSON 的 `content` 字段为 base64 编码的文件内容。
  /// 未认证时有 60 次/小时的速率限制，对市场安装场景足够。
  Future<PluginManifest?> _fetchViaGitHubContentsApi(
    MarketplaceEntry entry,
    _GitHubRepo repoInfo,
  ) async {
    final apiUrl =
        'https://api.github.com/repos/${repoInfo.owner}/${repoInfo.repo}/'
        'contents/plugin.json?ref=${entry.branch}';
    final response = await _httpClient.get(
      Uri.parse(apiUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;
    final content = body['content'];
    if (content is! String) return null;
    // content 可能含换行符，需先移除再 base64 解码。
    final cleaned = content.replaceAll(RegExp(r'\s'), '');
    final bytes = base64.decode(cleaned);
    final pluginJson = utf8.decode(bytes);
    return PluginManifest.parse(pluginJson).copyWith(
      sourceRepoUrl: entry.repoUrl,
      installedAt: DateTime.now().toIso8601String(),
    );
  }

  Future<PluginManifest> _downloadAndExtractManifest(
    MarketplaceEntry entry,
    _GitHubRepo repoInfo,
  ) async {
    final zipUrl =
        'https://codeload.github.com/${repoInfo.owner}/${repoInfo.repo}/zip/refs/heads/${entry.branch}';
    final response = await _httpClient.get(Uri.parse(zipUrl));
    if (response.statusCode != 200) {
      throw Exception('下载插件仓库失败 (${response.statusCode})');
    }

    final archive = ZipDecoder().decodeBytes(response.bodyBytes);
    // ZIP 解压后顶层目录通常为 `{repo}-{branch}/`
    final prefix = '${repoInfo.repo}-${entry.branch}/';

    for (final file in archive) {
      final name = file.name;
      // 跳过目录，匹配顶层 plugin.json
      if (file.isFile && (name == '${prefix}plugin.json' || name == 'plugin.json')) {
        final content = utf8.decode(file.content as List<int>);
        return PluginManifest.parse(content).copyWith(
          sourceRepoUrl: entry.repoUrl,
          installedAt: DateTime.now().toIso8601String(),
        );
      }
    }

    throw Exception('插件仓库中未找到 plugin.json');
  }

  /// 解析 GitHub 仓库 URL，提取 owner / repo。
  _GitHubRepo? _parseGitHubRepo(String url) {
    // https://github.com/owner/repo
    final match = RegExp(
      r'github\.com/([^/]+)/([^/]+)/?',
    ).firstMatch(url);
    if (match != null) {
      return _GitHubRepo(
        owner: match.group(1)!,
        repo: match.group(2)!.replaceAll('.git', ''),
      );
    }
    return null;
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

/// PluginManifest 扩展：复制时附加元信息。
extension PluginManifestCopy on PluginManifest {
  PluginManifest copyWith({
    String? sourceRepoUrl,
    String? installedAt,
  }) {
    return PluginManifest(
      id: id,
      displayName: displayName,
      description: description,
      version: version,
      author: author,
      category: category,
      inputs: inputs,
      outputs: outputs,
      configSchema: configSchema,
      executor: executor,
      executorType: executorType,
      functionDef: functionDef,
      uiComponent: uiComponent,
      sourceRepoUrl: sourceRepoUrl ?? this.sourceRepoUrl,
      installedAt: installedAt ?? this.installedAt,
    );
  }
}
