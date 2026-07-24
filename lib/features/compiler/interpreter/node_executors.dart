import 'dart:convert';

import '../../../data/models/control_edge.dart';
import '../../../data/models/db_schema.dart';
import '../../../data/models/function_def.dart';
import '../../../data/models/node.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variable_ref.dart';
import '../../plugins/plugin_config_storage.dart';
import '../../plugins/plugin_registry.dart';
import 'database_executor.dart';
import 'runtime_scope.dart';

/// 函数执行结果。
///
/// 由 [NodeInterpreter.runFunction] / [NodeInterpreter.runFromNode] 返回。
/// - [outputs]：函数输出（return 节点的值放在 `'value'` key 下）。
/// - [error]：执行错误（null 表示无错误）。
/// - [didReturn]：是否命中 return 节点终止（用于 loop body 内 return 向上传播）。
class RunResult {
  /// 函数输出。
  final Map<String, dynamic> outputs;

  /// 执行错误（null 表示无错误）。
  final String? error;

  /// 是否命中 return 节点终止。
  final bool didReturn;

  const RunResult({
    this.outputs = const {},
    this.error,
    this.didReturn = false,
  });
}

/// 节点执行结果。
///
/// 由 [executeNode] 返回，描述节点执行后的数据输出与控制流走向。
class NodeExecResult {
  /// 节点数据输出（key = 输出名，value = 输出值）。
  /// 由调用方写入 [RuntimeScope.nodeOutputs]（key = `"${nodeId}.${outputName}"`）。
  final Map<String, dynamic> dataOutputs;

  /// 下一个控制流输出端口名（null 表示终止节点，如 return 或无后续分支）。
  final String? nextControlOutput;

  /// 是否为 return 节点（终止函数执行并返回值）。
  final bool isReturn;

  /// return 节点的返回值（仅 [isReturn] 为 true 时有效）。
  final Object? returnValue;

  const NodeExecResult({
    this.dataOutputs = const {},
    this.nextControlOutput,
    this.isReturn = false,
    this.returnValue,
  });
}

/// 解释器宿主接口（供节点执行器回调递归执行）。
///
/// [NodeInterpreter] 实现本接口；[ExecContext] 持有本接口以避免
/// `node_executors.dart` ↔ `node_interpreter.dart` 循环依赖。
abstract class InterpreterHost {
  /// 执行函数（创建新作用域，初始化变量，从入口节点执行）。
  Future<RunResult> runFunction(
    FunctionDef function,
    Map<String, dynamic> inputs,
  );

  /// 从指定节点开始执行控制流（共享 [scope]）。
  Future<RunResult> runFromNode(
    FunctionDef function,
    String nodeId,
    RuntimeScope scope,
  );
}

/// 节点执行上下文，封装执行单个节点所需的全部依赖。
class ExecContext {
  /// 待执行节点。
  final Node node;

  /// 节点所属函数。
  final FunctionDef function;

  /// 所属项目（用于 function_call 查找目标函数、db 节点读取 schema）。
  final Project project;

  /// 当前运行时作用域。
  final RuntimeScope scope;

  /// 解释器宿主（用于 loop body 与 function_call 递归执行）。
  final InterpreterHost interpreter;

  /// 插件注册表。
  final PluginRegistry pluginRegistry;

  /// 插件配置存储（用于读取 API Key 等），可空。
  final PluginConfigStorage? pluginConfigStorage;

  /// 数据库执行器，可空（为空时 db_* 节点抛错）。
  final DatabaseExecutor? dbExecutor;

  const ExecContext({
    required this.node,
    required this.function,
    required this.project,
    required this.scope,
    required this.interpreter,
    required this.pluginRegistry,
    this.pluginConfigStorage,
    this.dbExecutor,
  });
}

