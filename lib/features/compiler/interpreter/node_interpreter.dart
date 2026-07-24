import '../../../data/models/control_edge.dart';
import '../../../data/models/function_def.dart';
import '../../../data/models/node.dart';
import '../../../data/models/project.dart';
import '../../plugins/plugin_config_storage.dart';
import '../../plugins/plugin_registry.dart';
import 'database_executor.dart';
import 'node_executors.dart';
import 'runtime_scope.dart';
import 'runtime_ui_state.dart';

export 'node_executors.dart' show RunResult, NodeExecResult;

/// 节点解释器：在编译后应用里由 Dart 直接执行 DAG 控制流图。
///
/// 架构 spike 决策：**IR 即运行时格式**，节点函数不经代码生成，
/// 而由本解释器按控制流边遍历节点图，逐节点执行（[executeNode]），
/// 数据通过 `#` 引用（[resolveRef]）在 [RuntimeScope] 中传递。
///
/// 核心能力：
/// - [runFunction]：执行函数（创建新作用域，初始化变量，从入口节点执行）。
/// - [runFromNode]：从指定节点开始执行控制流（共享作用域，供 loop body 复用）。
/// - 控制流遍历：执行当前节点 → 根据节点返回的下一个控制流输出名找到对应
///   [ControlEdge] → 执行目标节点 → 直到无后续或命中 return。
/// - 递归：function_call 递归 [runFunction]（新作用域），loop body 递归
///   [runFromNode]（共享作用域，body 内可引用 loop 的 index 输出）。
/// - 错误处理：节点执行异常捕获，记录到 [RunResult.error] 不崩溃。
class NodeInterpreter implements InterpreterHost {
  NodeInterpreter({
    required this.project,
    required this.pluginRegistry,
    this.dbExecutor,
    this.pluginConfigStorage,
    this.uiState,
  });

  /// 所属项目（用于 function_call 查找目标函数、db 节点读取 schema）。
  final Project project;

  /// 插件注册表（plugin_* 节点执行依赖）。
  final PluginRegistry pluginRegistry;

  /// 数据库执行器，可空（为空时 db_* 节点抛错）。
  final DatabaseExecutor? dbExecutor;

  /// 插件配置存储（读取 API Key 等），可空。
  final PluginConfigStorage? pluginConfigStorage;

  /// 运行时 UI 状态覆盖层，可空（为空时 ui_* 节点写入被忽略，不抛错）。
  final RuntimeUiState? uiState;

  /// db schema 是否已确保（幂等，避免每次 runFunction 重复建表）。
  bool _schemaEnsured = false;

  /// 执行函数：创建新作用域，初始化变量，从入口节点执行控制流图。
  ///
  /// [inputs] 为函数入参（key = funcVar.name），会按名合并到函数的 funcVars
  /// （匹配 [FunctionVariable.name]），未匹配的入参存入 [RuntimeScope.inputs]。
  @override
  Future<RunResult> runFunction(
    FunctionDef function,
    Map<String, dynamic> inputs,
  ) async {
    // 确保 db schema（幂等，仅首次实际建表）。
    await _ensureDbSchema();

    final scope = RuntimeScope();

    // 初始化项目变量默认值。
    for (final v in project.projectVars) {
      scope.setProjVar(v.id, v.defaultValue);
    }

    // 初始化函数变量：inputs 按名合并，否则用默认值。
    scope.inputs.addAll(inputs);
    for (final v in function.funcVars) {
      if (inputs.containsKey(v.name)) {
        scope.setFuncVar(v.id, inputs[v.name]);
      } else {
        scope.setFuncVar(v.id, v.defaultValue);
      }
    }

    // 查找入口节点：第一个（声明序）无入边的节点。
    final startId = _findEntryNodeId(function);
    if (startId == null) {
      return RunResult(
        error: '函数 ${function.name} 没有入口节点（无入边节点）',
      );
    }
    return runFromNode(function, startId, scope);
  }

