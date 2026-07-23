import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/entry.dart';
import '../../data/models/function_def.dart';
import '../../data/models/project.dart';
import '../../data/models/ui_tree.dart';
import '../../data/models/variable_ref.dart';
import '../functions/function_providers.dart';
import '../project/project_providers.dart';

const Uuid _uuid = Uuid();

/// UI 节点查找结果：节点本身 + 其父节点（根节点父为 null）。
class UiNodeSearchResult {
  const UiNodeSearchResult(this.node, this.parent);

  final UiNode node;

  /// 父节点；根节点为 null。
  final UiNode? parent;
}

/// 当前选中的 UI 节点 id（null 表示未选中，仅画布层 UI 状态，不持久化）。
final selectedUiNodeIdProvider = StateProvider<String?>((ref) => null);

/// UI 段变更器：管理 [Project.ui] 树 + 组件触发点绑定 + 定时器 entry。
///
/// state 始终镜像 [projectMutatorProvider]（在 [build] 中 watch），
/// 所有变更方法把新 [Project] 快照写回 [currentProjectProvider] 并异步落盘。
/// UI 通过 `ref.watch(uiMutatorProvider)` 获取当前项目，
/// 通过 `ref.read(uiMutatorProvider.notifier).xxx()` 执行变更。
class UiMutator extends Notifier<Project?> {
  @override
  Project? build() {
    return ref.watch(projectMutatorProvider);
  }

  Project? get _project => ref.read(currentProjectProvider);

  void _commit(Project newProject) {
    ref.read(currentProjectProvider.notifier).state = newProject;
    // 持久化失败不阻塞 UI；仓库内部会刷新 updatedAt。
    ref.read(projectRepositoryProvider).saveProject(newProject);
  }

  // ---- 选中 ----

  /// 选中组件；id 为 null 表示取消选中。
  void selectComponent(String? id) {
    ref.read(selectedUiNodeIdProvider.notifier).state = id;
  }

  // ---- 查找 ----

  /// 在整棵 UI 树中查找节点；返回节点与其父节点（根节点父为 null）。
  UiNodeSearchResult? findNode(String id) {
    final p = _project;
    if (p == null) return null;
    for (final root in p.ui) {
      final res = _findInTree(root, id, null);
      if (res != null) return res;
    }
    return null;
  }

  UiNodeSearchResult? _findInTree(UiNode node, String id, UiNode? parent) {
    if (node.id == id) return UiNodeSearchResult(node, parent);
    for (final child in node.children) {
      final res = _findInTree(child, id, node);
      if (res != null) return res;
    }
    return null;
  }

  /// 判断 [descendantId] 是否为 [ancestorId] 的后代（含自身）。
  bool _isDescendantOrSelf(String ancestorId, String descendantId) {
    final res = findNode(ancestorId);
    if (res == null) return false;
    bool search(UiNode n) {
      if (n.id == descendantId) return true;
      return n.children.any(search);
    }
    return search(res.node);
  }

  // ---- 添加 ----

  /// 添加组件；parentId 为 null 时添加为根节点，否则添加为 parentId 的子节点。
  /// 返回新节点 id（项目未打开时返回空字符串）。
  String addComponent(String type, {String? parentId}) {
    final p = _project;
    if (p == null) return '';
    final node = _createDefaultNode(type);
    final newUi = parentId == null
        ? <UiNode>[...p.ui, node]
        : p.ui
            .map((r) => _insertChild(r, parentId, node))
            .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
    selectComponent(node.id);
    return node.id;
  }

  /// 递归插入子节点到指定父节点下。
  UiNode _insertChild(UiNode node, String parentId, UiNode child) {
    if (node.id == parentId) {
      return node.copyWith(children: [...node.children, child]);
    }
    if (node.children.isEmpty) return node;
    return node.copyWith(
      children: node.children
          .map((c) => _insertChild(c, parentId, child))
          .toList(growable: false),
    );
  }

  // ---- 删除 ----

