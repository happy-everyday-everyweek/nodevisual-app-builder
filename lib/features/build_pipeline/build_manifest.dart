/// 构建清单（写入产物 manifest.json）。
///
/// 描述一次构建的元信息：项目、目标平台、构建时间、工具版本、IR 版本等。
/// 用于：
/// - Android `.nvapk` 包标识，便于运行时识别
/// - Web 包元数据
/// - Windows `.nvexe` 包元数据
/// - 后续 runner app 加载 IR 时的版本协商
class BuildManifest {
  /// 清单格式版本。
  final String manifestVersion;

  /// 目标平台（web / android / windows）。
  final String target;

  /// 项目元数据。
  final ProjectInfo project;

  /// 构建信息。
  final BuildInfo build;

  /// 运行时要求（IR 版本、解释器版本）。
  final RuntimeInfo runtime;

  const BuildManifest({
    this.manifestVersion = '1',
    required this.target,
    required this.project,
    required this.build,
    required this.runtime,
  });

  Map<String, dynamic> toJson() => {
        'manifestVersion': manifestVersion,
        'target': target,
        'project': project.toJson(),
        'build': build.toJson(),
        'runtime': runtime.toJson(),
      };

  @override
  String toString() => 'BuildManifest(${project.name} → $target)';
}

/// 项目元数据（嵌入 [BuildManifest]）。
class ProjectInfo {
  /// 项目 ID。
  final String id;

  /// 项目名。
  final String name;

  /// 项目描述（可空）。
  final String? description;

  /// IR schema 版本。
  final String irVersion;

  const ProjectInfo({
    required this.id,
    required this.name,
    required this.irVersion,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'irVersion': irVersion,
        if (description != null) 'description': description,
      };
}

/// 构建信息（嵌入 [BuildManifest]）。
class BuildInfo {
  /// 构建工具（NodeVisual App Builder）。
  final String builtBy;

  /// 构建工具版本。
  final String builderVersion;

  /// 构建时间（ISO8601）。
  final String builtAt;

  /// 构建所在设备/平台标识（端侧构建标记）。
  final String builtOn;

  const BuildInfo({
    this.builtBy = 'NodeVisual App Builder',
    required this.builderVersion,
    required this.builtAt,
    required this.builtOn,
  });

  Map<String, dynamic> toJson() => {
        'builtBy': builtBy,
        'builderVersion': builderVersion,
        'builtAt': builtAt,
        'builtOn': builtOn,
      };
}

/// 运行时要求（嵌入 [BuildManifest]）。
class RuntimeInfo {
  /// 解释器最低版本。
  final String interpreterVersion;

  /// IR 入口文件（相对包根）。
  final String irFile;

  /// 运行时类型（解释器执行 / 代码生成）。
  final String runtimeMode;

  const RuntimeInfo({
    this.interpreterVersion = '1',
    this.irFile = 'ir.json',
    this.runtimeMode = 'interpreter',
  });

  Map<String, dynamic> toJson() => {
        'interpreterVersion': interpreterVersion,
        'irFile': irFile,
        'runtimeMode': runtimeMode,
      };
}
