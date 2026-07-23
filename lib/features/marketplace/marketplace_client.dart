import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'marketplace_entry.dart';
import 'plugin_manifest.dart';

/// 插件市场客户端。
///
/// 负责从市场仓库拉取索引（index.json），以及从插件源仓库
/// 下载 plugin.json 清单。所有网络请求通过 GitHub raw / codeload URL 完成。
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

  /// 拉取市场索引。
  Future<MarketplaceIndex> fetchIndex() async {
    final response = await _httpClient.get(Uri.parse(_marketplaceRawBaseUrl));
    if (response.statusCode != 200) {
      throw Exception('无法获取插件市场索引 (${response.statusCode})');
    }
    return MarketplaceIndex.parse(response.body);
  }

  /// 从插件源仓库下载并解析 plugin.json 清单。
  ///
  /// 使用 GitHub codeload API 下载仓库 ZIP，解压后读取 plugin.json。
  /// 返回的 [PluginManifest] 带有 sourceRepoUrl 与 installedAt 元信息。
  Future<PluginManifest> downloadPluginManifest(MarketplaceEntry entry) async {
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
      // raw URL 失败时降级为下载 ZIP
    }

    // 降级：下载仓库 ZIP，解压后读取 plugin.json
    return _downloadAndExtractManifest(entry, repoInfo);
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

/// 已安装插件本地存储。
///
/// 将安装的 [PluginManifest] 序列化为 JSON 存储到应用文档目录下的
/// `installed_plugins/` 目录，每个插件一个文件（`{id}.json`）。
/// 启动时读取全部已安装清单，注册到 PluginRegistry。
class InstalledPluginStore {
  static const String _dirName = 'installed_plugins';

  Directory? _cacheDir;

  Future<Directory> _getDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// 列出全部已安装插件清单。
  Future<List<PluginManifest>> listInstalled() async {
    final dir = await _getDir();
    final files = dir
        .listSync()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final manifests = <PluginManifest>[];
    for (final file in files) {
      try {
        final raw = file.readAsStringSync();
        final manifest = PluginManifest.parse(raw);
        manifests.add(manifest);
      } catch (_) {
        // 跳过损坏的清单文件
      }
    }
    return manifests;
  }

  /// 获取指定插件的已安装清单（未安装返回 null）。
  Future<PluginManifest?> getInstalled(String pluginId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    if (!file.existsSync()) return null;
    try {
      return PluginManifest.parse(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  /// 保存（安装）插件清单。
  Future<void> save(PluginManifest manifest) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '${manifest.id}.json'));
    file.writeAsStringSync(jsonEncode(manifest.toJson()));
  }

  /// 删除（卸载）插件。
  Future<void> remove(String pluginId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    if (file.existsSync()) file.deleteSync();
  }

  /// 检查是否已安装。
  Future<bool> isInstalled(String pluginId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '$pluginId.json'));
    return file.existsSync();
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
      sourceRepoUrl: sourceRepoUrl ?? this.sourceRepoUrl,
      installedAt: installedAt ?? this.installedAt,
    );
  }
}
