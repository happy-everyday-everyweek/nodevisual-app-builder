/// 构建进度信息。
///
/// 由 [BuildPipeline] 在编译各阶段推进时发布，
/// UI 层（[BuildProgressNotifier]）订阅展示。
class BuildProgress {
  /// 当前阶段（如「校验 IR」「序列化」「打包 Web」「打包 Android」）。
  final String phase;

  /// 总进度百分比 0..100。
  final int percent;

  /// 详细消息（可包含子步骤信息）。
  final String message;

  /// 是否已完成（成功或失败）。
  final bool isCompleted;

  /// 是否发生错误（[message] 含错误详情）。
  final bool hasError;

  const BuildProgress({
    required this.phase,
    required this.percent,
    required this.message,
    this.isCompleted = false,
    this.hasError = false,
  });

  /// 初始空进度。
  static const BuildProgress idle = BuildProgress(
    phase: '待开始',
    percent: 0,
    message: '',
  );

  BuildProgress copyWith({
    String? phase,
    int? percent,
    String? message,
    bool? isCompleted,
    bool? hasError,
  }) =>
      BuildProgress(
        phase: phase ?? this.phase,
        percent: percent ?? this.percent,
        message: message ?? this.message,
        isCompleted: isCompleted ?? this.isCompleted,
        hasError: hasError ?? this.hasError,
      );

  @override
  String toString() =>
      'BuildProgress($phase $percent% ${hasError ? "ERR" : "OK"}: $message)';
}
