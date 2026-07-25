import 'dart:convert';
import 'dart:math' as math;

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
import 'runtime_ui_state.dart';

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

  /// return 节点的单返回值（向后兼容：旧式 `value` 单返回路径）。
  ///
  /// 仅 [isReturn] 为 true 时有效；若 [returnOutputs] 非空则优先使用
  /// [returnOutputs]（多返回值路径），调用方按目标函数 outputs 名映射。
  final Object? returnValue;

  /// return 节点的多返回值映射（按目标函数 outputs 名）。
  ///
  /// 非空时优先于 [returnValue]：调用方应将每个命名值放入 RunResult.outputs。
  /// 空时退化到旧式单返回 `value`。
  final Map<String, dynamic> returnOutputs;

  const NodeExecResult({
    this.dataOutputs = const {},
    this.nextControlOutput,
    this.isReturn = false,
    this.returnValue,
    this.returnOutputs = const {},
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

  /// 运行时 UI 状态覆盖层，可空（为空时 ui_* 节点写入会被忽略，不抛错）。
  final RuntimeUiState? uiState;

  const ExecContext({
    required this.node,
    required this.function,
    required this.project,
    required this.scope,
    required this.interpreter,
    required this.pluginRegistry,
    this.pluginConfigStorage,
    this.dbExecutor,
    this.uiState,
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
      // 页面级函数 outputs 引用：仅在函数已 done 时返回缓存值，
      // 其余状态返回 null（节点解释器执行时不应用加载态策略——
      // 加载态策略是 UI 绑定解析的职责，见 BindingResolver）。
      if (ref.isPageFunc) {
        final entry = scope.getPageFuncEntry(ref.funcId!);
        if (entry == null || entry.state != PageFuncState.done) return null;
        return entry.outputs[ref.outputName!];
      }
      if (ref.varId == null) return null;
      return scope.getFuncVar(ref.varId!);
    case VariableSource.projVar:
      if (ref.varId == null) return null;
      return scope.getProjVar(ref.varId!);
    case VariableSource.component:
      // 组件上下文变量（item / index / tab / value 等）由 UI 渲染层
      // 在运行时按组件树位置注入到 [RuntimeScope.componentContexts]。
      // 当前作用域未注入对应组件上下文时返回 null（加载态策略在 UI 侧处理）。
      if (ref.componentId == null || ref.fieldName == null) return null;
      final ctx = scope.getComponentContext(ref.componentId!);
      return ctx?.get(ref.fieldName!);
  }
}

/// 执行节点（按 [Node.kind] 分发）。
///
/// 每种 kind 的执行逻辑在下方对应的 `_execXxx` 函数中实现。
/// 异常由调用方（[NodeInterpreter]）捕获并记录到 [RunResult.error]。
Future<NodeExecResult> executeNode(ExecContext ctx) async {
  switch (ctx.node.kind) {
    // ---- 变量 ----
    case 'variable_set':
      return _execVariableSet(ctx);

    // ---- 运算 ----
    case 'arithmetic':
      return _execArithmetic(ctx);
    case 'math_func':
      return _execMathFunc(ctx);
    case 'string_op':
      return _execStringOp(ctx);
    case 'list_op':
      return _execListOp(ctx);
    case 'date_op':
      return _execDateOp(ctx);

    // ---- 逻辑 ----
    case 'logic':
      return _execLogic(ctx);
    case 'compare':
      return _execCompare(ctx);
    case 'type_check':
      return _execTypeCheck(ctx);
    case 'ternary':
      return _execTernary(ctx);

    // ---- 流程控制 ----
    case 'if':
      return _execIf(ctx);
    case 'if_branch':
      // 子母节点设计的子节点：纯控制流传递，走 next 输出（无数据产出）。
      return const NodeExecResult(nextControlOutput: 'next');
    case 'loop':
      return _execLoop(ctx);
    case 'return':
      return _execReturn(ctx);

    // ---- 函数调用 ----
    case 'function_call':
      return _execFunctionCall(ctx);

    // ---- 数据库 ----
    case 'db_query_one':
      return _execDbQueryOne(ctx);
    case 'db_query_rows':
      return _execDbQueryRows(ctx);
    case 'db_aggregate':
      return _execDbAggregate(ctx);
    case 'db_insert':
      return _execDbInsert(ctx);
    case 'db_insert_rows':
      return _execDbInsertRows(ctx);
    case 'db_update':
      return _execDbUpdate(ctx);
    case 'db_delete':
      return _execDbDelete(ctx);
    case 'db_create_table':
      return _execDbCreateTable(ctx);
    case 'db_alter_table':
      return _execDbAlterTable(ctx);

    // ---- UI 控制 ----
    case 'ui_set_text':
      return _execUiSetText(ctx);
    case 'ui_set_visible':
      return _execUiSetVisible(ctx);
    case 'ui_set_enabled':
      return _execUiSetEnabled(ctx);
    case 'ui_set_prop':
      return _execUiSetProp(ctx);
    case 'ui_navigate':
      return _execUiNavigate(ctx);
    case 'ui_show_toast':
      return _execUiShowToast(ctx);

    // ---- 内置插件 ----
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

// ===========================================================================
// 运算节点
// ===========================================================================

/// arithmetic：a op b；支持 + - * / % // ^（幂）。
Future<NodeExecResult> _execArithmetic(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operator']?.toString() ?? '+';
  final a = _toNum(resolveRef(params['a'], ctx.scope));
  final b = _toNum(resolveRef(params['b'], ctx.scope));
  num result;
  switch (op) {
    case '+':
      result = (a ?? 0) + (b ?? 0);
    case '-':
      result = (a ?? 0) - (b ?? 0);
    case '*':
      result = (a ?? 0) * (b ?? 0);
    case '/':
      if (b == null || b == 0) throw StateError('除数为零');
      result = a! / b;
    case '%':
      if (b == null || b == 0) throw StateError('取模数为零');
      result = a!.toInt() % b.toInt();
    case '//':
      if (b == null || b == 0) throw StateError('整除数为零');
      result = (a! / b).floor();
    case '^':
    case 'pow':
      result = math.pow((a ?? 0).toDouble(), (b ?? 0).toDouble());
    default:
      throw StateError('未知运算符: $op');
  }
  return NodeExecResult(
    dataOutputs: {'result': result},
    nextControlOutput: 'next',
  );
}

/// math_func：单参数数学函数；func ∈ abs/round/floor/ceil/sqrt/log/sin/cos/tan/random/min/max。
/// min/max 为双参数（a, b），其余单参数（a）。
Future<NodeExecResult> _execMathFunc(ExecContext ctx) async {
  final params = ctx.node.params;
  final fn = params['func']?.toString() ?? 'abs';
  final a = _toNum(resolveRef(params['a'], ctx.scope))?.toDouble() ?? 0.0;
  final b = _toNum(resolveRef(params['b'], ctx.scope))?.toDouble();
  double result;
  switch (fn) {
    case 'abs':
      result = a.abs();
    case 'round':
      result = a.roundToDouble();
    case 'floor':
      result = a.floorToDouble();
    case 'ceil':
      result = a.ceilToDouble();
    case 'sqrt':
      result = math.sqrt(a);
    case 'log':
      result = math.log(a);
    case 'sin':
      result = math.sin(a);
    case 'cos':
      result = math.cos(a);
    case 'tan':
      result = math.tan(a);
    case 'min':
      result = b == null ? a : math.min(a, b);
    case 'max':
      result = b == null ? a : math.max(a, b);
    case 'random':
      // 0..a（含 0 不含 a），默认 1。
      final max = a > 0 ? a : 1.0;
      result = math.Random().nextDouble() * max;
    default:
      throw StateError('未知数学函数: $fn');
  }
  // 整数函数返回 int 以保持类型友好。
  final out = (fn == 'round' || fn == 'floor' || fn == 'ceil' || fn == 'abs')
      ? result.toInt() as Object
      : result as Object;
  return NodeExecResult(
    dataOutputs: {'result': out},
    nextControlOutput: 'next',
  );
}

/// string_op：扩展字符串操作。
/// operation ∈ concat/substring/upper/lower/length/replace/split/trim/
///   contains/startsWith/endsWith/indexOf/format/padLeft/padRight/reverse/repeat
Future<NodeExecResult> _execStringOp(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operation']?.toString() ?? 'concat';
  final a = resolveRef(params['a'], ctx.scope)?.toString() ?? '';
  final b = resolveRef(params['b'], ctx.scope)?.toString() ?? '';
  final c = resolveRef(params['c'], ctx.scope)?.toString() ?? '';
  switch (op) {
    case 'concat':
      return _ok({'result': a + b});
    case 'substring':
      // b = "start,end" 或 "start"。
      final parts = b.split(',');
      final start = (int.tryParse(parts[0]) ?? 0).clamp(0, a.length);
      final end = parts.length > 1
          ? (int.tryParse(parts[1]) ?? a.length).clamp(0, a.length)
          : a.length;
      return _ok({'result': a.substring(start, end)});
    case 'upper':
      return _ok({'result': a.toUpperCase()});
    case 'lower':
      return _ok({'result': a.toLowerCase()});
    case 'length':
      return _ok({'length': a.length, 'result': a.length});
    case 'replace':
      return _ok({'result': a.replaceAll(b, c)});
    case 'split':
      return _ok({'result': a.split(b)});
    case 'trim':
      return _ok({'result': a.trim()});
    case 'contains':
      return _ok({'result': a.contains(b)});
    case 'startsWith':
      return _ok({'result': a.startsWith(b)});
    case 'endsWith':
      return _ok({'result': a.endsWith(b)});
    case 'indexOf':
      return _ok({'result': a.indexOf(b)});
    case 'format':
      // 简易：将 {0} {1} ... 占位替换为 b, c, ... 拆分。
      final args = [b, c, ..._toList(resolveRef(params['args'], ctx.scope))];
      var out = a;
      for (var i = 0; i < args.length; i++) {
        out = out.replaceAll('{$i}', args[i].toString());
      }
      return _ok({'result': out});
    case 'padLeft':
      final w = int.tryParse(b) ?? a.length;
      return _ok({'result': a.padLeft(w, c.isEmpty ? ' ' : c[0])});
    case 'padRight':
      final w = int.tryParse(b) ?? a.length;
      return _ok({'result': a.padRight(w, c.isEmpty ? ' ' : c[0])});
    case 'reverse':
      return _ok({'result': a.split('').reversed.join()});
    case 'repeat':
      final n = int.tryParse(b) ?? 1;
      return _ok({'result': a * n});
    default:
      throw StateError('未知字符串操作: $op');
  }
}

/// list_op：列表操作。
/// operation ∈ size/get/contains/append/removeAt/slice/reverse/sort/unique/join/concat/map/filter/indexOf
Future<NodeExecResult> _execListOp(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operation']?.toString() ?? 'size';
  final list = _toList(resolveRef(params['a'], ctx.scope));
  final b = resolveRef(params['b'], ctx.scope);
  switch (op) {
    case 'size':
      return _ok({'result': list.length, 'size': list.length});
    case 'get':
      final i = _toInt(b);
      return _ok({'result': i >= 0 && i < list.length ? list[i] : null});
    case 'contains':
      return _ok({'result': list.contains(b)});
    case 'indexOf':
      return _ok({'result': list.indexOf(b)});
    case 'append':
      return _ok({'result': [...list, b]});
    case 'removeAt':
      final i = _toInt(b);
      final out = List<Object?>.from(list);
      if (i >= 0 && i < out.length) out.removeAt(i);
      return _ok({'result': out});
    case 'slice':
      // b = "start,end"
      final parts = b?.toString().split(',') ?? ['0'];
      final start = (int.tryParse(parts[0]) ?? 0).clamp(0, list.length);
      final end = parts.length > 1
          ? (int.tryParse(parts[1]) ?? list.length).clamp(0, list.length)
          : list.length;
      return _ok({'result': list.sublist(start, end)});
    case 'reverse':
      return _ok({'result': list.reversed.toList()});
    case 'sort':
      final nums = list.whereType<num>().toList()..sort();
      return _ok({'result': nums});
    case 'unique':
      final seen = <Object?>{};
      final out = <Object?>[];
      for (final e in list) {
        if (seen.add(e)) out.add(e);
      }
      return _ok({'result': out});
    case 'join':
      final sep = b?.toString() ?? ',';
      return _ok({'result': list.map((e) => e?.toString() ?? '').join(sep)});
    case 'concat':
      final other = _toList(b);
      return _ok({'result': [...list, ...other]});
    default:
      throw StateError('未知列表操作: $op');
  }
}

/// date_op：日期时间操作。
/// operation ∈ now/format/parse/add/diff/year/month/day/hour/minute/second/weekday
Future<NodeExecResult> _execDateOp(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operation']?.toString() ?? 'now';
  final aStr = resolveRef(params['a'], ctx.scope)?.toString();
  switch (op) {
    case 'now':
      return _ok({'result': DateTime.now().toIso8601String()});
    case 'parse':
      final dt = aStr != null ? DateTime.tryParse(aStr) : null;
      if (dt == null) throw StateError('无法解析日期: $aStr');
      return _ok({'result': dt.toIso8601String(), 'timestamp': dt.millisecondsSinceEpoch});
    case 'format':
      // 简易：b = 模板（YYYY-MM-DD 等），仅支持常用占位符。
      final dt = aStr != null ? (DateTime.tryParse(aStr) ?? DateTime.now()) : DateTime.now();
      return _ok({'result': _formatDate(dt, b?.toString() ?? 'YYYY-MM-DD')});
    case 'year':
    case 'month':
    case 'day':
    case 'hour':
    case 'minute':
    case 'second':
    case 'weekday':
      final dt = aStr != null ? (DateTime.tryParse(aStr) ?? DateTime.now()) : DateTime.now();
      final v = _dateField(dt, op);
      return _ok({'result': v});
    case 'add':
      // b = "amount,unit" 如 "1,days"
      final dt = aStr != null ? (DateTime.tryParse(aStr) ?? DateTime.now()) : DateTime.now();
      final parts = b?.toString().split(',') ?? ['0', 'days'];
      final amount = int.tryParse(parts[0]) ?? 0;
      final unit = parts.length > 1 ? parts[1] : 'days';
      final out = _addDuration(dt, amount, unit);
      return _ok({'result': out.toIso8601String()});
    case 'diff':
      // a, b 为两个日期，返回相差天数。
      final d1 = aStr != null ? (DateTime.tryParse(aStr) ?? DateTime.now()) : DateTime.now();
      final d2 = b != null ? (DateTime.tryParse(b.toString()) ?? DateTime.now()) : DateTime.now();
      final diff = d2.difference(d1).inDays;
      return _ok({'result': diff});
    default:
      throw StateError('未知日期操作: $op');
  }
}

// ===========================================================================
// 逻辑节点
// ===========================================================================

/// logic：and/or/not/xor/nand/nor。
Future<NodeExecResult> _execLogic(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operator']?.toString() ?? 'and';
  final a = _toBool(resolveRef(params['a'], ctx.scope));
  final b = _toBool(resolveRef(params['b'], ctx.scope));
  bool result;
  switch (op) {
    case 'and':
      result = a && b;
    case 'or':
      result = a || b;
    case 'not':
      result = !a;
    case 'xor':
      result = a != b;
    case 'nand':
      result = !(a && b);
    case 'nor':
      result = !(a || b);
    default:
      throw StateError('未知逻辑运算符: $op');
  }
  return NodeExecResult(
    dataOutputs: {'result': result},
    nextControlOutput: 'next',
  );
}

/// compare：比较 ==/!=/>/<>=/<=/between。
Future<NodeExecResult> _execCompare(ExecContext ctx) async {
  final params = ctx.node.params;
  final op = params['operator']?.toString() ?? '==';
  final a = resolveRef(params['a'], ctx.scope);
  final b = resolveRef(params['b'], ctx.scope);
  final na = _toNum(a);
  final nb = _toNum(b);
  bool result;
  switch (op) {
    case '==':
      result = a == b;
    case '!=':
      result = a != b;
    case '>':
      result = (na ?? double.negativeInfinity) > (nb ?? double.negativeInfinity);
    case '<':
      result = (na ?? double.infinity) < (nb ?? double.infinity);
    case '>=':
      result = (na ?? double.negativeInfinity) >= (nb ?? double.negativeInfinity);
    case '<=':
      result = (na ?? double.infinity) <= (nb ?? double.infinity);
    case 'between':
      // a 在 [b, c] 之间。
      final c = _toNum(resolveRef(params['c'], ctx.scope));
      result = na != null && (c != null ? (na >= nb! && na <= c) : (na >= nb!));
    default:
      throw StateError('未知比较运算符: $op');
  }
  return NodeExecResult(
    dataOutputs: {'result': result},
    nextControlOutput: 'next',
  );
}

/// type_check：类型判断 isNull/isNotNull/isNumber/isString/isBool/isList/isMap。
Future<NodeExecResult> _execTypeCheck(ExecContext ctx) async {
  final params = ctx.node.params;
  final fn = params['check']?.toString() ?? 'isNull';
  final v = resolveRef(params['a'], ctx.scope);
  bool result;
  switch (fn) {
    case 'isNull':
      result = v == null;
    case 'isNotNull':
      result = v != null;
    case 'isNumber':
      result = v is num;
    case 'isString':
      result = v is String;
    case 'isBool':
      result = v is bool;
    case 'isList':
      result = v is List;
    case 'isMap':
      result = v is Map;
    default:
      throw StateError('未知类型检查: $fn');
  }
  return NodeExecResult(
    dataOutputs: {'result': result},
    nextControlOutput: 'next',
  );
}

/// ternary：condition ? trueValue : falseValue。
Future<NodeExecResult> _execTernary(ExecContext ctx) async {
  final params = ctx.node.params;
  final cond = _toBool(resolveRef(params['condition'], ctx.scope));
  final trueVal = resolveRef(params['trueValue'], ctx.scope);
  final falseVal = resolveRef(params['falseValue'], ctx.scope);
  return NodeExecResult(
    dataOutputs: {'result': cond ? trueVal : falseVal},
    nextControlOutput: 'next',
  );
}

// ===========================================================================
// 数据库节点
// ===========================================================================

/// db_query_one：查询单行（返回第一行）。
Future<NodeExecResult> _execDbQueryOne(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) throw StateError('db_query_one 未指定 table');
  final filter = resolveRef(params['filter'], ctx.scope)?.toString();
  final orderBy = resolveRef(params['orderBy'], ctx.scope)?.toString();
  final result = await db.query(table, filter: filter, limit: 1, orderBy: orderBy);
  final row = result.rows.isNotEmpty ? result.rows.first : null;
  return NodeExecResult(
    dataOutputs: {'row': row, 'found': row != null},
    nextControlOutput: 'next',
  );
}

/// db_query_rows：查询多行。
Future<NodeExecResult> _execDbQueryRows(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) throw StateError('db_query_rows 未指定 table');
  final filter = resolveRef(params['filter'], ctx.scope)?.toString();
  final limit = _toInt(resolveRef(params['limit'], ctx.scope));
  final orderBy = resolveRef(params['orderBy'], ctx.scope)?.toString();
  final result = await db.query(table,
      filter: filter, limit: limit > 0 ? limit : null, orderBy: orderBy);
  return NodeExecResult(
    dataOutputs: {'rows': result.rows, 'count': result.count},
    nextControlOutput: 'next',
  );
}

/// db_aggregate：聚合统计 sum/avg/count/min/max。
Future<NodeExecResult> _execDbAggregate(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) throw StateError('db_aggregate 未指定 table');
  final func = params['func']?.toString() ?? 'count';
  final column = params['column']?.toString();
  final filter = resolveRef(params['filter'], ctx.scope)?.toString();
  final value = await db.queryAggregate(table,
      func: func, column: column, filter: filter);
  return NodeExecResult(
    dataOutputs: {'value': value, 'count': value?.toInt() ?? 0},
    nextControlOutput: 'next',
  );
}

/// db_insert：插入单行。
Future<NodeExecResult> _execDbInsert(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) throw StateError('db_insert 未指定 table');
  final data = _toMap(resolveRef(params['data'], ctx.scope));
  final result = await db.insert(table, data);
  return NodeExecResult(
    dataOutputs: {'insertedId': result.insertedId, 'affected': result.affected},
    nextControlOutput: 'next',
  );
}

