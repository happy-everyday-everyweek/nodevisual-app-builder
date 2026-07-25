import '../../../data/models/function_def.dart';
import '../../../data/models/project.dart';
import '../compiler/interpreter/node_interpreter.dart';
import '../plugins/plugin_registry.dart';
import '../plugins/plugin_spec.dart';
import 'plugin_manifest.dart';

/// 函数插件执行器：解释执行嵌入的 [FunctionDef] IR。
///
/// 当用户通过函数编辑器将一个函数发布为插件时，函数 IR 嵌入在
/// [PluginManifest.functionDef] 中。本执行器在调用时：
///
/// 1. 通过 [FunctionDef.fromJson] 还原函数定义；
/// 2. 构造一个最小化的 [Project]（仅含该函数，无项目变量 / 数据库 / UI 树，
///    因为函数插件禁用这些依赖项目上下文的节点）；
/// 3. 用 [NodeInterpreter] 执行该函数，inputs 按函数入参签名传递；
/// 4. 将 [RunResult.outputs] 透传给调用方（键对齐 [PluginSpec.outputs]）。
///
/// 函数插件节点限制（发布前由 UI 校验）：
/// - 禁用 `variable_set` 的 `projVar` target（项目变量）；
/// - 禁用所有 `db_*` 节点（依赖项目数据库 schema）；
/// - 禁用所有 `ui_*` 节点（依赖项目 UI 树）；
/// - 禁用 `function_call` 节点（依赖项目内其他函数）；
/// - 禁用 `timer` / `external` 触发器（依赖宿主项目调度）。
class FunctionPluginExecutor implements PluginExecutor {
  FunctionPluginExecutor(this._manifest, this._pluginRegistry);

  /// 插件清单（携带嵌入的函数 IR）。
  final PluginManifest _manifest;

  /// 插件注册表（用于函数内嵌套调用其他已安装插件）。
  final PluginRegistry _pluginRegistry;

  @override
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async {
    final functionDef = _manifest.functionDef;
    if (functionDef == null) {
      throw StateError('函数插件 ${_manifest.id} 缺少 functionDef 字段');
    }

    // 1. 还原函数 IR。
    final functionJson = functionDef.function;
    if (functionJson.isEmpty) {
      throw StateError('函数插件 ${_manifest.id} 的 function IR 为空');
    }
    final function = FunctionDef.fromJson(functionJson);

    // 2. 构造最小化 Project（仅含该函数）。
    //    函数插件禁用 projVar / db / ui / function_call，所以 Project 的
    //    projectVars / db / pages / ui 均为空即可。
    final minimalProject = Project(
      meta: ProjectMeta(
        id: 'plugin_${_manifest.id}',
        name: _manifest.displayName,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
      functions: [function],
    );

    // 3. 用 NodeInterpreter 执行函数。
    //    pluginConfigStorage 传 null：函数插件内的嵌套 plugin_* 节点
    //    需要自行从 registry 查找执行器，但配置由调用方通过 config
    //    参数传入。这里简化处理：嵌套插件的配置读取由 _execPlugin
    //    在 NodeInterpreter 内通过 pluginConfigStorage 完成；本执行器
    //    不持有 pluginConfigStorage，嵌套插件若需配置将使用空 config。
    //    （如需支持嵌套带配置的插件，可后续扩展。）
    final interpreter = NodeInterpreter(
      project: minimalProject,
      pluginRegistry: _pluginRegistry,
      // dbExecutor / uiState 为 null：函数插件禁用 db_* / ui_* 节点，
      // 即使节点误用也会在执行时抛错，不影响正常流程。
    );

    // 4. 按 spec.inputs 声明过滤 inputs，避免传入未声明的参数。
    final filteredInputs = <String, dynamic>{};
    for (final input in spec.inputs) {
      filteredInputs[input.name] = inputs[input.name];
    }

    // 5. 执行函数。
    final result = await interpreter.runFunction(function, filteredInputs);

    if (result.error != null) {
      throw StateError('函数插件 ${_manifest.id} 执行失败: ${result.error}');
    }

    // 6. 透传输出（键对齐 spec.outputs）。
    //    RunResult.outputs 已按 function_output 节点的 values 映射，
    //    与 spec.outputs 名对齐（发布时由 UI 保证一致）。
    return Map<String, dynamic>.from(result.outputs);
  }
}
