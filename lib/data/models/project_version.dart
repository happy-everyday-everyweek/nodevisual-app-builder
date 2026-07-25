/// 项目版本发布历史记录。
///
/// 每次发布到 GitHub（或其他渠道）后追加一条记录，用于：
/// - 发布界面展示版本历史列表；
/// - 校验版本号单调递增；
/// - 故障回溯（关联 commit sha / release url）。
///
/// 与 [ProjectMeta.semver] 区别：
/// - [ProjectMeta.semver] 是当前最新版本号（标量）；
/// - [ProjectVersion] 是历史版本快照（含发布时间、release url 等元数据）。
class ProjectVersion {
  /// 项目 id（外键 → [ProjectMeta.id]）。
  final String projectId;

  /// 语义化版本号（如 "0.1.0"）。
  final String semver;

  /// 发布时间（ISO8601 字符串）。
  final String publishedAt;

  /// 对应的 GitHub commit SHA（推送后获取），未推送为 null。
  final String? commitSha;

  /// 对应的 GitHub Release HTML URL，未创建 Release 为 null。
  final String? releaseUrl;

  /// 发布到的 GitHub 仓库 URL（如 https://github.com/owner/repo）。
  ///
  /// 持久化以支持"已绑定仓库"展示与历史回溯（即使后续项目绑定仓库被更改，
  /// 旧版本仍能跳转到当时的仓库）。
  final String? githubRepoUrl;

  /// 简短发布说明（可选）。
  final String? notes;

  const ProjectVersion({
    required this.projectId,
    required this.semver,
    required this.publishedAt,
    this.commitSha,
    this.releaseUrl,
    this.githubRepoUrl,
    this.notes,
  });

  ProjectVersion copyWith({
    String? projectId,
    String? semver,
    String? publishedAt,
    String? commitSha,
    String? releaseUrl,
    String? githubRepoUrl,
    String? notes,
  }) =>
      ProjectVersion(
        projectId: projectId ?? this.projectId,
        semver: semver ?? this.semver,
        publishedAt: publishedAt ?? this.publishedAt,
        commitSha: commitSha ?? this.commitSha,
        releaseUrl: releaseUrl ?? this.releaseUrl,
        githubRepoUrl: githubRepoUrl ?? this.githubRepoUrl,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'semver': semver,
        'publishedAt': publishedAt,
        if (commitSha != null) 'commitSha': commitSha,
        if (releaseUrl != null) 'releaseUrl': releaseUrl,
        if (githubRepoUrl != null) 'githubRepoUrl': githubRepoUrl,
        if (notes != null) 'notes': notes,
      };

  factory ProjectVersion.fromJson(Map<String, dynamic> json) => ProjectVersion(
        projectId: json['projectId'] as String,
        semver: json['semver'] as String,
        publishedAt: json['publishedAt'] as String,
        commitSha: json['commitSha'] as String?,
        releaseUrl: json['releaseUrl'] as String?,
        githubRepoUrl: json['githubRepoUrl'] as String?,
        notes: json['notes'] as String?,
      );

  @override
  String toString() => 'ProjectVersion($projectId@$semver)';
}

/// 语义化版本工具。
///
/// 解析 "major.minor.patch" 格式（如 "0.1.0"），支持 bump 操作。
/// 不支持预发布标签（-alpha 等）和构建元数据（+build 等），
/// 保持发布场景的最小可用实现。
class SemVer {
  SemVer(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// 从字符串解析；解析失败抛 [FormatException]。
  factory SemVer.parse(String s) {
    final parts = s.split('.');
    if (parts.length != 3) {
      throw FormatException('Invalid semver: "$s"（应为 major.minor.patch）');
    }
    final major = int.parse(parts[0]);
    final minor = int.parse(parts[1]);
    final patch = int.parse(parts[2]);
    if (major < 0 || minor < 0 || patch < 0) {
      throw FormatException('Invalid semver: "$s"（版本号不能为负）');
    }
    return SemVer(major, minor, patch);
  }

  /// 尝试解析；失败返回 null（不抛异常）。
  static SemVer? tryParse(String s) {
    try {
      return SemVer.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// 是否为合法 semver 字符串。
  static bool isValid(String s) => tryParse(s) != null;

  /// bump major：major+1，minor/patch 归零。
  SemVer bumpMajor() => SemVer(major + 1, 0, 0);

  /// bump minor：minor+1，patch 归零。
  SemVer bumpMinor() => SemVer(major, minor + 1, 0);

  /// bump patch：patch+1。
  SemVer bumpPatch() => SemVer(major, minor, patch + 1);

  /// 与另一个 semver 比较（-1 / 0 / 1）。
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  /// 是否严格大于 [other]。
  bool operator >(SemVer other) => compareTo(other) > 0;

  /// 是否严格小于 [other]。
  bool operator <(SemVer other) => compareTo(other) < 0;

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemVer &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}