/// 解析节点 params 中的 `#` 引用或字面值。
///
/// - 若 [value] 是 [VariableRef] 的 JSON 形式（Map 含 `'source'` key），
///   按 [VariableSource] 从 [scope] 取值。
/// - 否则视为字面值，直接返回。
///
/// 这是节点解释器的核心：确保 `#` 引用能取到上游节点输出 / 函数变量 /
/// 项目变量的运行时值。
Object? resolveRef(Object? value, RuntimeScope scope) {
  if (value is Map<String, dynamic> && value.containsKey('source')) {
    final ref = VariableRef.fromJson(value);
    return _resolveVariableRef(ref, scope);
  }
  return value;
}

Object? _resolveVariableRef(VariableRef ref, RuntimeScope scope) {
  switch (ref.source) {
    case VariableSource.upstream:
      if (ref.nodeId == null || ref.outputName == null) return null;
      return scope.getNodeOutput(ref.nodeId!, ref.outputName!);
    case VariableSource.funcVar:
      if (ref.varId == null) return null;
      return scope.getFuncVar(ref.varId!);
    case VariableSource.projVar:
      if (ref.varId == null) return null;
      return scope.getProjVar(ref.varId!);
  }
}

/// 执行节点（按 [Node.kind] 分发）。
///
/// 每种 kind 的执行逻辑在下方对应的 `_execXxx` 函数中实现。
/// 异常由调用方（[NodeInterpreter]）捕获并记录到 [RunResult.error]。
Future<NodeExecResult> executeNode(ExecContext ctx) async {
  switch (ctx.node.kind) {
    case 'variable_set':
      return _execVariableSet(ctx);
    case 'variable_get':
      return _execVariableGet(ctx);
    case 'arithmetic':
      return _execArithmetic(ctx);
    case 'logic':
      return _execLogic(ctx);
    case 'string_op':
      return _execStringOp(ctx);
    case 'if':
      return _execIf(ctx);
    case 'loop':
      return _execLoop(ctx);
    case 'function_call':
      return _execFunctionCall(ctx);
    case 'return':
      return _execReturn(ctx);
    case 'db_query':
      return _execDbQuery(ctx);
    case 'db_insert':
      return _execDbInsert(ctx);
    case 'db_update':
      return _execDbUpdate(ctx);
    case 'db_delete':
      return _execDbDelete(ctx);
    case 'db_create_table':
      return _execDbCreateTable(ctx);
    case 'db_alter_table':
      return _execDbAlterTable(ctx);
    case 'plugin_openai':
      return _execPlugin(ctx, 'llm_openai');
    case 'plugin_anthropic':
      return _execPlugin(ctx, 'llm_anthropic');
    default:
      // 市场插件节点（kind = plugin_<id>）：提取 pluginId 并执行。
      if (ctx.node.kind.startsWith('plugin_')) {
        final pluginId = ctx.node.params['pluginId']?.toString() ??
            ctx.node.kind.substring(7);
        return _execPlugin(ctx, pluginId);
      }
      // 未知 kind：按约定走 next 控制流输出（不产出数据）。
      return const NodeExecResult(nextControlOutput: 'next');
  }
}

// ===========================================================================
// 变量节点
// ===========================================================================

/// variable_set：scope[funcVar 或动态] = resolveRef(params['value'])。
Future<NodeExecResult> _execVariableSet(ExecContext ctx) async {
  final params = ctx.node.params;
  final varName = params['varName']?.toString() ?? '';
  final value = resolveRef(params['value'], ctx.scope);
  // 按名匹配函数变量并赋值。
  if (varName.isNotEmpty) {
    for (final v in ctx.function.funcVars) {
      if (v.name == varName) {
        ctx.scope.setFuncVar(v.id, value);
        break;
      }
    }
  }
  return const NodeExecResult(nextControlOutput: 'next');
}

/// variable_get：dataOutputs[value] = scope[params['varName']]。
Future<NodeExecResult> _execVariableGet(ExecContext ctx) async {
  final params = ctx.node.params;
  final varName = params['varName']?.toString() ?? '';
  Object? value;
  for (final v in ctx.function.funcVars) {
    if (v.name == varName) {
      value = ctx.scope.getFuncVar(v.id);
      break;
    }
  }
  return NodeExecResult(
    dataOutputs: {'value': value},
    nextControlOutput: 'next',
  );
}

