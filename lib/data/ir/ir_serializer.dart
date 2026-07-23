import '../models/project.dart';

/// IR（中间表示）序列化器。
///
/// 架构 spike 决策：**IR 即运行时格式**，[Project] 的 JSON 形式既是
/// 持久化格式也是节点解释器的执行输入，代码生成降级为可选优化。
///
/// 本类作为 IR 序列化的统一入口，封装 [Project.toJson] / [Project.fromJson]，
/// 覆盖 meta / projectVars / functions / folders / db / ui 全部段。每个
/// 模型委托其自身的 [toJson] / [fromJson] 实现，null / 默认值（entry 可空、
/// folderId 可空等）由各模型在序列化时按需省略、反序列化时降级处理。
class IrSerializer {
  IrSerializer._();

  /// 将 [Project] 序列化为完整 JSON Map。
  ///
  /// 返回的 Map 可直接 `jsonEncode` 落盘，或交由 [deserialize] 还原。
  static Map<String, dynamic> serialize(Project project) {
    return project.toJson();
  }

  /// 从 JSON Map 反序列化为 [Project]。
  ///
  /// 缺失字段降级为默认空集合 / null（由各模型 [fromJson] 保证）。
  static Project deserialize(Map<String, dynamic> json) {
    return Project.fromJson(json);
  }

  /// 校验往返一致性：[serialize] 后 [deserialize] 应得到相等的 [Project]。
  ///
  /// 相等性依赖 [Project.operator==] 对全部段的深比较（基于
  /// `DeepCollectionEquality`）。返回 true 表示一致。
  static bool roundtripEquals(Project project) {
    final json = serialize(project);
    final restored = deserialize(json);
    return restored == project;
  }
}
