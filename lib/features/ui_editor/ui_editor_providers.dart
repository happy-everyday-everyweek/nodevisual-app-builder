import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/entry.dart';
import '../../data/models/function_def.dart';
import '../../data/models/page.dart';
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

/// 当前选中的 Page 节点 id（仅画布层 UI 状态，不持久化）。
///
/// Phase 4 v2 引入：UI 编辑器主视图聚焦单一 Page 渲染，
/// 此处记录当前画布正在编辑的 Page 节点 id（应为 [Project.ui] 中 type=='page' 的节点）。
/// null 表示尚未选择任何页面（无 Page 时画布显示引导提示）。
final selectedPageIdProvider = StateProvider<String?>((ref) => null);

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

  /// 更新节点布局配置；layout 为 null 时清除布局（退化为默认流式布局）。
  ///
  /// 供布局属性面板与长按移动模式处理器提交 [LayoutConfig] 变更使用。
  void updateLayout(String id, LayoutConfig? layout) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id, (n) => n.copyWith(layout: layout)))
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 更新单个样式键值（写入 [UiNode.style]）。
  ///
  /// 供 Phase 4 v2 样式段编辑器使用：value 为 null 时移除该样式键。
  void updateStyleProp(String id, String key, Object? value) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id, (n) {
              final newStyle = Map<String, dynamic>.from(n.style);
              if (value == null) {
                newStyle.remove(key);
              } else {
                newStyle[key] = value;
              }
              return n.copyWith(style: newStyle);
            }),)
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 整体替换节点样式（合并）。
  void updateStyle(String id, Map<String, dynamic> style) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id,
            (n) => n.copyWith(style: {...n.style, ...style}),),)
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 更新节点动画配置；animations 为 null 时清除动画。
  ///
  /// 供 Phase 4 v2 样式段内的动画配置区使用。
  void updateAnimations(String id, AnimationsConfig? animations) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) =>
            _updateNode(r, id, (n) => n.copyWith(animations: animations)),)
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

  // ---- 页面管理 ----

  /// 新建页面；返回创建的 Page 节点（特殊 UiNode，type=='page'）。
  ///
  /// Page 节点的 children 为该页面的 UI 根节点树（初始为空）。
  /// 首个页面自动设为首页（isHome=true）。
  UiNode? addPage(String name) {
    final p = _project;
    if (p == null) return null;
    final isFirstPage = p.ui.where((n) => n.isPage).isEmpty;
    final pageNode = createPageNode(
      id: _uuid.v4(),
      name: name,
      isHome: isFirstPage,
    );
    _commit(p.copyWith(ui: [...p.ui, pageNode]));
    return pageNode;
  }

  /// 更新页面字段（Page 节点的 props）。
  ///
  /// [name] / [route] / [isHome] 直接写入 Page 节点的 props。
  /// isHome 唯一性：设为 home 时清除其他 Page 节点的 isHome。
  void updatePage(String pageId, {String? name, String? route, bool? isHome}) {
    final p = _project;
    if (p == null) return;
    var newUi = p.ui.map((node) {
      if (node.id != pageId || !node.isPage) return node;
      final newProps = Map<String, dynamic>.from(node.props);
      if (name != null) newProps[PagePropsKeys.name] = name;
      if (route != null) newProps[PagePropsKeys.route] = route;
      if (isHome == true) newProps[PagePropsKeys.isHome] = true;
      return node.copyWith(props: newProps);
    }).toList(growable: false);
    // isHome 唯一性：设为 home 时清除其他 Page 节点的 isHome。
    if (isHome == true) {
      newUi = newUi.map((node) {
        if (!node.isPage || node.id == pageId) return node;
        if (!node.isHomePage) return node;
        final newProps = Map<String, dynamic>.from(node.props);
        newProps.remove(PagePropsKeys.isHome);
        return node.copyWith(props: newProps);
      }).toList(growable: false);
    }
    _commit(p.copyWith(ui: newUi));
  }

  /// 删除页面（Page 节点）；同时清除关联的页面事件 entry。
  void removePage(String pageId) {
    final p = _project;
    if (p == null) return;
    final newFuncs = p.functions.map((f) {
      final entry = f.entry;
      if (entry != null &&
          entry.kind == EntryKind.pageEvent &&
          entry.pageId == pageId) {
        return f.copyWith(entry: null);
      }
      return f;
    }).toList(growable: false);
    _commit(p.copyWith(
      ui: p.ui.where((n) => n.id != pageId).toList(growable: false),
      functions: newFuncs,
    ));
  }

  /// 绑定页面事件到函数；funcId 为 null 时移除绑定。
  ///
  /// 页面事件绑定即把目标函数的 entry 设为
  /// [FunctionEntry.pageEvent]（ref: `pageId:event`）。
  /// 同一 pageId+event 仅允许绑定一个函数。
  void setPageEventFunction(String pageId, String event, String? funcId) {
    final p = _project;
    if (p == null) return;
    // 清除该 pageId+event 的旧绑定。
    var newFuncs = p.functions.map((f) {
      final entry = f.entry;
      if (entry != null && entry.matchesPageEvent(pageId, event)) {
        return f.copyWith(entry: null);
      }
      return f;
    }).toList(growable: false);
    // 设置目标函数的 entry。
    if (funcId != null) {
      newFuncs = newFuncs
          .map((f) => f.id == funcId
              ? f.copyWith(
                  entry: FunctionEntry.pageEvent(pageId: pageId, event: event),)
              : f,)
          .toList(growable: false);
    }
    _commit(p.copyWith(functions: newFuncs));
  }

  /// 查找页面某事件绑定的函数 id；未绑定返回 null。
  String? getPageEventFunctionId(String pageId, String event) {
    final p = _project;
    if (p == null) return null;
    for (final f in p.functions) {
      final entry = f.entry;
      if (entry != null && entry.matchesPageEvent(pageId, event)) {
        return f.id;
      }
    }
    return null;
  }

  /// 获取页面下所有页面事件绑定的函数（按事件名分组）。
  Map<String, String> getPageEventBindings(String pageId) {
    final p = _project;
    if (p == null) return {};
    final result = <String, String>{};
    for (final f in p.functions) {
      final entry = f.entry;
      if (entry != null &&
          entry.kind == EntryKind.pageEvent &&
          entry.pageId == pageId &&
          entry.pageEvent != null) {
        result[entry.pageEvent!] = f.id;
      }
    }
    return result;
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
      case 'rich_text':
        return UiNode(id: id, type: type, props: const {'content': '富文本内容'});
      case 'icon':
        return UiNode(id: id, type: type, props: const {
          'name': 'star',
          'size': 24,
        });
      case 'badge':
        return UiNode(id: id, type: type, props: const {'count': '0'});
      case 'divider':
        return UiNode(id: id, type: type, props: const {'thickness': 1});
      case 'spacer':
        return UiNode(id: id, type: type, props: const {'flex': 1});
      case 'video':
        return UiNode(id: id, type: type, props: const {'src': ''});
      case 'slider':
        return UiNode(id: id, type: type, props: const {
          'value': 0.5,
          'min': 0,
          'max': 1,
        });
      case 'switch':
        return UiNode(id: id, type: type, props: const {'value': false});
      case 'checkbox':
        return UiNode(id: id, type: type, props: const {
          'value': false,
          'label': '选项',
        });
      case 'progress':
        return UiNode(id: id, type: type, props: const {'value': 0.5});
      case 'list_vertical':
        return UiNode(id: id, type: type, props: const {'items': ''});
      case 'list_horizontal':
        return UiNode(id: id, type: type, props: const {'items': ''});
      case 'tab_container':
        return UiNode(id: id, type: type, props: const {});
      case 'card':
        return UiNode(id: id, type: type, props: const {'elevation': 1});
      case 'conditional_container':
        // 选择式容器默认：condition 为空字符串（展示第一个 case 作为预览），
        // mode 为 single（精确匹配 case 名）。
        return UiNode(id: id, type: type, props: const {
          'condition': '',
          'mode': 'single',
        });
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
