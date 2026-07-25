import 'dart:convert';

/// 项目市场索引文件（marketplace 仓库根目录 `projects.json`）。
///
/// 列出市场中所有用户发布的项目条目。项目作者通过向 marketplace 仓库
/// 提交 PR 在此追加条目，PR 详情中包含项目源仓库地址。
///
/// 与 [MarketplaceIndex]（插件索引）平行存在，但服务于项目分发：
/// 用户可从市场克隆项目到本地，作为自己项目的起点。
class ProjectMarketplaceIndex {
  /// 索引格式版本。
  final int version;

  /// 市场名称。
  final String name;

  /// 项目条目列表。
  final List<ProjectMarketplaceEntry> projects;

  const ProjectMarketplaceIndex({
    this.version = 1,
    this.name = 'NodeVisual Project Marketplace',
    this.projects = const [],
  });

  factory ProjectMarketplaceIndex.fromJson(Map<String, dynamic> json) {
    return ProjectMarketplaceIndex(
      version: (json['version'] as num?)?.toInt() ?? 1,
      name: (json['name'] as String?) ?? 'NodeVisual Project Marketplace',
      projects: (json['projects'] as List?)
              ?.map((e) =>
                  ProjectMarketplaceEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  static ProjectMarketplaceIndex parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return ProjectMarketplaceIndex.fromJson(decoded);
    }
    throw FormatException('projects.json 格式错误');
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'name': name,
        'projects': projects.map((e) => e.toJson()).toList(),
      };
}

/// 项目市场条目（projects.json 中的一项）。
///
/// 每个条目指向一个已发布到 GitHub 的项目仓库（[repoUrl]），仓库根目录
/// 包含 `ir.json`（项目 IR 快照）。用户克隆时会从该仓库下载 ir.json
/// 并导入为本地项目。
class ProjectMarketplaceEntry {
  /// 项目唯一标识（使用 GitHub 仓库全名 `owner/repo` 作为 id）。
  final String id;

  /// 项目展示名。
  final String name;

  /// 项目描述。
  final String description;

  /// 作者（GitHub login）。
  final String author;

  /// 项目语义化版本（最新发布版本）。
  final String version;

  /// 项目源仓库 URL（HTTPS）。
  final String repoUrl;

  /// 分支名（默认 main）。
  final String branch;

  /// 分类标签。
  final List<String> tags;

  /// 图标标识（用于 UI 展示）。
  final String icon;

  /// Star 数（市场统计，可为 0）。
  final int stars;

  /// 最近更新时间（ISO8601）。
  final String updatedAt;

  const ProjectMarketplaceEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.repoUrl,
    this.branch = 'main',
    this.tags = const [],
    this.icon = 'folder',
    this.stars = 0,
    this.updatedAt = '',
  });

  factory ProjectMarketplaceEntry.fromJson(Map<String, dynamic> json) {
    return ProjectMarketplaceEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      author: (json['author'] as String?) ?? 'unknown',
      version: (json['version'] as String?) ?? '0.1.0',
      repoUrl: json['repoUrl'] as String,
      branch: (json['branch'] as String?) ?? 'main',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      icon: (json['icon'] as String?) ?? 'folder',
      stars: (json['stars'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'author': author,
        'version': version,
        'repoUrl': repoUrl,
        'branch': branch,
        'tags': tags,
        'icon': icon,
        'stars': stars,
        'updatedAt': updatedAt,
      };
}
