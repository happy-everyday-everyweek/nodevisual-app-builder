/// 变量引用来源类型。
///
/// 对应 `#` 作用域三类来源：控制流上游节点输出、函数变量、项目变量。
enum VariableSource {
  /// 控制流上游节点的命名数据输出（需配合 [VariableRef.nodeId] + [VariableRef.outputName]）。
  upstream,

  /// 当前函数的局部变量（需配合 [VariableRef.varId]）。
  funcVar,

  /// 项目级变量（需配合 [VariableRef.varId]）。
  projVar;

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
/// `#` 引用 [VariableRef] 拼装。`#` 作用域 = 控制流上游节点输出
/// + 函数变量 + 项目变量。
///
/// 字段约束：
/// - [source] == [VariableSource.upstream]：[nodeId] 与 [outputName] 必填。
/// - [source] == [VariableSource.funcVar]：[varId] 必填。
/// - [source] == [VariableSource.projVar]：[varId] 必填。
class VariableRef {
  /// 引用来源。
  final VariableSource source;

  /// 上游节点 id（仅 [VariableSource.upstream] 有效）。
  final String? nodeId;

  /// 上游节点命名数据输出名（仅 [VariableSource.upstream] 有效）。
  final String? outputName;

  /// 变量 id（[VariableSource.funcVar] / [VariableSource.projVar] 有效）。
  final String? varId;

  const VariableRef({
    required this.source,
    this.nodeId,
    this.outputName,
    this.varId,
  });

  /// 便捷构造：引用上游节点输出。
  const VariableRef.upstream({
    required String nodeId,
    required String outputName,
  })  : source = VariableSource.upstream,
        nodeId = nodeId,
        outputName = outputName,
        varId = null;

  /// 便捷构造：引用函数变量。
  const VariableRef.funcVar({required String varId})
      : source = VariableSource.funcVar,
        varId = varId,
        nodeId = null,
        outputName = null;

  /// 便捷构造：引用项目变量。
  const VariableRef.projVar({required String varId})
      : source = VariableSource.projVar,
        varId = varId,
        nodeId = null,
        outputName = null;

  VariableRef copyWith({
    VariableSource? source,
    String? nodeId,
    String? outputName,
    String? varId,
  }) =>
      VariableRef(
        source: source ?? this.source,
        nodeId: nodeId ?? this.nodeId,
        outputName: outputName ?? this.outputName,
        varId: varId ?? this.varId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VariableRef &&
          source == other.source &&
          nodeId == other.nodeId &&
          outputName == other.outputName &&
          varId == other.varId;

  @override
  int get hashCode => Object.hash(source, nodeId, outputName, varId);

  Map<String, dynamic> toJson() => {
        'source': source.toJson(),
        if (nodeId != null) 'nodeId': nodeId,
        if (outputName != null) 'outputName': outputName,
        if (varId != null) 'varId': varId,
      };

  factory VariableRef.fromJson(Map<String, dynamic> json) => VariableRef(
        source: VariableSource.fromJson(json['source']),
        nodeId: json['nodeId'] as String?,
        outputName: json['outputName'] as String?,
        varId: json['varId'] as String?,
      );

  @override
  String toString() {
    switch (source) {
      case VariableSource.upstream:
        return 'VariableRef(#$nodeId.$outputName)';
      case VariableSource.funcVar:
        return 'VariableRef(#func:$varId)';
      case VariableSource.projVar:
        return 'VariableRef(#proj:$varId)';
    }
  }
}
