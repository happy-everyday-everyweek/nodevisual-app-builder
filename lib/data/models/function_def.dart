import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'control_edge.dart';
import 'entry.dart';
import 'func_param.dart';
import 'node.dart';
import 'port.dart';
import 'variable_ref.dart';

const DeepCollectionEquality _funcDeepEq = DeepCollectionEquality();
const Uuid _migrateUuid = Uuid();

/// 函数局部变量定义。
///
/// 属于 `#` 作用域的"函数变量"来源，仅在该函数的节点编辑页内
/// 可通过 `#func:<varId>` 引用。生命周期与函数实例绑定。
class FunctionVariable {
  /// 唯一标识（在函数内唯一）。
  final String id;

  /// 变量名。
  final String name;

  /// 变量类型。
  final PortType type;

  /// 默认值。
  final Object? defaultValue;

  /// 是否为入参（兼容旧 IR：true 时参与默认签名推导）。
  final bool isInput;

  const FunctionVariable({
    required this.id,
    required this.name,
    required this.type,
    this.defaultValue,
    this.isInput = false,
  });

  FunctionVariable copyWith({
    String? id,
    String? name,
    PortType? type,
    Object? defaultValue,
    bool? isInput,
  }) =>
      FunctionVariable(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        defaultValue: defaultValue ?? this.defaultValue,
        isInput: isInput ?? this.isInput,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionVariable &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          defaultValue == other.defaultValue &&
          isInput == other.isInput;

  @override
  int get hashCode => Object.hash(id, name, type, defaultValue, isInput);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.toJson(),
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (isInput) 'isInput': true,
      };

  factory FunctionVariable.fromJson(Map<String, dynamic> json) =>
      FunctionVariable(
        id: json['id'] as String,
        name: json['name'] as String,
        type: PortType.fromJson(json['type']),
        defaultValue: json['defaultValue'],
        isInput: (json['isInput'] as bool?) ?? false,
      );

  @override
  String toString() => 'FunctionVariable($name: $type)';
}

/// 函数定义（函数段的核心 IR 容器）。
///
/// 一个 [FunctionDef] = 入口（[entry]，函数触发模型）
/// + 节点图（[nodes] + [controlEdges]，双平面模型的控制流平面）
/// + 函数变量（[funcVars]，`#` 作用域的函数变量来源）
/// + 显式签名（[inputs] / [outputs]，供 `function_call` 节点动态生成端口）。
///
/// 数据平面通过节点 [Node.params] 内的 `#` 引用（[VariableRef]）完成，
/// 与 [controlEdges] 解耦。
///
/// **签名迁移规则**：既有无签名函数（inputs/outputs 为空）加载时，
/// 由 [migrateSignature] 自动推导：inputs = funcVars 中 `isInput==true` 项；
/// outputs = 空（沿用 return 节点的 `value` 单返回语义）。
class FunctionDef {
  /// 唯一标识。
  final String id;

  /// 函数名（在项目内唯一）。
  final String name;

  /// 标签（用于检索与分组）。
  final List<String> tags;

  /// 所属文件夹 id（顶层为 null）。
  final String? folderId;

  /// 函数入口（声明触发方式），无则需被显式调用。
  final FunctionEntry? entry;

  /// 函数局部变量。
  final List<FunctionVariable> funcVars;

  /// 显式入参签名。
  ///
  /// 由用户在签名面板编辑。`function_call` 节点按此动态生成参数端口。
  /// 既有无签名函数通过 [migrateSignature] 推导为空 inputs（兼容旧 IR）。
  final List<FuncParam> inputs;

  /// 显式出参签名。
  ///
  /// 由用户在签名面板编辑。`function_call` 节点按此动态生成命名数据输出端口。
  /// `return` 节点按 [outputs] 名映射返回多值。空 outputs 时沿用单返回值 `value`。
  final List<FuncParam> outputs;

  /// 节点列表。
  final List<Node> nodes;

  /// 控制流连线列表（仅表达执行顺序与分支，无类型校验）。
  final List<ControlEdge> controlEdges;

  /// 函数版本号（每次退出编辑器自动保存时 +1，从 1 开始）。
  ///
  /// 用于追踪编辑会话次数。0 / 缺省值在 [fromJson] 中归一化为 1。
  final int version;