/// db_insert_rows：批量插入多行。
Future<NodeExecResult> _execDbInsertRows(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) throw StateError('db_insert_rows 未指定 table');
  final rows = _toMapList(resolveRef(params['data'], ctx.scope));
  final result = await db.insertBatch(table, rows);
  return NodeExecResult(
    dataOutputs: {
      'insertedIds': result.insertedIds,
      'affected': result.affected,
    },
    nextControlOutput: 'next',
  );
}

/// db_update：更新。
Future<NodeExecResult> _execDbUpdate(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) throw StateError('db_update 未指定 table');
  final filter = resolveRef(params['filter'], ctx.scope)?.toString() ?? '';
  final data = _toMap(resolveRef(params['data'], ctx.scope));
  final affected = await db.update(table, filter, data);
  return NodeExecResult(
    dataOutputs: {'affected': affected},
    nextControlOutput: 'next',
  );
}

/// db_delete：删除。
Future<NodeExecResult> _execDbDelete(ExecContext ctx) async {
  final db = _requireDb(ctx);
  final params = ctx.node.params;
  final table = params['table']?.toString() ?? '';
  if (table.isEmpty) throw StateError('db_delete 未指定 table');
  final filter = resolveRef(params['filter'], ctx.scope)?.toString() ?? '';
  final affected = await db.delete(table, filter);
  return NodeExecResult(
    dataOutputs: {'affected': affected},
    nextControlOutput: 'next',
  );
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
  // 按目标函数 outputs 名透传多返回值；无 outputs 时退化到旧式单返回。
  if (targetFn.outputs.isNotEmpty) {
    return NodeExecResult(
      dataOutputs: {
        for (final p in targetFn.outputs)
          p.name: result.outputs[p.name],
      },
      nextControlOutput: 'next',
    );
  }
  return NodeExecResult(
    dataOutputs: {'result': result.outputs['value']},
    nextControlOutput: 'next',
  );
}