  /// 删除组件；同时清理其关联的触发点绑定与选中态。
  void removeComponent(String id) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _removeFromTree(r, id))
        .whereType<UiNode>()
        .toList(growable: false);
    // 清理该组件相关的 uiEvent 触发点绑定。
    final prefix = '$id::';
    final newFuncs = p.functions.map((f) {
      final entry = f.entry;
      if (entry != null &&
          entry.kind == EntryKind.uiEvent &&
          entry.ref != null &&
          entry.ref!.startsWith(prefix)) {
        return f.copyWith(entry: null);
      }
      return f;
    }).toList(growable: false);
    _commit(p.copyWith(ui: newUi, functions: newFuncs));
    if (ref.read(selectedUiNodeIdProvider) == id) {
      selectComponent(null);
    }
  }

  UiNode? _removeFromTree(UiNode node, String id) {
    if (node.id == id) return null;
    if (node.children.isEmpty) return node;
    final newChildren = node.children
        .map((c) => _removeFromTree(c, id))
        .whereType<UiNode>()
        .toList(growable: false);
    return node.copyWith(children: newChildren);
  }

  // ---- 复制 ----

  /// 复制组件（含子树）到原父节点下；返回新节点 id。
  String duplicateComponent(String id) {
    final p = _project;
    if (p == null) return '';
    final found = findNode(id);
    if (found == null) return '';
    final copy = _deepCopy(found.node);
    final List<UiNode> newUi;
    if (found.parent == null) {
      newUi = [...p.ui, copy];
    } else {
      newUi = p.ui
          .map((r) => _insertChild(r, found.parent!.id, copy))
          .toList(growable: false);
    }
    _commit(p.copyWith(ui: newUi));
    selectComponent(copy.id);
    return copy.id;
  }

  UiNode _deepCopy(UiNode node) {
    return UiNode(
      id: _uuid.v4(),
      type: node.type,
      props: Map<String, dynamic>.from(node.props),
      children: node.children.map(_deepCopy).toList(growable: false),
      bindings: Map<String, Binding>.from(node.bindings),
    );
  }

  // ---- 移动 ----

  /// 移动组件到新父节点下；newParentId 为 '__root__' 时移到根列表。
  /// 不允许移入自身或自身的子树。
  void moveComponent(String id, String newParentId) {
    final p = _project;
    if (p == null) return;
    if (newParentId != '__root__' &&
        _isDescendantOrSelf(id, newParentId)) {
      return;
    }
    final found = findNode(id);
    if (found == null) return;
    final moving = found.node;
    // 从原位置移除。
    var newUi = p.ui
        .map((r) => _removeFromTree(r, id))
        .whereType<UiNode>()
        .toList(growable: false);
    // 插入到新位置。
    if (newParentId == '__root__') {
      newUi = [...newUi, moving];
    } else {
      newUi = newUi
          .map((r) => _insertChild(r, newParentId, moving))
          .toList(growable: false);
    }
    _commit(p.copyWith(ui: newUi));
  }

  // ---- 更新属性 ----

  /// 整体替换节点 props（合并）。
  void updateProps(String id, Map<String, dynamic> props) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id,
            (n) => n.copyWith(props: {...n.props, ...props}),),)
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 更新单个属性。
  void updateProp(String id, String key, Object? value) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id, (n) {
              final newProps = Map<String, dynamic>.from(n.props);
              newProps[key] = value;
              return n.copyWith(props: newProps);
            }),)
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  UiNode _updateNode(
      UiNode node, String id, UiNode Function(UiNode) updater,) {
    if (node.id == id) return updater(node);
    if (node.children.isEmpty) return node;
    return node.copyWith(
      children: node.children
          .map((c) => _updateNode(c, id, updater))
          .toList(growable: false),
    );
  }

  // ---- 属性绑定 ----

  /// 设置属性绑定；binding 为 null 时移除该属性绑定。
  ///
  /// v1 简化实现：复用 [VariableRef.upstream]，nodeId 存函数 id，
  /// outputName 存函数内某数据输出名。
  void setBinding(String id, String prop, Binding? binding) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id, (n) {
              final newBindings = Map<String, Binding>.from(n.bindings);
              if (binding == null) {
                newBindings.remove(prop);
              } else {
                newBindings[prop] = binding;
              }
              return n.copyWith(bindings: newBindings);
            }),)
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  // ---- 触发点（uiEvent entry）----

  /// 编码组件触发点引用：`componentId::eventName`。
  static String encodeTriggerRef(String componentId, String eventName) =>
      '$componentId::$eventName';

  /// 设置组件触发点绑定到函数；funcId 为 null 时移除绑定。
  ///
  /// 触发点绑定即把目标函数的 entry 设为
  /// [FunctionEntry]（kind: uiEvent, ref: `componentId::eventName`）。
  /// 同一 componentId+eventName 仅允许绑定一个函数：先清除旧绑定。
  void setTrigger(String componentId, String eventName, String? funcId) {
    final p = _project;
    if (p == null) return;
    final ref = encodeTriggerRef(componentId, eventName);
    // 清除该 componentId+eventName 的旧绑定。
    var newFuncs = p.functions.map((f) {
      final entry = f.entry;
      if (entry != null &&
          entry.kind == EntryKind.uiEvent &&
          entry.ref == ref) {
        return f.copyWith(entry: null);
      }
      return f;
    }).toList(growable: false);
    // 设置目标函数的 entry。
    if (funcId != null) {
      newFuncs = newFuncs
          .map((f) => f.id == funcId
              ? f.copyWith(
                  entry: FunctionEntry(kind: EntryKind.uiEvent, ref: ref),)
              : f,)
          .toList(growable: false);
    }
    _commit(p.copyWith(functions: newFuncs));
  }

  /// 移除组件触发点绑定。
  void removeTrigger(String componentId, String eventName) {
    setTrigger(componentId, eventName, null);
  }

  /// 查找组件某事件绑定的函数 id；未绑定返回 null。
  String? getTriggerFunctionId(String componentId, String eventName) {
    final p = _project;
    if (p == null) return null;
    final ref = encodeTriggerRef(componentId, eventName);
    for (final f in p.functions) {
      final entry = f.entry;
      if (entry != null &&
          entry.kind == EntryKind.uiEvent &&
          entry.ref == ref) {
        return f.id;
      }
    }
    return null;
  }

  // ---- 定时器 entry ----

  /// 为函数设置定时器 entry；intervalMs 为毫秒。
  void setTimerEntry(String funcId, int intervalMs) {
    final p = _project;
    if (p == null) return;
    final newFuncs = p.functions
        .map((f) => f.id == funcId
            ? f.copyWith(
                entry: FunctionEntry(kind: EntryKind.timer, ref: '$intervalMs'),)
            : f,)
        .toList(growable: false);
    _commit(p.copyWith(functions: newFuncs));
  }

  /// 清除函数的 entry（用于删除定时器 / 触发点）。
  void clearEntry(String funcId) {
    final p = _project;
    if (p == null) return;
    final newFuncs = p.functions
        .map((f) => f.id == funcId ? f.copyWith(entry: null) : f)
        .toList(growable: false);
    _commit(p.copyWith(functions: newFuncs));
  }

  // ---- 默认节点工厂 ----

  /// 按 type 生成默认 UI 节点（含默认 props）。
  UiNode _createDefaultNode(String type) {
    final id = _uuid.v4();
    switch (type) {
      case 'column':
        return UiNode(id: id, type: type, props: const {
          'mainAxisAlignment': 'start',
          'crossAxisAlignment': 'center',
        },);
      case 'row':
        return UiNode(id: id, type: type, props: const {
          'mainAxisAlignment': 'start',
          'crossAxisAlignment': 'center',
        },);
      case 'text':
        return UiNode(
            id: id, type: type, props: const {'content': '文本'},);
      case 'button':
        return UiNode(
            id: id, type: type, props: const {'label': '按钮'},);
      case 'text_field':
        return UiNode(id: id, type: type, props: const {
          'hint': '请输入',
          'label': '',
        },);
      case 'image':
        return UiNode(id: id, type: type, props: const {'src': ''});
      case 'list_view':
        return UiNode(id: id, type: type, props: const {});
      case 'container':
        return UiNode(id: id, type: type, props: const {
          'color': '#FFFFFF',
          'padding': 8,
        },);
      case 'scaffold':
        return UiNode(id: id, type: type, props: const {});
      default:
        return UiNode(id: id, type: type, props: const {});
    }
  }
}

/// UI 段变更器 provider。
final uiMutatorProvider =
    NotifierProvider<UiMutator, Project?>(UiMutator.new);

// ---- 纯函数工具 ----

/// 收集函数内所有命名数据输出名（去重，保留出现顺序）。
List<String> collectFunctionOutputNames(FunctionDef fn) {
  final seen = <String>{};
  final result = <String>[];
  for (final node in fn.nodes) {
    for (final out in node.dataOutputs) {
      if (seen.add(out.name)) {
        result.add(out.name);
      }
    }
  }
  return result;
}
