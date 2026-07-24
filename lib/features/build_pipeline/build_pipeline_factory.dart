import 'build_pipeline_io.dart' if (dart.library.html) 'build_pipeline_stub.dart';

export 'build_pipeline_io.dart' if (dart.library.html) 'build_pipeline_stub.dart';

/// 创建 [BuildPipeline] 实例（平台相关）。
///
/// - 非 Web 平台：返回真正的 [BuildPipeline]（基于 dart:io 文件系统）。
/// - Web 平台：返回 [StubBuildPipeline]，所有方法抛 [UnsupportedError]，
///   因为端侧构建依赖文件系统与原生工具链，Web 不可用。
BuildPipeline createBuildPipeline() => createBuildPipelineImpl();