/// return：终止函数。
///
/// 支持两种返回路径：
/// - **多返回值**：[Node.params] 含 `values` map（key=output 名，
///   value=`#` 引用），按目标函数 outputs 名映射到 [returnOutputs]。
///   优先级高于单返回。
/// - **单返回**（向后兼容）：[Node.params] 含 `value`，放入 [returnValue]，
///   调用方将其写入 RunResult.outputs['value']。
Future<NodeExecResult> _execReturn(ExecContext ctx) async {
  final params = ctx.node.params;
  // 多返回值路径：params['values'] 为 map<name, ref>。
  final rawValues = params['values'];
  if (rawValues is Map && rawValues.isNotEmpty) {
    final resolved = <String, dynamic>{};
    for (final entry in rawValues.entries) {
      resolved[entry.key.toString()] = resolveRef(entry.value, ctx.scope);
    }
    return NodeExecResult(isReturn: true, returnOutputs: resolved);
  }
  // 单返回路径（向后兼容）。
  final value = resolveRef(params['value'], ctx.scope);
  return NodeExecResult(isReturn: true, returnValue: value);
}

// ===========================================================================
// 数据库 DDL 节点
// ===========================================================================

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
// UI 控制节点
// ===========================================================================

/// ui_set_text：设置文本组件内容。
Future<NodeExecResult> _execUiSetText(ExecContext ctx) async {
  final params = ctx.node.params;
  final componentId = params['componentId']?.toString() ?? '';
  final text = resolveRef(params['text'], ctx.scope)?.toString() ?? '';
  ctx.uiState?.setText(componentId, text);
  return const NodeExecResult(nextControlOutput: 'next');
}

