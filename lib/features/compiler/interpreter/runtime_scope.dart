import '../../data/models/component_context.dart';

/// 页面级函数的执行状态。
///
/// 用于时间线规则：UI 组件 `#` 引用函数 outputs 时，系统按当前状态决定返回
/// 实际值还是加载态占位（详见 spec 的"加载态占位机制"）。
enum PageFuncState {
  /// 尚未开始执行。
  idle,

  /// 执行中。
  running,

  /// 执行完成（成功）。
  done,

  /// 执行失败。
  error,
}

/// 页面级函数缓存条目（outputs + 状态 + 错误信息）。
class PageFuncEntry {
  /// 函数 outputs（按名缓存；执行完成前为空）。
  final Map<String, dynamic> outputs;

  /// 执行状态。
  final PageFuncState state;

  /// 错误信息（仅 [state] == [PageFuncState.error] 时非空）。
  final String? error;

  const PageFuncEntry({
    this.outputs = const {},
    this.state = PageFuncState.idle,
    this.error,
  });

  /// 拷贝并更新字段。
  PageFuncEntry copyWith({
    Map<String, dynamic>? outputs,
    PageFuncState? state,
    String? error,
  }) {
    return PageFuncEntry(
      outputs: outputs ?? this.outputs,
      state: state ?? this.state,
      error: error ?? this.error,
    );
  }
}

/// 运行时作用域，存储节点执行期间的动态值。
///
/// 节点解释器执行控制流图时，[RuntimeScope] 承载 `#` 引用作用域的**四源**
/// 运行时值：
/// - [nodeOutputs]：已执行节点的命名数据输出，key = `"${nodeId}.${outputName}"`，
///   对应 [VariableSource.upstream] 引用。
/// - [funcVars]：当前函数的局部变量，key = varId，对应
///   [VariableSource.funcVar] 引用。
/// - [projVars]：项目级变量，key = varId，对应 [VariableSource.projVar] 引用。
/// - [componentContexts]：容器组件注入的上下文（item/index/tab/value），
///   key = componentId，对应 [VariableSource.component] 引用。
///   仅 UI 渲染期有效，节点解释器执行函数时通常为空。
/// - [pageFuncOutputs]：页面级函数 outputs 缓存 + 时间线状态，
///   供同页面 UI 组件的 `#funcVar` 引用按时间线规则解析。
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

  /// 组件上下文（key = componentId），由容器组件在 UI 渲染期注入。
  ///
  /// 节点解释器执行函数时此 map 通常为空（函数内不会读取组件上下文，
  /// 除非显式传入）。
  final Map<String, ComponentContext> componentContexts = {};

  /// 页面级函数 outputs 缓存 + 时间线状态（key = funcId）。
  ///
  /// UI 渲染层在页面 onLoad 时执行函数并写入此缓存；同页面 UI 组件的
  /// `#funcVar` 引用按 [PageFuncEntry.state] 决定返回值或加载态占位。
  final Map<String, PageFuncEntry> pageFuncOutputs = {};

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

  /// 读取组件上下文（可能为 null：未注入或组件不存在）。
  ComponentContext? getComponentContext(String componentId) =>
      componentContexts[componentId];

  /// 写入组件上下文（由容器组件在渲染期注入）。
  void setComponentContext(String componentId, ComponentContext ctx) {
    componentContexts[componentId] = ctx;
  }

  /// 清除指定组件的上下文（组件卸载时调用）。
  void removeComponentContext(String componentId) {
    componentContexts.remove(componentId);
  }

  /// 读取页面级函数缓存条目（可能为 null：函数未挂到任何页面事件）。
  PageFuncEntry? getPageFuncEntry(String funcId) => pageFuncOutputs[funcId];

  /// 写入页面级函数缓存条目。
  void setPageFuncEntry(String funcId, PageFuncEntry entry) {
    pageFuncOutputs[funcId] = entry;
  }

  /// 清除页面级函数缓存（页面卸载时调用）。
  void clearPageFuncOutputs() {
    pageFuncOutputs.clear();
  }
}
