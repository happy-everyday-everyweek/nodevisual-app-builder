/// 应用全局常量。
///
/// 集中维护应用名称、版本、存储键名、路由路径等常量，
/// 便于在编译期被裁剪与统一引用。
class AppConstants {
  AppConstants._();

  /// 应用名称。
  static const String appName = 'NodeVisual App Builder';

  /// 应用版本号（与 pubspec.yaml 保持一致）。
  static const String appVersion = '0.1.0';

  /// 构建号。
  static const int buildNumber = 1;

  // ---- 路由路径 ----
  static const String routeHome = '/';
  static const String routeEditor = '/editor';
  static const String routeSettings = '/settings';

  /// 插件市场路由路径。
  static const String routeMarketplace = '/marketplace';

  /// 项目编辑器路由路径模板（含 :id 路径参数）。
  static const String routeProject = '/project/:id';

  /// 拼接项目编辑器路由地址。
  static String projectRoute(String id) => '/project/$id';

  /// 函数节点图编辑器路由路径模板（含 :id 与 :fid 路径参数）。
  static const String routeFunctionEditor = '/project/:id/function/:fid';

  /// 拼接函数节点图编辑器路由地址。
  static String functionEditorRoute(String projectId, String functionId) =>
      '/project/$projectId/function/$functionId';

  /// 节点编辑页路由路径模板（含 :id / :fid / :nid 路径参数）。
  static const String routeNodeEditor =
      '/project/:id/function/:fid/node/:nid';

  /// 拼接节点编辑页路由地址。
  static String nodeEditorRoute(
    String projectId,
    String functionId,
    String nodeId,
  ) =>
      '/project/$projectId/function/$functionId/node/$nodeId';

  /// 编译打包页路由路径模板（含 :id 路径参数）。
  static const String routeBuild = '/project/:id/build';

  /// 拼接编译打包页路由地址。
  static String buildRoute(String projectId) => '/project/$projectId/build';

  // ---- 本地存储相关键名 ----
  /// SharedPreferences 中保存最近打开项目 id 的键。
  static const String prefKeyLastProjectId = 'last_project_id';

  /// SQLite 数据库文件名。
  static const String sqliteDbName = 'nodevisual.db';

  /// SQLite 数据库版本。
  static const int sqliteDbVersion = 1;

  /// 项目文件存储子目录名（位于应用文档目录下）。
  static const String projectsDirName = 'projects';

  // ---- 默认节点参数 ----
  /// 画布网格吸附半径（逻辑像素）。
  static const double canvasSnapRadius = 8.0;
}