/// ui_set_visible：设置组件可见性。
Future<NodeExecResult> _execUiSetVisible(ExecContext ctx) async {
  final params = ctx.node.params;
  final componentId = params['componentId']?.toString() ?? '';
  final visible = _toBool(resolveRef(params['visible'], ctx.scope));
  ctx.uiState?.setVisible(componentId, visible);
  return const NodeExecResult(nextControlOutput: 'next');
}

/// ui_set_enabled：设置组件启用状态。
Future<NodeExecResult> _execUiSetEnabled(ExecContext ctx) async {
  final params = ctx.node.params;
  final componentId = params['componentId']?.toString() ?? '';
  final enabled = _toBool(resolveRef(params['enabled'], ctx.scope));
  ctx.uiState?.setEnabled(componentId, enabled);
  return const NodeExecResult(nextControlOutput: 'next');
}

/// ui_set_prop：设置组件任意属性。
Future<NodeExecResult> _execUiSetProp(ExecContext ctx) async {
  final params = ctx.node.params;
  final componentId = params['componentId']?.toString() ?? '';
  final propName = params['propName']?.toString() ?? '';
  final value = resolveRef(params['value'], ctx.scope);
  if (propName.isNotEmpty) {
    ctx.uiState?.setProp(componentId, propName, value);
  }
  return const NodeExecResult(nextControlOutput: 'next');
}