// ===========================================================================
// 运算节点
// ===========================================================================

/// arithmetic：a=resolveRef(params['a']), b=resolveRef(params['b'])，
/// 按 operator 计算，dataOutputs[result]。
Future<NodeExecResult> _execArithmetic(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operator']?.toString() ?? '+';
  final a = _toNum(resolveRef(params['a'], ctx.scope));
  final b = _toNum(resolveRef(params['b'], ctx.scope));
  num result;
  switch (op) {
    case '+':
      result = (a ?? 0) + (b ?? 0);
      break;
    case '-':
      result = (a ?? 0) - (b ?? 0);
      break;
    case '*':
      result = (a ?? 0) * (b ?? 0);
      break;
    case '/':
      if (b == null || b == 0) {
        throw StateError('除数为零');
      }
      result = a! / b;
      break;
    case '%':
      if (b == null || b == 0) {
        throw StateError('取模数为零');
      }
      result = a!.toInt() % b.toInt();
      break;
    default:
      throw StateError('未知运算符: $op');
  }
  return NodeExecResult(
    dataOutputs: {'result': result},
    nextControlOutput: 'next',
  );
}

/// logic：按 operator（and/or/not）计算。
Future<NodeExecResult> _execLogic(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operator']?.toString() ?? 'and';
  final a = _toBool(resolveRef(params['a'], ctx.scope));
  final b = _toBool(resolveRef(params['b'], ctx.scope));
  bool result;
  switch (op) {
    case 'and':
      result = a && b;
      break;
    case 'or':
      result = a || b;
      break;
    case 'not':
      result = !a;
      break;
    default:
      throw StateError('未知逻辑运算符: $op');
  }
  return NodeExecResult(
    dataOutputs: {'result': result},
    nextControlOutput: 'next',
  );
}

/// string_op：按 operation（concat/substring/upper/lower/length）。
Future<NodeExecResult> _execStringOp(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operation']?.toString() ?? 'concat';
  final a = resolveRef(params['a'], ctx.scope)?.toString() ?? '';
  final b = resolveRef(params['b'], ctx.scope)?.toString() ?? '';
  switch (op) {
    case 'concat':
      return NodeExecResult(
        dataOutputs: {'result': a + b},
        nextControlOutput: 'next',
      );
    case 'substring':
      // b 形如 "start,end" 或 "start"。
      final parts = b.split(',');
      final start = (int.tryParse(parts[0]) ?? 0).clamp(0, a.length);
      final end = parts.length > 1
          ? (int.tryParse(parts[1]) ?? a.length).clamp(0, a.length)
          : a.length;
      return NodeExecResult(
        dataOutputs: {'result': a.substring(start, end)},
        nextControlOutput: 'next',
      );
    case 'upper':
      return NodeExecResult(
        dataOutputs: {'result': a.toUpperCase()},
        nextControlOutput: 'next',
      );
    case 'lower':
      return NodeExecResult(
        dataOutputs: {'result': a.toLowerCase()},
        nextControlOutput: 'next',
      );
    case 'length':
      return NodeExecResult(
        dataOutputs: {'length': a.length},
        nextControlOutput: 'next',
      );
    default:
      throw StateError('未知字符串操作: $op');
  }
}

// ===========================================================================
// 流程控制节点
// ===========================================================================