  const FunctionDef({
    required this.id,
    required this.name,
    this.tags = const [],
    this.folderId,
    this.entry,
    this.funcVars = const [],
    this.inputs = const [],
    this.outputs = const [],
    this.nodes = const [],
    this.controlEdges = const [],
    this.version = 1,
  });

  FunctionDef copyWith({
    String? id,
    String? name,
    List<String>? tags,
    String? folderId,
    Object? entry = _sentinel,
    List<FunctionVariable>? funcVars,
    List<FuncParam>? inputs,
    List<FuncParam>? outputs,
    List<Node>? nodes,
    List<ControlEdge>? controlEdges,
    int? version,
  }) =>
      FunctionDef(
        id: id ?? this.id,
        name: name ?? this.name,
        tags: tags ?? this.tags,
        folderId: folderId ?? this.folderId,
        entry: identical(entry, _sentinel) ? this.entry : entry as FunctionEntry?,
        funcVars: funcVars ?? this.funcVars,
        inputs: inputs ?? this.inputs,
        outputs: outputs ?? this.outputs,
        nodes: nodes ?? this.nodes,
        controlEdges: controlEdges ?? this.controlEdges,
        version: version ?? this.version,
      );

  /// 推导既有无签名函数的默认签名。
  ///
  /// 规则：
  /// - inputs = funcVars 中 `isInput==true` 项（按声明序，转为 [FuncParam]）。
  /// - outputs = 空（沿用 return 节点的 `value` 单返回语义，向后兼容）。
  ///
  /// 既有函数已有 inputs/outputs 时直接返回原值。
  FunctionDef migrateSignature() {
    if (inputs.isNotEmpty || outputs.isNotEmpty) return this;
    if (funcVars.isEmpty || funcVars.every((v) => !v.isInput)) return this;
    final derivedInputs = funcVars
        .where((v) => v.isInput)
        .map((v) => FuncParam(
              name: v.name,
              type: v.type,
              defaultValue: v.defaultValue,
            ))
        .toList(growable: false);
    return copyWith(inputs: derivedInputs);
  }

  /// 节点级迁移：补全入参/出参节点，转换旧 return 节点为 function_output。
  ///
  /// 旧项目（无 function_input/function_output 节点）加载时自动迁移：
  /// - 第一个 return 节点 → 转换为 function_output 节点（保留 values 映射，
  ///   单返回 value 转换为 `{'value': value}` 形式）
  /// - 其余 return 节点 → 删除（含关联边）
  /// - 若无 return 节点可转换，补充一个空的 function_output 节点
  /// - 若无 function_input 节点，补充一个（dataOutputs 来自 inputs 签名）
  ///
  /// 已有 function_input/function_output 节点的函数直接返回原值（幂等）。
  FunctionDef migrateNodes() {
    final hasInput = nodes.any((n) => n.kind == 'function_input');
    var hasOutput = nodes.any((n) => n.kind == 'function_output');
    if (hasInput && hasOutput) return this;

    var newNodes = List<Node>.from(nodes);
    var newEdges = List<ControlEdge>.from(controlEdges);

    // return → function_output 转换（仅第一个 return，其余删除）。
    if (!hasOutput) {
      int? firstReturnIdx;
      for (var i = 0; i < newNodes.length; i++) {
        if (newNodes[i].kind == 'return') {
          firstReturnIdx = i;
          break;
        }
      }
      if (firstReturnIdx != null) {
        final returnNode = newNodes[firstReturnIdx];
        // 合并 values：优先用多返回 values，否则单返回 value 包成 {'value': ...}。
        final values = <String, dynamic>{};
        final rawValues = returnNode.params['values'];
        if (rawValues is Map && rawValues.isNotEmpty) {
          for (final entry in rawValues.entries) {
            values[entry.key.toString()] = entry.value;
          }
        } else if (returnNode.params['value'] != null) {
          values['value'] = returnNode.params['value'];
        }
        newNodes[firstReturnIdx] = returnNode.copyWith(
          kind: 'function_output',
          params: {'values': values, 'name': '出参'},
          controlOutputs: const [],
          dataOutputs: const [],
        );
        // 删除其余 return 节点（及其关联边）。
        final returnIds = newNodes
            .where((n) => n.kind == 'return')
            .map((n) => n.id)
            .toSet();
        newNodes = newNodes.where((n) => n.kind != 'return').toList();
        newEdges = newEdges
            .where((e) =>
                !returnIds.contains(e.fromNode) &&
                !returnIds.contains(e.toNode))
            .toList();
        hasOutput = true;
      }
    }

    // 无 return 可转换 → 补充空 function_output 节点。
    if (!hasOutput) {
      newNodes.add(Node(
        id: _migrateUuid.v4(),
        kind: 'function_output',
        params: const {'name': '出参'},
        position: const NodePosition(x: 300, y: 0),
      ));
    }

    // 补充 function_input 节点（dataOutputs 来自 inputs 签名）。
    if (!hasInput) {
      newNodes.add(Node(
        id: _migrateUuid.v4(),
        kind: 'function_input',
        params: const {'name': '入参'},
        position: const NodePosition(x: -300, y: 0),
        controlOutputs: const [ControlOutput(name: 'next')],
        dataOutputs: [
          for (final p in inputs) DataOutput(name: p.name, type: p.type),
        ],
      ));
    }

    return copyWith(nodes: newNodes, controlEdges: newEdges);
  }

