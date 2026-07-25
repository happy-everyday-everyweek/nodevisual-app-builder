import '../../features/node_graph/dag_validator.dart';
import '../../features/node_graph/node_kinds.dart';
import '../../features/node_graph/type_checker.dart';
import '../models/entry.dart';
import '../models/folder.dart';
import '../models/function_def.dart';
import '../models/node.dart';
import '../models/port.dart';
import '../models/project.dart';
import '../models/ui_tree.dart';
import '../models/variable_ref.dart';

/// IR 校验问题严重级别。
enum IssueSeverity {
  /// 错误：阻断执行或导致语义错误。
  error,

  /// 警告：可执行但有风险（如类型不匹配）。
  warning,
}

/// IR 校验发现的问题。
class Issue {
  /// 严重级别。
  final IssueSeverity severity;

  /// 中文描述。
  final String message;

  /// 问题定位路径（如 `functions.<id>.nodes.<id>`）。
  final String path;

  const Issue({
    required this.severity,
    required this.message,
    required this.path,
  });

  @override
  String toString() => '[${severity.name}] $path: $message';
}

/// IR 完整性校验器。
///
/// 对 [Project] 做引用完整性、DAG 无环、入口引用、文件夹树、节点参数
/// `#` 引用类型等校验，返回 [Issue] 列表（空列表表示通过）。
///
/// 校验项：
/// - [VariableRef] 的 nodeId / outputName / varId 指向的节点 / 输出 / 变量是否存在；
/// - [ControlEdge] 的 fromNode / toNode 存在；
/// - 控制流图 DAG 无环（复用 [DagValidator]）；
/// - 函数 [FunctionEntry] 引用的 UI 组件 / 函数存在；
/// - 节点 params 中 `#` 引用的类型与目标参数期望类型匹配（warning 级，用 [checkRefType]）；
/// - 文件夹 parentId 无环、函数 folderId 指向存在的 folder。
class IrValidator {
  IrValidator._();

  /// 校验 [Project]，返回问题列表（空列表表示通过）。
  static List<Issue> validate(Project project) {
    final issues = <Issue>[];

    // 校验每个函数（DAG、边、引用、entry）。
    for (final fn in project.functions) {
      _validateFunction(fn, project, issues);
    }

    // 校验文件夹树（parentId 无环、folderId 指向存在）。
    _validateFolders(project, issues);

    // 校验函数 folderId 指向存在的 folder。
    final folderIds = <String>{for (final f in project.folders) f.id};
    for (final fn in project.functions) {
      if (fn.folderId != null && !folderIds.contains(fn.folderId)) {
        issues.add(Issue(
          severity: IssueSeverity.error,
          path: 'functions.${fn.id}',
          message: '函数 ${fn.name} 的 folderId "${fn.folderId}" '
              '指向不存在的文件夹',
        ),);
      }
    }

    return issues;
  }

  /// 校验单个函数：DAG 无环 + 边引用 + 节点 # 引用 + entry。
  static void _validateFunction(
    FunctionDef fn,
    Project project,
    List<Issue> issues,
  ) {
    final path = 'functions.${fn.id}';
    final nodeIds = <String>{for (final n in fn.nodes) n.id};

    // DAG 无环 + 边引用合法性 + 单入 + 孤立节点（复用 dag_validator）。
    final dagErrors = DagValidator.validateGraph(fn);
    for (final e in dagErrors) {
      issues.add(Issue(
        severity: IssueSeverity.error,
        path: path,
        message: e,
      ),);
    }

    // 显式校验 ControlEdge.fromNode / toNode 存在（dag_validator 也做，
    // 这里更精确地按边定位）。
    for (final edge in fn.controlEdges) {
      if (!nodeIds.contains(edge.fromNode)) {
        issues.add(Issue(
          severity: IssueSeverity.error,
          path: '$path.controlEdges',
          message: '控制流边 ${edge.fromNode}.${edge.fromPort} -> '
              '${edge.toNode} 的源节点不存在',
        ),);
      }
      if (!nodeIds.contains(edge.toNode)) {
        issues.add(Issue(
          severity: IssueSeverity.error,
          path: '$path.controlEdges',
          message: '控制流边 ${edge.fromNode}.${edge.fromPort} -> '
              '${edge.toNode} 的目标节点不存在',
        ),);
      }
    }

    // 校验节点 params 中的 # 引用（引用完整性 + 类型匹配 warning）。
    for (final node in fn.nodes) {
      _validateNodeRefs(node, fn, project, issues, '$path.nodes.${node.id}');
    }

    // 校验函数 entry 引用。
    if (fn.entry != null) {
      _validateEntry(fn.entry!, project, issues, '$path.entry');
    }
  }