/// if：cond=resolveRef(params['condition'])；遍历 params['cases']，
/// 找匹配 case（条件值字符串化后与 case 名匹配），返回对应 controlOutput 名；
/// 无匹配走 default（若 includeDefault）。
Future<NodeExecResult> _execIf(ExecContext ctx) async {
  final params = ctx.node.params;
  final rawCond = resolveRef(params['condition'], ctx.scope);
  final condStr = rawCond?.toString().toLowerCase() ?? '';
  final cases = <String>[];
  final rawCases = params['cases'];
  if (rawCases is List) {
    cases.addAll(rawCases.map((e) => e.toString()));
  }
  if (cases.isEmpty) {
    cases.addAll(['true', 'false']);
  }
  final includeDefault = params['includeDefault'] == true;

  // 条件值字符串化后与 case 名（大小写不敏感）匹配。
  for (final c in cases) {
    if (c.toLowerCase() == condStr) {
      return NodeExecResult(nextControlOutput: c);
    }
  }
  if (includeDefault) {
    return const NodeExecResult(nextControlOutput: 'default');
  }
  // 无匹配且无 default，终止。
  return const NodeExecResult();
}

/// loop：count=resolveRef(params['count'])；for i in 0..count-1：
/// 执行 body 子图（递归 runFromNode），scope[index]=i；循环完走 completed。
///
/// body 子图内若命中 return 节点，向上传播终止函数。
Future<NodeExecResult> _execLoop(ExecContext ctx) async {
  final params = ctx.node.params;
  final mode = params['mode']?.toString() ?? 'count';
  const maxIter = 100000; // 安全上限，防止死循环。

  if (mode == 'count') {
    final count = _toInt(resolveRef(params['count'], ctx.scope));
    if (count > maxIter) {
      throw StateError('循环次数 $count 超过上限 $maxIter');
    }
    for (var i = 0; i < count; i++) {
      ctx.scope.setNodeOutput(ctx.node.id, 'index', i);
      final bodyResult = await _runSubGraph(ctx, 'body');
      if (bodyResult.isReturn) {
        return NodeExecResult(
          isReturn: true,
          returnValue: bodyResult.returnValue,
        );
      }
    }
    ctx.scope.setNodeOutput(ctx.node.id, 'index', count - 1);
    return const NodeExecResult(nextControlOutput: 'completed');
  } else {
    // condition 模式：每次迭代前求值 condition。
    var iter = 0;
    while (_toBool(resolveRef(params['condition'], ctx.scope))) {
      if (iter++ >= maxIter) {
        throw StateError('条件循环超过 $maxIter 次迭代');
      }
      ctx.scope.setNodeOutput(ctx.node.id, 'index', iter - 1);
      final bodyResult = await _runSubGraph(ctx, 'body');
      if (bodyResult.isReturn) {
        return NodeExecResult(
          isReturn: true,
          returnValue: bodyResult.returnValue,
        );
      }
    }
    return const NodeExecResult(nextControlOutput: 'completed');
  }
}

/// loop body 子图执行结果（内部类型，仅用于 return 传播检测）。
class _SubGraphResult {
  final bool isReturn;
  final Object? returnValue;

  const _SubGraphResult({required this.isReturn, this.returnValue});
}

/// 执行 loop 节点 [portName]（body）对应的子图。
Future<_SubGraphResult> _runSubGraph(ExecContext ctx, String portName) async {
  ControlEdge? edge;
  for (final e in ctx.function.controlEdges) {
    if (e.fromNode == ctx.node.id && e.fromPort == portName) {
      edge = e;
      break;
    }
  }
  if (edge == null) {
    return const _SubGraphResult(isReturn: false);
  }
  // 递归执行 body 子图（共享 scope，body 内可引用 loop 的 index 输出）。
  final result = await ctx.interpreter.runFromNode(
    ctx.function,
    edge.toNode,
    ctx.scope,
  );
  return _SubGraphResult(
    isReturn: result.didReturn,
    returnValue: result.outputs['value'],
  );
}

