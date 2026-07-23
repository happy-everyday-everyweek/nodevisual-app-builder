import 'dart:convert';

/// 插件市场索引文件（marketplace 仓库根目录 `index.json`）。
///
/// 列出市场中所有可安装的插件条目。插件作者通过向 marketplace 仓库
/// 提交 PR 在此追加条目，PR 详情中包含插件源仓库地址。
class MarketplaceIndex {
  /// 索引格式版本。
  final int version;

  /// 市场名称。
  final String name;

  /// 插件条目列表。
  final List<MarketplaceEntry> plugins;

  const MarketplaceIndex({
    this.version = 1,
    this.name = 'NodeVisual Plugin Marketplace',
    this.plugins = const [],
  });

  factory MarketplaceIndex.fromJson(Map<String, dynamic> json) {
    return MarketplaceIndex(
      version: (json['version'] as num?)?.toInt() ?? 1,
      name: (json['name'] as String?) ?? 'NodeVisual Plugin Marketplace',
      plugins: (json['plugins'] as List?)
              ?.map((e) => MarketplaceEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  static MarketplaceIndex parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return MarketplaceIndex.fromJson(decoded);
    }
    throw FormatException('marketplace index.json 格式错误');
  }
}

/// 插件市场条目（index.json 中的一项）。
///
/// 每个条目指向一个独立的插件源仓库（[repoUrl]），安装时从该仓库
/// 拉取 `plugin.json` 清单并注册。
class MarketplaceEntry {
  /// 插件唯一标识。
  final String id;

  /// 中文展示名。
  final String displayName;

  /// 中文描述。
  final String description;

  /// 版本号。
  final String version;

  /// 作者。
  final String author;

  /// 插件源仓库 URL（HTTPS）。
  final String repoUrl;

  /// 分支名（默认 main）。
  final String branch;

  /// 分类标签。
  final List<String> tags;

  /// 图标标识（用于 UI 展示，如 weather / http / translate）。
  final String icon;

  /// 下载次数（市场统计，可为 0）。
  final int downloads;

  const MarketplaceEntry({
    required this.id,
    required this.displayName,
    required this.description,
    required this.version,
    required this.author,
    required this.repoUrl,
    this.branch = 'main',
    this.tags = const [],
    this.icon = 'extension',
    this.downloads = 0,
  });

  factory MarketplaceEntry.fromJson(Map<String, dynamic> json) {
    return MarketplaceEntry(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      description: (json['description'] as String?) ?? '',
      version: (json['version'] as String?) ?? '1.0.0',
      author: (json['author'] as String?) ?? 'unknown',
      repoUrl: json['repoUrl'] as String,
      branch: (json['branch'] as String?) ?? 'main',
      tags: (json['tags'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      icon: (json['icon'] as String?) ?? 'extension',
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'description': description,
        'version': version,
        'author': author,
        'repoUrl': repoUrl,
        'branch': branch,
        'tags': tags,
        'icon': icon,
        'downloads': downloads,
      };
}