/// ui_navigate：导航到路由。
Future<NodeExecResult> _execUiNavigate(ExecContext ctx) async {
  final params = ctx.node.params;
  final route = resolveRef(params['route'], ctx.scope)?.toString() ?? '/';
  final paramsMap = _toMap(resolveRef(params['params'], ctx.scope));
  ctx.uiState?.navigate(route, paramsMap);
  return const NodeExecResult(nextControlOutput: 'next');
}

/// ui_show_toast：显示提示。
Future<NodeExecResult> _execUiShowToast(ExecContext ctx) async {
  final params = ctx.node.params;
  final message = resolveRef(params['message'], ctx.scope)?.toString() ?? '';
  final type = params['type']?.toString() ?? 'info';
  ctx.uiState?.showToast(message, type: type);
  return const NodeExecResult(nextControlOutput: 'next');
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

/// 转换为 List（兼容 JSON 字符串解析）。
List<Object?> _toList(Object? v) {
  if (v is List) return v;
  if (v is String && v.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is List) return decoded;
    } catch (_) {
      // 非 JSON 字符串，降级为空列表。
    }
  }
  return const [];
}

/// 转换为 List<Map>（批量插入用）。
List<Map<String, Object?>> _toMapList(Object? v) {
  final list = _toList(v);
  return list
      .map((e) => e is Map ? Map<String, Object?>.from(e) : <String, Object?>{})
      .toList();
}

