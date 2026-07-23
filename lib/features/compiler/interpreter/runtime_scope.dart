/// 运行时作用域，存储节点执行期间的动态值。
///
/// 节点解释器执行控制流图时，[RuntimeScope] 承载 `#` 引用作用域的三来源
/// 运行时值：
/// - [nodeOutputs]：已执行节点的命名数据输出，key = `"${nodeId}.${outputName}"`，
///   对应 [VariableSource.upstream] 引用。
/// - [funcVars]：当前函数的局部变量，key = varId，对应
///   [VariableSource.funcVar] 引用。
/// - [projVars]：项目级变量，key = varId，对应 [VariableSource.projVar] 引用。
/// - [inputs]：函数入参（按名传入，合并到 [funcVars] 前的原始副本）。
///
/// 循环体内执行共享同一 [RuntimeScope]（不创建新作用域），以保证 loop 节点
/// 的 `index` 输出对 body 子图可见；函数调用（function_call）则通过
/// [NodeInterpreter.runFunction] 创建新的 [RuntimeScope] 实现隔离。
class RuntimeScope {
  /// 节点数据输出（key = `"${nodeId}.${outputName}"`）。
  final Map<String, dynamic> nodeOutputs = {};

  /// 函数局部变量（key = varId）。
  final Map<String, dynamic> funcVars = {};

  /// 项目级变量（key = varId）。
  final Map<String, dynamic> projVars = {};

  /// 函数入参（key = name，合并到 [funcVars] 前的原始副本）。
  final Map<String, dynamic> inputs = {};

  /// 读取节点数据输出。
  Object? getNodeOutput(String nodeId, String outputName) =>
      nodeOutputs['$nodeId.$outputName'];

  /// 写入节点数据输出。
  void setNodeOutput(String nodeId, String outputName, Object? value) {
    nodeOutputs['$nodeId.$outputName'] = value;
  }

  /// 读取函数变量。
  Object? getFuncVar(String varId) => funcVars[varId];

  /// 写入函数变量。
  void setFuncVar(String varId, Object? value) {
    funcVars[varId] = value;
  }

  /// 读取项目变量。
  Object? getProjVar(String varId) => projVars[varId];

  /// 写入项目变量。
  void setProjVar(String varId, Object? value) {
    projVars[varId] = value;
  }
}