  /// 从指定节点开始执行控制流（共享 [scope]）。
  ///
  /// 供 [runFunction] 与 loop body 子图执行复用。loop body 共享同一
  /// [scope]，使 body 内的 `#upstream(loopNodeId, index)` 引用可见。
  @override
  Future<RunResult> runFromNode(
    FunctionDef function,
    String nodeId,
    RuntimeScope scope,
  ) async {
    String? currentId = nodeId;
    const maxSteps = 100000; // 安全上限，防止控制流死循环。
    var steps = 0;
    while (currentId != null) {
      if (steps++ > maxSteps) {
        return const RunResult(error: '执行步数超过上限 $maxSteps，疑似死循环');
      }
      // 查找当前节点。
      Node? node;
      for (final n in function.nodes) {
        if (n.id == currentId) {
          node = n;
          break;
        }
      }
      if (node == null) {
        return RunResult(error: '节点 $currentId 不存在');
      }

      // 执行节点（异常捕获，记录到 error 不崩溃）。
      NodeExecResult execResult;
      try {
        final ctx = ExecContext(
          node: node,
          function: function,
          project: project,
          scope: scope,
          interpreter: this,
          pluginRegistry: pluginRegistry,
          pluginConfigStorage: pluginConfigStorage,
          dbExecutor: dbExecutor,
          uiState: uiState,
        );
        execResult = await executeNode(ctx);
      } catch (e) {
        return RunResult(
          error: '节点 ${node.kind}#$currentId 执行失败: $e',
        );
      }

      // 写入数据输出到 scope（key = "${nodeId}.${outputName}"）。
      for (final entry in execResult.dataOutputs.entries) {
        scope.setNodeOutput(currentId, entry.key, entry.value);
      }

      // return 节点：终止函数并返回值。
      //
      // 优先级：returnOutputs（多返回值映射）> returnValue（单返回兼容）。
      // - 多返回值：把每个命名值放入 RunResult.outputs（key=output 名），
      //   function_call 节点按目标函数 outputs 名透传给下游。
      // - 单返回：保留旧式 outputs['value']，向后兼容无签名函数。
      if (execResult.isReturn) {
        if (execResult.returnOutputs.isNotEmpty) {
          return RunResult(
            outputs: Map<String, dynamic>.from(execResult.returnOutputs),
            didReturn: true,
          );
        }
        return RunResult(
          outputs: {'value': execResult.returnValue},
          didReturn: true,
        );
      }

      // 查找下一条控制流边。
      final nextPort = execResult.nextControlOutput;
      if (nextPort == null) {
        // 终止节点（无后续控制流输出）。
        return const RunResult();
      }
      ControlEdge? nextEdge;
      for (final e in function.controlEdges) {
        if (e.fromNode == currentId && e.fromPort == nextPort) {
          nextEdge = e;
          break;
        }
      }
      if (nextEdge == null) {
        // 无后续边，终止。
        return const RunResult();
      }
      currentId = nextEdge.toNode;
    }
    return const RunResult();
  }

  /// 查找入口节点：第一个（声明序）无入边的节点。
  ///
  /// 控制流图中无入边的节点即函数入口（由 [FunctionDef.entry] 描述触发方式，
  /// 但入口节点本身由图拓扑决定）。所有节点都有入边时返回 null（成环或空图）。
  String? _findEntryNodeId(FunctionDef function) {
    final hasIncoming = <String>{};
    for (final e in function.controlEdges) {
      hasIncoming.add(e.toNode);
    }
    for (final n in function.nodes) {
      if (!hasIncoming.contains(n.id)) return n.id;
    }
    return null;
  }

  /// 确保运行时数据库 schema 已建表（幂等）。
  Future<void> _ensureDbSchema() async {
    if (_schemaEnsured || dbExecutor == null) return;
    await dbExecutor!.ensureSchema(project.db);
    _schemaEnsured = true;
  }
}
