import '../../data/models/function_def.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../../data/models/variable_ref.dart';

/// 类型校验结果。
///
/// v1 简化：仅返回是否兼容 + 不匹配原因字符串（[reason] 在 [ok] 为 true 时为空）。
class TypeCheckResult {
  /// 是否兼容。
  final bool ok;

  /// 不匹配原因（[ok] 为 true 时为空字符串）。
  final String reason;

  const TypeCheckResult(this.ok, this.reason);

  static const TypeCheckResult match = TypeCheckResult(true, '');
}

/// 解析 [ref] 指向目标的声明类型。
///
/// - [VariableSource.upstream]：在 [functionDef.nodes] 中查找 [VariableRef.nodeId]
///   节点，再查其 [DataOutput] 名为 [VariableRef.outputName] 的类型。
/// - [VariableSource.funcVar]：在 [functionDef.funcVars] 中按 [VariableRef.varId] 查找。
/// - [VariableSource.projVar]：在 [project.projectVars] 中按 [VariableRef.varId] 查找。
/// - [VariableSource.component]：运行时注入（item/index/tab/value 等），静态
///   无法确定类型，返回 [PortType.any]（兼容一切，由运行时按值校验）。
///
/// 找不到返回 null（引用目标不存在）。
PortType? resolveRefType(
  VariableRef ref,
  FunctionDef functionDef,
  Project? project,
) {
  switch (ref.source) {
    case VariableSource.upstream:
      final nodeId = ref.nodeId;
      final outputName = ref.outputName;
      if (nodeId == null || outputName == null) return null;
      for (final node in functionDef.nodes) {
        if (node.id != nodeId) continue;
        for (final out in node.dataOutputs) {
          if (out.name == outputName) return out.type;
        }
        return null;
      }
      return null;
    case VariableSource.funcVar:
      final varId = ref.varId;
      if (varId == null) return null;
      for (final v in functionDef.funcVars) {
        if (v.id == varId) return v.type;
      }
      return null;
    case VariableSource.projVar:
      final varId = ref.varId;
      if (varId == null || project == null) return null;
      for (final v in project.projectVars) {
        if (v.id == varId) return v.type;
      }
      return null;
    case VariableSource.component:
      // 组件上下文变量类型由运行时值决定，静态返回 any 以兼容校验。
      return PortType.any;
  }
}

/// 校验 [ref] 与期望类型 [expectedType] 是否兼容。
///
/// 兼容规则（v1）：
/// - 期望为 [PortType.any] → 兼容一切；
/// - 实际为 [PortType.any] → 兼容一切（动态来源）；
/// - 实际与期望同类型 → 兼容；
/// - list / map 无参容器，仅同容器类型兼容（list↔list、map↔map）；
/// - 其余视为不匹配，附原因。
///
/// 若引用目标无法解析（[resolveRefType] 返回 null），返回不匹配并提示
/// "引用目标不存在"。
TypeCheckResult checkRefType(
  VariableRef ref,
  PortType expectedType,
  FunctionDef functionDef,
  Project? project,
) {
  final refType = resolveRefType(ref, functionDef, project);
  if (refType == null) {
    return const TypeCheckResult(false, '引用目标不存在');
  }
  if (expectedType == PortType.any || refType == PortType.any) {
    return TypeCheckResult.match;
  }
  if (refType == expectedType) {
    return TypeCheckResult.match;
  }
  return TypeCheckResult(
    false,
    '类型不匹配：期望 ${expectedType.toJson()}，实际 ${refType.toJson()}',
  );
}
