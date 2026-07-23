import 'package:collection/collection.dart';

import 'control_edge.dart';
import 'entry.dart';
import 'node.dart';
import 'port.dart';

const DeepCollectionEquality _funcDeepEq = DeepCollectionEquality();

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

  const FunctionVariable({
    required this.id,
    required this.name,
    required this.type,
    this.defaultValue,
  });

  FunctionVariable copyWith({
    String? id,
    String? name,
    PortType? type,
    Object? defaultValue,
  }) =>
      FunctionVariable(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        defaultValue: defaultValue ?? this.defaultValue,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionVariable &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          defaultValue == other.defaultValue;

  @override
  int get hashCode => Object.hash(id, name, type, defaultValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.toJson(),
        if (defaultValue != null) 'defaultValue': defaultValue,
      };

  factory FunctionVariable.fromJson(Map<String, dynamic> json) =>
      FunctionVariable(
        id: json['id'] as String,
        name: json['name'] as String,
        type: PortType.fromJson(json['type']),
        defaultValue: json['defaultValue'],
      );

  @override
  String toString() => 'FunctionVariable($name: $type)';
}

/// 函数定义（函数段的核心 IR 容器）。
///
/// 一个 [FunctionDef] = 入口（[entry]，函数触发模型）
/// + 节点图（[nodes] + [controlEdges]，双平面模型的控制流平面）
/// + 函数变量（[funcVars]，`#` 作用域的函数变量来源）。
///
/// 数据平面通过节点 [Node.params] 内的 `#` 引用（[VariableRef]）完成，
/// 与 [controlEdges] 解耦。
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

  /// 节点列表。
  final List<Node> nodes;

  /// 控制流连线列表（仅表达执行顺序与分支，无类型校验）。
  final List<ControlEdge> controlEdges;

  const FunctionDef({
    required this.id,
    required this.name,
    this.tags = const [],
    this.folderId,
    this.entry,
    this.funcVars = const [],
    this.nodes = const [],
    this.controlEdges = const [],
  });

  FunctionDef copyWith({
    String? id,
    String? name,
    List<String>? tags,
    String? folderId,
    Object? entry = _sentinel,
    List<FunctionVariable>? funcVars,
    List<Node>? nodes,
    List<ControlEdge>? controlEdges,
  }) =>
      FunctionDef(
        id: id ?? this.id,
        name: name ?? this.name,
        tags: tags ?? this.tags,
        folderId: folderId ?? this.folderId,
        entry: identical(entry, _sentinel) ? this.entry : entry as FunctionEntry?,
        funcVars: funcVars ?? this.funcVars,
        nodes: nodes ?? this.nodes,
        controlEdges: controlEdges ?? this.controlEdges,
      );

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
          _funcDeepEq.equals(nodes, other.nodes) &&
          _funcDeepEq.equals(controlEdges, other.controlEdges);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        folderId,
        entry,
        Object.hashAll(funcVars),
        Object.hashAll(nodes),
        Object.hashAll(controlEdges),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (tags.isNotEmpty) 'tags': tags,
        if (folderId != null) 'folderId': folderId,
        if (entry != null) 'entry': entry!.toJson(),
        if (funcVars.isNotEmpty)
          'funcVars': funcVars.map((e) => e.toJson()).toList(),
        if (nodes.isNotEmpty) 'nodes': nodes.map((e) => e.toJson()).toList(),
        if (controlEdges.isNotEmpty)
          'controlEdges': controlEdges.map((e) => e.toJson()).toList(),
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
        nodes: (json['nodes'] as List<dynamic>?)
                ?.map((e) => Node.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        controlEdges: (json['controlEdges'] as List<dynamic>?)
                ?.map((e) => ControlEdge.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() => 'FunctionDef($name#$id)';
}

const Object _sentinel = Object();
