import 'build_artifact.dart';

/// 编译结果。
///
/// 一次 [BuildPipeline.run] 调用的返回值，包含：
/// - 成功标志 [success]
/// - 全部产物 [artifacts]
/// - 各阶段日志 [logs]
/// - 失败原因 [error]（[success] == false 时）
class BuildResult {
  /// 是否全部目标成功。
  final bool success;

  /// 生成的产物列表（按 [BuildTarget] 顺序）。
  final List<BuildArtifact> artifacts;

  /// 构建日志（含每阶段开始 / 完成 / 警告）。
  final List<String> logs;

  /// 失败原因（[success] == false 时非空）。
  final String? error;

  /// 构建耗时（毫秒）。
  final int elapsedMs;

  const BuildResult({
    required this.success,
    required this.artifacts,
    required this.logs,
    required this.elapsedMs,
    this.error,
  });

  /// 成功结果。
  factory BuildResult.ok({
    required List<BuildArtifact> artifacts,
    required List<String> logs,
    required int elapsedMs,
  }) =>
      BuildResult(
        success: true,
        artifacts: artifacts,
        logs: logs,
        elapsedMs: elapsedMs,
      );

  /// 失败结果。
  factory BuildResult.failure({
    required String error,
    required List<String> logs,
    required int elapsedMs,
    List<BuildArtifact> artifacts = const [],
  }) =>
      BuildResult(
        success: false,
        artifacts: artifacts,
        logs: logs,
        elapsedMs: elapsedMs,
        error: error,
      );

  @override
  String toString() =>
      'BuildResult(${success ? "OK" : "FAIL"}, ${artifacts.length} artifacts, ${elapsedMs}ms)';
}