/// 构造成功结果（next 控制流 + 数据输出）。
NodeExecResult _ok(Map<String, dynamic> data) =>
    NodeExecResult(dataOutputs: data, nextControlOutput: 'next');

/// 日期格式化（简易：支持 YYYY MM DD HH mm ss 占位）。
String _formatDate(DateTime dt, String fmt) {
  return fmt
      .replaceAll('YYYY', dt.year.toString())
      .replaceAll('MM', dt.month.toString().padLeft(2, '0'))
      .replaceAll('DD', dt.day.toString().padLeft(2, '0'))
      .replaceAll('HH', dt.hour.toString().padLeft(2, '0'))
      .replaceAll('mm', dt.minute.toString().padLeft(2, '0'))
      .replaceAll('ss', dt.second.toString().padLeft(2, '0'));
}

/// 取日期字段值。
int _dateField(DateTime dt, String field) {
  switch (field) {
    case 'year':
      return dt.year;
    case 'month':
      return dt.month;
    case 'day':
      return dt.day;
    case 'hour':
      return dt.hour;
    case 'minute':
      return dt.minute;
    case 'second':
      return dt.second;
    case 'weekday':
      return dt.weekday;
    default:
      return 0;
  }
}

/// 日期增量。unit ∈ days/hours/minutes/seconds/months/years。
DateTime _addDuration(DateTime dt, int amount, String unit) {
  switch (unit) {
    case 'days':
      return dt.add(Duration(days: amount));
    case 'hours':
      return dt.add(Duration(hours: amount));
    case 'minutes':
      return dt.add(Duration(minutes: amount));
    case 'seconds':
      return dt.add(Duration(seconds: amount));
    case 'months':
      return DateTime(dt.year, dt.month + amount, dt.day,
          dt.hour, dt.minute, dt.second);
    case 'years':
      return DateTime(dt.year + amount, dt.month, dt.day,
          dt.hour, dt.minute, dt.second);
    default:
      return dt.add(Duration(days: amount));
  }
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
