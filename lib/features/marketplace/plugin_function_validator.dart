import '../../data/models/entry.dart';
import '../../data/models/function_def.dart';
import '../../data/models/node.dart';

/// 插件函数校验器：检查一个 [FunctionDef] 是否可作为插件发布。
///
/// 函数插件相比项目内函数有以下限制（依赖项目上下文的节点不允许）：
/// - 禁用项目变量（`variable_set` 节点 `target == 'projVar'`）；
/// - 禁用数据库节点（所有 `db_*` 节点）；
/// - 禁用 UI 控制节点（所有 `ui_*` 节点）；
/// - 禁用函数调用节点（`function_call`，依赖项目内其他函数）；
/// - 禁用定时器/外部触发器（`entry.kind` 为 `timer` / `external`，
///   以及 `uiEvent` / `pageEvent`，因为它们依赖宿主项目 UI/页面）。
///
/// 允许的节点：纯运算、逻辑、流程控制、网络请求（http_request / open_link）、
/// 已安装插件（plugin_*）、函数局部变量（variable_set 的 funcVar target）。
class PluginFunctionValidator {
  PluginFunctionValidator._();

  /// 校验函数是否可作为插件发布。
  ///
  /// 返回校验结果列表（[PluginValidationResult]）。若 [problems] 为空，
  /// 表示函数符合插件发布要求。
  static PluginValidationResult validate(FunctionDef function) {
    final problems = <PluginValidationProblem>[];

    // 1. 校验函数入口：仅允许 funcCall 或 null（被显式调用）。
    //    timer / external / uiEvent / pageEvent 都依赖宿主项目上下文。
    final entry = function.entry;
    if (entry != null && entry.kind != EntryKind.funcCall) {
      problems.add(PluginValidationProblem(
        type: PluginValidationProblemType.disallowedTrigger,
        message: '函数入口为「${_entryKindLabel(entry.kind)}」，'
            '插件函数仅支持「被调用」入口。请清除函数的触发器后再发布。',
      ));
    }

    // 2. 逐节点校验。
    for (final node in function.nodes) {
      _validateNode(node, problems);
    }

    return PluginValidationResult(problems: problems);
  }

  /// 校验单个节点是否符合插件函数要求。
  static void _validateNode(Node node, List<PluginValidationProblem> problems) {
    final kind = node.kind;

    // 禁用数据库节点。
    if (kind.startsWith('db_')) {
      problems.add(PluginValidationProblem(
        type: PluginValidationProblemType.disallowedNode,
        nodeId: node.id,
        nodeName: _nodeDisplayName(node),
        message: '数据库节点「${_nodeDisplayName(node)}」依赖项目数据库，'
            '不能用于插件函数。',
      ));
      return;
    }

    // 禁用 UI 控制节点。
    if (kind.startsWith('ui_')) {
      problems.add(PluginValidationProblem(
        type: PluginValidationProblemType.disallowedNode,
        nodeId: node.id,
        nodeName: _nodeDisplayName(node),
        message: 'UI 控制节点「${_nodeDisplayName(node)}」依赖项目 UI 树，'
            '不能用于插件函数。',
      ));
      return;
    }

    // 禁用函数调用节点。
    if (kind == 'function_call') {
      problems.add(PluginValidationProblem(
        type: PluginValidationProblemType.disallowedNode,
        nodeId: node.id,
        nodeName: _nodeDisplayName(node),
        message: '函数调用节点「${_nodeDisplayName(node)}」依赖项目内其他函数，'
            '不能用于插件函数。',
      ));
      return;
    }

    // variable_set 节点：仅允许 funcVar target，禁用 projVar。
    if (kind == 'variable_set') {
      final target = node.params['target']?.toString();
      if (target == 'projVar') {
        problems.add(PluginValidationProblem(
          type: PluginValidationProblemType.disallowedNode,
          nodeId: node.id,
          nodeName: _nodeDisplayName(node),
          message: '设置变量节点「${_nodeDisplayName(node)}」引用了项目变量，'
              '插件函数不能使用项目变量。',
        ));
      }
      return;
    }
  }

  /// 获取节点显示名（优先使用 params.name，否则用 kind）。
  static String _nodeDisplayName(Node node) {
    final name = node.params['name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    return node.kind;
  }

  /// 触发类型中文标签。
  static String _entryKindLabel(EntryKind kind) {
    switch (kind) {
      case EntryKind.uiEvent:
        return 'UI 事件';
      case EntryKind.pageEvent:
        return '页面事件';
      case EntryKind.timer:
        return '定时器';
      case EntryKind.external:
        return '外部触发';
      case EntryKind.funcCall:
        return '被调用';
    }
  }
}

/// 插件函数校验问题类型。
enum PluginValidationProblemType {
  /// 禁用的触发器（timer / external / uiEvent / pageEvent）。
  disallowedTrigger,

  /// 禁用的节点（db_* / ui_* / function_call / projVar variable_set）。
  disallowedNode,
}

/// 插件函数校验问题。
class PluginValidationProblem {
  const PluginValidationProblem({
    required this.type,
    required this.message,
    this.nodeId,
    this.nodeName,
  });

  final PluginValidationProblemType type;
  final String message;
  final String? nodeId;
  final String? nodeName;
}

/// 插件函数校验结果。
class PluginValidationResult {
  const PluginValidationResult({required this.problems});

  final List<PluginValidationProblem> problems;

  /// 是否通过校验（无问题）。
  bool get isValid => problems.isEmpty;
}
