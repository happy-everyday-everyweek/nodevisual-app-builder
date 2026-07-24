/// 变量引用来源类型。
///
/// 对应 `#` 作用域四类来源：项目变量、组件上下文变量、函数变量、
/// 控制流上游节点输出。所有源通过同一 `#` 引用机制访问。
enum VariableSource {
  /// 项目级变量（需配合 [VariableRef.varId]）。
  projVar,

  /// 组件上下文变量（仅 UI 侧可见）。
  ///
  /// 容器组件（list_vertical/horizontal/tab_container/card）向子组件注入：
  /// - 列表项：`item` / `index` / `item.<field>`
  /// - Tab：`tab`（当前索引） / `tab.<field>`
  /// - 滑块/开关：`value`
  ///
  /// 由 [ComponentContext] 在渲染时按组件树位置注入（运行时，不持久化）。
  /// 需配合 [VariableRef.componentId] + [VariableRef.fieldName]。
  component,

  /// 当前函数的局部变量（需配合 [VariableRef.varId]）。
  ///
  /// 含时间线问题：UI 侧引用页面 onLoad 函数的 outputs 时，函数可能
  /// 尚未执行 / 执行中 / 已完成 / 失败，由 [RuntimeScope] 按状态机返回。
  funcVar,

  /// 控制流上游节点的命名数据输出
  /// （需配合 [VariableRef.nodeId] + [VariableRef.outputName]）。
  upstream;

  /// 序列化为字符串。
  String toJson() => name;

  /// 反序列化，未知值降级为 [upstream]。
  static VariableSource fromJson(Object? value) {
    if (value is VariableSource) return value;
    if (value is String) {
      return VariableSource.values.firstWhere(
        (e) => e.name == value,
        orElse: () => VariableSource.upstream,
      );
    }
    return VariableSource.upstream;
  }
}

/// `#` 引用，数据平面的核心引用单元。
///
/// **双平面模型**：画布连线只表达控制流；数据通过节点编辑页内的
/// `#` 引用 [VariableRef] 拼装。`#` 作用域四源统一：
/// 项目变量 / 组件上下文变量 / 函数变量 / 上游节点输出。
///
/// 字段约束：
/// - [source] == [VariableSource.projVar]：[varId] 必填。
/// - [source] == [VariableSource.component]：[componentId] 必填（指向容器
///   组件 id）；[fieldName] 可空（为空时引用组件上下文根 `item` / `index` 等）。
/// - [source] == [VariableSource.funcVar]：
///   - 当前函数局部变量：[varId] 必填（指向 [FunctionVariable.id]）。
///   - 页面级函数 outputs（含时间线）：[funcId] 必填（指向 [FunctionDef.id]）
///     + [outputName] 必填（函数 outputs 名）；运行时按 [PageFuncEntry] 状态机
///     解析，未就绪时按 [LoadingStrategy] 返回占位。
/// - [source] == [VariableSource.upstream]：[nodeId] 与 [outputName] 必填。
class VariableRef {
  /// 引用来源。
  final VariableSource source;

  /// 上游节点 id（仅 [VariableSource.upstream] 有效）。
  final String? nodeId;

  /// 上游节点命名数据输出名（[VariableSource.upstream] 必填；
  /// [VariableSource.funcVar] 页面级函数 outputs 时也使用，表示 output 名）。
  final String? outputName;

  /// 变量 id（[VariableSource.funcVar] 当前函数变量 / [VariableSource.projVar] 有效）。
  final String? varId;

  /// 函数 id（[VariableSource.funcVar] 页面级函数 outputs 时必填，
  /// 指向 [FunctionDef.id]）。与 [outputName] 一起定位函数的某个命名 output。
  final String? funcId;

  /// 组件 id（[VariableSource.component] 有效，指向容器组件 id）。
  final String? componentId;

  /// 组件上下文字段名（[VariableSource.component] 有效）。
  ///
  /// 形如 `'item'` / `'index'` / `'tab'` / `'value'` / `'item.name'`。
  /// 为空时引用组件上下文根（即整个 `ComponentContext.fields` map）。
  final String? fieldName;

  const VariableRef({
    required this.source,
    this.nodeId,
    this.outputName,
    this.varId,
    this.funcId,
    this.componentId,
    this.fieldName,
  });

