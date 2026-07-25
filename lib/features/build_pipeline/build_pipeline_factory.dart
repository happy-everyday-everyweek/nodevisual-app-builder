import 'build_pipeline_io.dart'
    if (dart.library.html) 'build_pipeline_web.dart';

export 'build_pipeline_io.dart'
    if (dart.library.html) 'build_pipeline_web.dart';

/// 创建 [BuildPipeline] 实例（平台相关）。
///
/// - 非 Web 平台：返回基于 dart:io 文件系统的 [BuildPipeline]，
///   支持 Web / Android / Windows 三类产物（Android / Windows 为 IR bundle）。
/// - Web 平台：返回内存版 [BuildPipeline]，仅支持 Web 目标，
///   产物以 [BuildArtifact.bytes] 形式保留在内存，由 UI 层触发浏览器下载。
BuildPipeline createBuildPipeline() => createBuildPipelineImpl();