/// function_call：target=项目内函数；args=resolveRef 各参数；递归 runFunction。
Future<NodeExecResult> _execFunctionCall(ExecContext ctx) async {
  final params = ctx.node.params;
  final targetId = params['targetFunctionId']?.toString() ?? '';
  if (targetId.isEmpty) {
    throw StateError('function_call 未指定 targetFunctionId');
  }
  FunctionDef? targetFn;
  for (final f in ctx.project.functions) {
    if (f.id == targetId) {
      targetFn = f;
      break;
    }
  }
  if (targetFn == null) {
    throw StateError('目标函数 $targetId 不存在');
  }
  // 收集 args：除 targetFunctionId 外的参数，resolveRef 后作为 inputs
  // （inputs 按 funcVar.name 合并到被调用函数的 funcVars）。
  final inputs = <String, dynamic>{};
  for (final entry in params.entries) {
    if (entry.key == 'targetFunctionId') continue;
    inputs[entry.key] = resolveRef(entry.value, ctx.scope);
  }
  // 递归调用（创建新作用域）。
  final result = await ctx.interpreter.runFunction(targetFn, inputs);
  if (result.error != null) {
    throw StateError('子函数 ${targetFn.name} 执行失败: ${result.error}');
  }
  return NodeExecResult(
    dataOutputs: {'result': result.outputs['value']},
    nextControlOutput: 'next',
  );
}

/// return：终止，返回 params['value']。
Future<NodeExecResult> _execReturn(ExecContext ctx) async {
  final value = resolveRef(ctx.node.params['value'], ctx.scope);
  return NodeExecResult(isReturn: true, returnValue: value);
}

// ===========================================================================
// 数据库节点
// ===========================================================================

/// db_query：用 DatabaseExecutor 执行 SELECT，返回 rows + count。
Future<NodeExecResult> _execDbQuery(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) {
    throw StateError('db_query 未指定 table');
  }
  final filter = resolveRef(params['filter'], ctx.scope)?.toString();
  final limit = _toInt(resolveRef(params['limit'], ctx.scope));
  final result = await db.query(table, filter: filter, limit: limit);
  return NodeExecResult(
    dataOutputs: {'rows': result.rows, 'count': result.count},
    nextControlOutput: 'next',
  );
}

/// db_insert：执行 INSERT，返回 insertedId + affected。
Future<NodeExecResult> _execDbInsert(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) {
    throw StateError('db_insert 未指定 table');
  }
  final data = _toMap(resolveRef(params['data'], ctx.scope));
  final result = await db.insert(table, data);
  return NodeExecResult(
    dataOutputs: {'insertedId': result.insertedId, 'affected': result.affected},
    nextControlOutput: 'next',
  );
}

/// db_update：执行 UPDATE，返回 affected。
Future<NodeExecResult> _execDbUpdate(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) {
    throw StateError('db_update 未指定 table');
  }
  final filter = resolveRef(params['filter'], ctx.scope)?.toString() ?? '';
  final data = _toMap(resolveRef(params['data'], ctx.scope));
  final affected = await db.update(table, filter, data);
  return NodeExecResult(
    dataOutputs: {'affected': affected},
    nextControlOutput: 'next',
  );
}

/// db_delete：执行 DELETE，返回 affected。
Future<NodeExecResult> _execDbDelete(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) {
    throw StateError('db_delete 未指定 table');
  }
  final filter = resolveRef(params['filter'], ctx.scope)?.toString() ?? '';
  final affected = await db.delete(table, filter);
  return NodeExecResult(
    dataOutputs: {'affected': affected},
    nextControlOutput: 'next',
  );
}

/// db_create_table：执行建表 DDL。
Future<NodeExecResult> _execDbCreateTable(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) {
    throw StateError('db_create_table 未指定 table');
  }
  final columnsSpec = params['columnsSpec']?.toString() ?? '';
  final columns = _parseColumns(columnsSpec);
  await db.createTable(table, columns);
  return const NodeExecResult(
    dataOutputs: {'success': true},
    nextControlOutput: 'next',
  );
}

/// db_alter_table：执行改表 DDL（add/rename）。
Future<NodeExecResult> _execDbAlterTable(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) {
    throw StateError('db_alter_table 未指定 table');
  }
  final action = params['action']?.toString() ?? 'add';
  final columnName = params['columnName']?.toString() ?? '';
  final newType = params['newType']?.toString();
  await db.alterTable(
    table,
    action: action,
    columnName: columnName,
    newType: newType,
  );
  return const NodeExecResult(
    dataOutputs: {'success': true},
    nextControlOutput: 'next',
  );
}