  /// 便捷构造：引用上游节点输出。
  const VariableRef.upstream({
    required String nodeId,
    required String outputName,
  })  : source = VariableSource.upstream,
        nodeId = nodeId,
        outputName = outputName,
        varId = null,
        funcId = null,
        componentId = null,
        fieldName = null;

  /// 便捷构造：引用当前函数的局部变量。
  const VariableRef.funcVar({required String varId})
      : source = VariableSource.funcVar,
        varId = varId,
        nodeId = null,
        outputName = null,
        funcId = null,
        componentId = null,
        fieldName = null;

  /// 便捷构造：引用页面级函数的某个命名 output（含时间线）。
  ///
  /// [funcId] 指向 [FunctionDef.id]；[outputName] 为该函数 outputs 中某项名。
  /// 运行时按 [PageFuncEntry.state] 解析：done 返回缓存值，其余状态按
  /// [LoadingStrategy] 返回占位。
  const VariableRef.pageFunc({
    required String funcId,
    required String outputName,
  })  : source = VariableSource.funcVar,
        funcId = funcId,
        outputName = outputName,
        varId = null,
        nodeId = null,
        componentId = null,
        fieldName = null;

  /// 便捷构造：引用项目变量。
  const VariableRef.projVar({required String varId})
      : source = VariableSource.projVar,
        varId = varId,
        nodeId = null,
        outputName = null,
        funcId = null,
        componentId = null,
        fieldName = null;

  /// 便捷构造：引用组件上下文变量。
  ///
  /// [componentId] 指向容器组件 id；[fieldName] 形如 `'item'` /
  /// `'index'` / `'tab'` / `'value'` / `'item.name'`。
  const VariableRef.component({
    required String componentId,
    required String fieldName,
  })  : source = VariableSource.component,
        componentId = componentId,
        fieldName = fieldName,
        nodeId = null,
        outputName = null,
        varId = null,
        funcId = null;

  /// 是否为页面级函数 outputs 引用（含时间线）。
  ///
  /// true 时 [funcId] 与 [outputName] 必填，运行时按 [PageFuncEntry] 状态机解析。
  bool get isPageFunc =>
      source == VariableSource.funcVar && funcId != null && outputName != null;

  VariableRef copyWith({
    VariableSource? source,
    String? nodeId,
    String? outputName,
    String? varId,
    String? funcId,
    String? componentId,
    String? fieldName,
  }) =>
      VariableRef(
        source: source ?? this.source,
        nodeId: nodeId ?? this.nodeId,
        outputName: outputName ?? this.outputName,
        varId: varId ?? this.varId,
        funcId: funcId ?? this.funcId,
        componentId: componentId ?? this.componentId,
        fieldName: fieldName ?? this.fieldName,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VariableRef &&
          source == other.source &&
          nodeId == other.nodeId &&
          outputName == other.outputName &&
          varId == other.varId &&
          funcId == other.funcId &&
          componentId == other.componentId &&
          fieldName == other.fieldName;

  @override
  int get hashCode =>
      Object.hash(source, nodeId, outputName, varId, funcId, componentId, fieldName);

  Map<String, dynamic> toJson() => {
        'source': source.toJson(),
        if (nodeId != null) 'nodeId': nodeId,
        if (outputName != null) 'outputName': outputName,
        if (varId != null) 'varId': varId,
        if (funcId != null) 'funcId': funcId,
        if (componentId != null) 'componentId': componentId,
        if (fieldName != null) 'fieldName': fieldName,
      };

  factory VariableRef.fromJson(Map<String, dynamic> json) => VariableRef(
        source: VariableSource.fromJson(json['source']),
        nodeId: json['nodeId'] as String?,
        outputName: json['outputName'] as String?,
        varId: json['varId'] as String?,
        funcId: json['funcId'] as String?,
        componentId: json['componentId'] as String?,
        fieldName: json['fieldName'] as String?,
      );

  @override
  String toString() {
    switch (source) {
      case VariableSource.upstream:
        return 'VariableRef(#$nodeId.$outputName)';
      case VariableSource.funcVar:
        if (isPageFunc) return 'VariableRef(#pageFunc:$funcId.$outputName)';
        return 'VariableRef(#func:$varId)';
      case VariableSource.projVar:
        return 'VariableRef(#proj:$varId)';
      case VariableSource.component:
        return 'VariableRef(#comp:$componentId.$fieldName)';
    }
  }
}