  /// 节点级迁移：把旧 `device_var` 节点 + 下游 `upstream` 引用迁移为
  /// `#device:<property>` 直接引用。
  ///
  /// 旧 IR 中 `device_var` 是一个节点，下游节点通过
  /// `VariableRef.upstream(nodeId: <device_var_id>, outputName: 'value')`
  /// 引用其 `value` 输出。新 IR 中设备变量改为 `#device:<property>` 引用源，
  /// 不再是节点。
  ///
  /// 迁移步骤：
  /// 1. 收集所有 `device_var` 节点的 `{id → property}` 映射；
  /// 2. 遍历剩余节点的 params，把指向 device_var 节点的 upstream 引用替换为
  ///    `VariableRef.device(property: <对应 property>)`；
  /// 3. 删除所有 device_var 节点（及其关联边）。
  ///
  /// 已无 device_var 节点的函数直接返回原值（幂等）。
  FunctionDef migrateDeviceVar() {
    final deviceVarNodes = nodes.where((n) => n.kind == 'device_var').toList();
    if (deviceVarNodes.isEmpty) return this;

    // 1. 建立 {device_var_id → property} 映射。
    final propMap = <String, String>{};
    for (final n in deviceVarNodes) {
      final prop = n.params['property']?.toString() ?? 'deviceType';
      propMap[n.id] = prop;
    }

    // 2. 把所有节点的 params 中指向 device_var 节点的 upstream 引用替换为
    //    VariableRef.device(property: ...)。
    final newNodes = <Node>[];
    for (final n in nodes) {
      if (n.kind == 'device_var') continue; // 删除 device_var 节点
      if (n.params.isEmpty) {
        newNodes.add(n);
        continue;
      }
      final newParams = <String, dynamic>{};
      bool changed = false;
      for (final entry in n.params.entries) {
        final v = entry.value;
        if (v is Map<String, dynamic> && v.containsKey('source')) {
          final ref = VariableRef.fromJson(v);
          if (ref.source == VariableSource.upstream &&
              ref.nodeId != null &&
              propMap.containsKey(ref.nodeId)) {
            newParams[entry.key] = VariableRef.device(property: propMap[ref.nodeId]!).toJson();
            changed = true;
            continue;
          }
        }
        newParams[entry.key] = v;
      }
      newNodes.add(changed ? n.copyWith(params: newParams) : n);
    }

    // 3. 删除 device_var 节点关联的边。
    final removedIds = deviceVarNodes.map((n) => n.id).toSet();
    final newEdges = controlEdges
        .where((e) =>
            !removedIds.contains(e.fromNode) && !removedIds.contains(e.toNode))
        .toList(growable: false);

    return copyWith(nodes: newNodes, controlEdges: newEdges);
  }

