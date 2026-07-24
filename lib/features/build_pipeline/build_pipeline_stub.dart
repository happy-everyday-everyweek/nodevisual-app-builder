import 'build_progress.dart';
import 'build_result.dart';

/// Web 平台的 [BuildPipeline] stub。
///
/// 端侧构建依赖 dart:io（文件系统）与原生工具链，Web 平台不可用。
/// 此 stub 仅用于 Web 编译占位，所有方法抛 [UnsupportedError]。
class BuildPipeline {
  BuildPipeline({List<dynamic>? builders});

  Stream<BuildProgress> get progressStream => const Stream.empty();

  Future<BuildResult> run({
    required dynamic project,
    required List<dynamic> targets,
  }) async {
    throw UnsupportedError('Web 平台不支持端侧构建（需要文件系统与原生工具链）');
  }

  void dispose() {}
}

/// Web 平台实现入口。
BuildPipeline createBuildPipelineImpl() => BuildPipeline();