// ===========================================================================
// 插件节点
// ===========================================================================

/// plugin_openai / plugin_anthropic：从 PluginRegistry 取 executor + config，
/// 调用 execute，输出 content / usage_tokens。
Future<NodeExecResult> _execPlugin(ExecContext ctx, String pluginId) async {
  final entry = ctx.pluginRegistry.get(pluginId);
  if (entry == null) {
    throw StateError('插件 $pluginId 未注册');
  }
  // 从安全存储读取插件配置（含 API Key）。
  Map<String, dynamic> config = const {};
  if (ctx.pluginConfigStorage != null) {
    config = await ctx.pluginConfigStorage!.getPluginConfig(pluginId);
  }
  // 构建 inputs：按插件 inputs 声明从 node params 取值并 resolveRef。
  final inputs = <String, dynamic>{};
  for (final p in entry.spec.inputs) {
    inputs[p.name] = resolveRef(ctx.node.params[p.name], ctx.scope);
  }
  final outputs = await entry.executor.execute(entry.spec, inputs, config);
  return NodeExecResult(
    dataOutputs: outputs,
    nextControlOutput: 'next',
  );
}

// ===========================================================================
// 工具函数
// ===========================================================================

DatabaseExecutor _requireDb(ExecContext ctx) {
  final db = ctx.dbExecutor;
  if (db == null) {
    throw StateError('未提供 DatabaseExecutor，无法执行数据库节点');
  }
  return db;
}

/// 转换为 num（兼容 String 解析）。
num? _toNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

/// 转换为 int（兼容 num 截断与 String 解析）。
int _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// 转换为 bool（兼容 String "true"/"false" 与 num 非零）。
bool _toBool(Object? v) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  if (v is num) return v != 0;
  return false;
}

/// 转换为 Map（兼容 JSON 字符串解析）。
Map<String, Object?> _toMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return Map<String, Object?>.from(v);
  if (v is String && v.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {
      // 非 JSON 字符串，降级为空 Map。
    }
  }
  return {};
}

/// 解析列定义字符串为 [Column] 列表。
///
/// 支持两种格式：
/// - JSON：`[{"name":"id","type":"INTEGER","primaryKey":true},...]`
/// - 简单文本：`id INTEGER PRIMARY KEY, name TEXT NOT NULL`
List<Column> _parseColumns(String spec) {
  if (spec.isEmpty) return const [];
  // 尝试 JSON。
  try {
    final decoded = jsonDecode(spec);
    if (decoded is List) {
      return decoded.map((e) {
        if (e is Map) {
          return Column(
            name: e['name']?.toString() ?? '',
            type: e['type']?.toString() ?? 'TEXT',
            primaryKey: e['primaryKey'] == true,
            nullable: e['nullable'] != false,
          );
        }
        return Column(name: e.toString(), type: 'TEXT');
      }).toList();
    }
  } catch (_) {
    // 非 JSON，降级到简单文本解析。
  }
  // 简单格式：`id INTEGER PRIMARY KEY, name TEXT NOT NULL`
  final cols = <Column>[];
  for (final part in spec.split(',')) {
    final tokens = part.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || tokens[0].isEmpty) continue;
    final name = tokens[0];
    final type = tokens.length > 1 ? tokens[1] : 'TEXT';
    final isPk = tokens.any((t) => t.toUpperCase() == 'PRIMARY');
    final isNotNull = tokens.any((t) => t.toUpperCase() == 'NOTNULL') ||
        (tokens.any((t) => t.toUpperCase() == 'NOT') &&
            tokens.any((t) => t.toUpperCase() == 'NULL'));
    cols.add(Column(
      name: name,
      type: type,
      primaryKey: isPk,
      nullable: !isNotNull,
    ),);
  }
  return cols;
}