  /// 节点级迁移：把旧 `variable_set` 节点的 `varName` 参数迁移为新的
  /// `target` + `varId` 形式。
  ///
  /// 旧 IR：`{varName: "<函数变量名>", value: ...}` 仅支持当前函数变量。
  /// 新 IR：`{target: "funcVar"|"projVar", varId: "<varId>", value: ...}`，
  /// 其中 varId 是变量 id 而非变量名。
  ///
  /// 迁移规则：按 varName 在当前函数 funcVars 中匹配，命中则写入 varId；
  /// 未命中保持原样（运行时会跳过空 varId）。
  ///
  /// 已是新格式（有 target 或 varId 参数）的节点直接返回原值（幂等）。
  FunctionDef migrateVariableSet() {
    bool needs = false;
    for (final n in nodes) {
      if (n.kind == 'variable_set' &&
          !n.params.containsKey('target') &&
          !n.params.containsKey('varId') &&
          n.params.containsKey('varName')) {
        needs = true;
        break;
      }
    }
    if (!needs) return this;

    final newNodes = <Node>[];
    for (final n in nodes) {
      if (n.kind != 'variable_set' ||
          n.params.containsKey('target') ||
          n.params.containsKey('varId') ||
          !n.params.containsKey('varName')) {
        newNodes.add(n);
        continue;
      }
      final varName = n.params['varName']?.toString() ?? '';
      String? varId;
      for (final v in funcVars) {
        if (v.name == varName) {
          varId = v.id;
          break;
        }
      }
      final newParams = Map<String, dynamic>.from(n.params);
      newParams.remove('varName');
      newParams['target'] = 'funcVar';
      if (varId != null) {
        newParams['varId'] = varId;
      }
      newNodes.add(n.copyWith(params: newParams));
    }
    return copyWith(nodes: newNodes);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionDef &&
          id == other.id &&
          name == other.name &&
          _funcDeepEq.equals(tags, other.tags) &&
          folderId == other.folderId &&
          entry == other.entry &&
          _funcDeepEq.equals(funcVars, other.funcVars) &&
          _funcDeepEq.equals(inputs, other.inputs) &&
          _funcDeepEq.equals(outputs, other.outputs) &&
          _funcDeepEq.equals(nodes, other.nodes) &&
          _funcDeepEq.equals(controlEdges, other.controlEdges) &&
          version == other.version;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        folderId,
        entry,
        Object.hashAll(funcVars),
        Object.hashAll(inputs),
        Object.hashAll(outputs),
        Object.hashAll(nodes),
        Object.hashAll(controlEdges),
        version,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (tags.isNotEmpty) 'tags': tags,
        if (folderId != null) 'folderId': folderId,
        if (entry != null) 'entry': entry!.toJson(),
        if (funcVars.isNotEmpty)
          'funcVars': funcVars.map((e) => e.toJson()).toList(),
        if (inputs.isNotEmpty) 'inputs': inputs.map((e) => e.toJson()).toList(),
        if (outputs.isNotEmpty)
          'outputs': outputs.map((e) => e.toJson()).toList(),
        if (nodes.isNotEmpty) 'nodes': nodes.map((e) => e.toJson()).toList(),
        if (controlEdges.isNotEmpty)
          'controlEdges': controlEdges.map((e) => e.toJson()).toList(),
        if (version > 1) 'version': version,
      };

  factory FunctionDef.fromJson(Map<String, dynamic> json) => FunctionDef(
        id: json['id'] as String,
        name: json['name'] as String,
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        folderId: json['folderId'] as String?,
        entry: json['entry'] == null
            ? null
            : FunctionEntry.fromJson(json['entry'] as Map<String, dynamic>),
        funcVars: (json['funcVars'] as List<dynamic>?)
                ?.map((e) =>
                    FunctionVariable.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        inputs: (json['inputs'] as List<dynamic>?)
                ?.map((e) => FuncParam.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        outputs: (json['outputs'] as List<dynamic>?)
                ?.map((e) => FuncParam.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        nodes: (json['nodes'] as List<dynamic>?)
                ?.map((e) => Node.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        controlEdges: (json['controlEdges'] as List<dynamic>?)
                ?.map((e) => ControlEdge.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        version: (json['version'] as num?)?.toInt() ?? 1,
      ).migrateSignature().migrateNodes().migrateDeviceVar().migrateVariableSet();

  @override
  String toString() => 'FunctionDef($name#$id)';
}

const Object _sentinel = Object();