  /// 校验节点 params 中的所有 # 引用。
  static void _validateNodeRefs(
    Node node,
    FunctionDef fn,
    Project project,
    List<Issue> issues,
    String path,
  ) {
    final spec = NodeKindRegistry.getSpec(node.kind);
    for (final entry in node.params.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic> && value.containsKey('source')) {
        final ref = VariableRef.fromJson(value);
        _validateRef(ref, fn, project, spec, entry.key, issues, path);
      }
    }
  }

  /// 校验单个 [VariableRef] 的引用完整性与类型匹配。
  static void _validateRef(
    VariableRef ref,
    FunctionDef fn,
    Project project,
    NodeKindSpec? spec,
    String paramName,
    List<Issue> issues,
    String path,
  ) {
    // ---- 引用完整性 ----
    switch (ref.source) {
      case VariableSource.upstream:
        final nodeId = ref.nodeId;
        final outputName = ref.outputName;
        if (nodeId == null || outputName == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 的 upstream 引用缺少 '
                'nodeId / outputName',
          ),);
          break;
        }
        Node? target;
        for (final n in fn.nodes) {
          if (n.id == nodeId) {
            target = n;
            break;
          }
        }
        if (target == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 引用的节点 $nodeId 不存在',
          ),);
          break;
        }
        bool outputExists = false;
        for (final out in target.dataOutputs) {
          if (out.name == outputName) {
            outputExists = true;
            break;
          }
        }
        if (!outputExists) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 引用的输出 '
                '$nodeId.$outputName 不存在',
          ),);
        }
        break;
      case VariableSource.funcVar:
        // 页面级函数 outputs 引用：校验目标函数存在且 outputs 含该名。
        if (ref.isPageFunc) {
          final funcId = ref.funcId;
          final outputName = ref.outputName;
          if (funcId == null || outputName == null) {
            issues.add(Issue(
              severity: IssueSeverity.error,
              path: path,
              message: '参数 $paramName 的页面函数 outputs 引用缺少 '
                  'funcId / outputName',
            ),);
            break;
          }
          FunctionDef? targetFn;
          for (final f in project.functions) {
            if (f.id == funcId) {
              targetFn = f;
              break;
            }
          }
          if (targetFn == null) {
            issues.add(Issue(
              severity: IssueSeverity.error,
              path: path,
              message: '参数 $paramName 引用的页面函数 $funcId 不存在',
            ),);
            break;
          }
          bool outputExists = false;
          for (final out in targetFn.outputs) {
            if (out.name == outputName) {
              outputExists = true;
              break;
            }
          }
          if (!outputExists) {
            issues.add(Issue(
              severity: IssueSeverity.error,
              path: path,
              message: '参数 $paramName 引用的函数 $funcId '
                  '无 outputs 名 $outputName',
            ),);
          }
          break;
        }
        final varId = ref.varId;
        if (varId == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 的 funcVar 引用缺少 varId',
          ),);
          break;
        }
        bool varExists = false;
        for (final v in fn.funcVars) {
          if (v.id == varId) {
            varExists = true;
            break;
          }
        }
        if (!varExists) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 引用的函数变量 $varId 不存在',
          ),);
        }
        break;
      case VariableSource.projVar:
        final varId = ref.varId;
        if (varId == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 的 projVar 引用缺少 varId',
          ),);
          break;
        }
        bool varExists = false;
        for (final v in project.projectVars) {
          if (v.id == varId) {
            varExists = true;
            break;
          }
        }
        if (!varExists) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 引用的项目变量 $varId 不存在',
          ),);
        }
        break;
      case VariableSource.component:
        // 组件上下文变量在运行时由容器组件注入，静态无法校验存在性；
        // 仅校验引用字段非空（componentId / fieldName 缺失视为引用损坏）。
        if (ref.componentId == null || ref.fieldName == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 的 component 引用缺少 '
                'componentId / fieldName',
          ),);
        }
        break;
      case VariableSource.device:
        // 设备变量：只读属性，校验 property 非空且属于支持的属性列表。
        if (ref.property == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '参数 $paramName 的 device 引用缺少 property',
          ),);
        } else if (!DeviceProperty.all.contains(ref.property)) {
          issues.add(Issue(
            severity: IssueSeverity.warning,
            path: path,
            message: '参数 $paramName 的 device 引用属性 '
                '"${ref.property}" 不在支持列表中（'
                '${DeviceProperty.all.join(", ")}），运行时回退为设备类型',
          ),);
        }
        break;
    }

    // ---- 类型匹配（warning 级，用 type_checker）----
    if (spec != null) {
      PortType? expected;
      for (final p in spec.paramSchema) {
        if (p.name == paramName && p.acceptsRef) {
          expected = p.expectedType ?? PortType.any;
          break;
        }
      }
      if (expected != null && expected != PortType.any) {
        final result = checkRefType(ref, expected, fn, project);
        if (!result.ok) {
          issues.add(Issue(
            severity: IssueSeverity.warning,
            path: path,
            message: '参数 $paramName 类型不匹配：${result.reason}',
          ),);
        }
      }
    }
  }

  /// 校验函数 entry 的 ref 引用。
  ///
  /// - [EntryKind.uiEvent]：ref 指向 UI 节点 id（`componentId::eventName`），
  ///   需在 [Project.ui] 树中存在。
  /// - [EntryKind.pageEvent]：ref 形如 `<pageId>:<event>`，校验 pageId 在
  ///   [Project.pages] 中存在、event ∈ [PageEventName.all]。
  /// - [EntryKind.funcCall]：ref 为空（由调用方决定），无需校验。
  /// - [EntryKind.timer] / [EntryKind.external]：v1 不校验配置存在性。
  static void _validateEntry(
    FunctionEntry entry,
    Project project,
    List<Issue> issues,
    String path,
  ) {
    switch (entry.kind) {
      case EntryKind.uiEvent:
        // uiEvent ref 形如 `componentId::eventName`，校验组件存在。
        if (entry.ref == null) {
          issues.add(Issue(
            severity: IssueSeverity.warning,
            path: path,
            message: 'UI 事件入口未指定 ref（UI 元素 id）',
          ),);
          break;
        }
        // 解析 componentId（`::` 之前）。
        final refStr = entry.ref!;
        final sepIdx = refStr.indexOf('::');
        final componentId =
            sepIdx > 0 ? refStr.substring(0, sepIdx) : refStr;
        if (!_uiNodeExists(project.ui, componentId)) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '入口 ref "${entry.ref}" 指向的 UI 节点不存在',
          ),);
        }
        break;
      case EntryKind.pageEvent:
        final pageId = entry.pageId;
        final event = entry.pageEvent;
        if (pageId == null || event == null) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '页面事件入口 ref "${entry.ref}" 格式不合法'
                '（应为 <pageId>:<event>）',
          ),);
          break;
        }
        bool pageExists = false;
        for (final p in project.pages) {
          if (p.id == pageId) {
            pageExists = true;
            break;
          }
        }
        if (!pageExists) {
          issues.add(Issue(
            severity: IssueSeverity.error,
            path: path,
            message: '页面事件入口指向的页面 $pageId 不存在',
          ),);
        }
        break;
      case EntryKind.funcCall:
        // ref 为空，无需校验。
        break;
      case EntryKind.timer:
      case EntryKind.external:
        // v1 不校验配置存在性。
        break;
    }
  }

  /// 在 UI 树中递归查找指定 id 的节点。
  static bool _uiNodeExists(List<UiNode> roots, String id) {
    for (final node in roots) {
      if (node.id == id) return true;
      if (_uiNodeExists(node.children, id)) return true;
    }
    return false;
  }

  /// 校验文件夹树：parentId 指向存在 + parentId 无环。
  static void _validateFolders(Project project, List<Issue> issues) {
    final folderIds = <String>{for (final f in project.folders) f.id};

    // parentId 指向存在的 folder。
    for (final folder in project.folders) {
      if (folder.parentId != null && !folderIds.contains(folder.parentId)) {
        issues.add(Issue(
          severity: IssueSeverity.error,
          path: 'folders.${folder.id}',
          message: '文件夹 ${folder.name} 的 parentId '
              '"${folder.parentId}" 指向不存在的文件夹',
        ),);
      }
    }

    // parentId 无环（沿 parentId 链向上追溯，回到访问过的节点即环）。
    if (_hasFolderCycle(project.folders)) {
      issues.add(const Issue(
        severity: IssueSeverity.error,
        path: 'folders',
        message: '文件夹 parentId 形成环',
      ),);
    }
  }

  /// 检测文件夹 parentId 是否形成环。
  static bool _hasFolderCycle(List<Folder> folders) {
    final parentMap = <String, String?>{};
    for (final f in folders) {
      parentMap[f.id] = f.parentId;
    }
    for (final folder in folders) {
      final visited = <String>{};
      String? current = folder.id;
      while (current != null && parentMap.containsKey(current)) {
        if (!visited.add(current)) {
          return true; // 回到访问过的节点 = 环。
        }
        current = parentMap[current];
      }
    }
    return false;
  }
}
