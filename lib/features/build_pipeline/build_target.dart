/// 编译目标平台。
///
/// 对应 spec「多端编译打包」要求的三类产物：
/// - [web]：可部署的 HTML/JS 静态包（v1 优先，真端侧生成）
/// - [android]：可安装的 APK / `.nvapk` 包（v1 优先，bundle 优先）
/// - [windows]：可执行 / 可运行目录（v1 milestone，bundle 形式）
enum BuildTarget {
  web('Web', 'HTML/JS 静态包', '.zip'),
  android('Android', 'APK / .nvapk 包', '.nvapk'),
  windows('Windows', '可执行 / 可运行目录', '.nvexe');

  const BuildTarget(this.label, this.description, this.bundleExtension);

  /// 显示名。
  final String label;

  /// 产物描述。
  final String description;

  /// 打包产物默认扩展名。
  final String bundleExtension;

  /// 从字符串解析，未知值降级为 [web]。
  static BuildTarget fromName(String? name) {
    switch (name) {
      case 'web':
        return BuildTarget.web;
      case 'android':
        return BuildTarget.android;
      case 'windows':
        return BuildTarget.windows;
      default:
        return BuildTarget.web;
    }
  }
}
