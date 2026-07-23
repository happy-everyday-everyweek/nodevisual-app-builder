import '../../../data/models/project.dart';

/// 代码生成器骨架（P8 可选优化路径，当前未实现）。
///
/// 架构 spike 决策：**IR 即运行时格式**，节点函数由 Dart 节点解释器
/// （[NodeInterpreter]）直接执行 DAG，无需代码生成。代码生成降级为
/// 可选优化，留待 P8 阶段实现（如生成原生 Dart 代码以提升性能、
/// 或导出为独立可执行模块）。
///
/// 当前仅占位，[generate] 抛 [UnsupportedError]。
class Codegen {
  /// 生成代码（未实现）。
  ///
  /// TODO(P8): 实现基于 [Project] IR 的代码生成。
  String generate(Project project) {
    throw UnsupportedError('代码生成尚未实现（P8 优化路径）');
  }
}
