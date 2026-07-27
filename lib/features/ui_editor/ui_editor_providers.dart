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

/// 当前编辑的布局模式（仅画布层 UI 状态，不持久化）。
///
/// Phase 6 引入：布局属性面板据此切换相对/绝对布局编辑视图；
/// null 表示未进入特定布局编辑（沿用节点自身 [LayoutConfig.mode]）。
final layoutEditModeProvider = StateProvider<LayoutMode?>((ref) => null);

/// 当前是否处于"移动模式"（仅画布层 UI 状态，不持久化）。
///
/// Phase 6 引入：长按节点进入移动模式后置为 true，画布据此高亮可放置区域并
/// 拦截常规点击；移动结束或取消时复位为 false。
final isMoveModeActiveProvider = StateProvider<bool>((ref) => false);

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

  // ---- 组件树查询（Phase 6）----

  /// 获取指定 Page 的直接子节点（该页面的 UI 根节点树）。
  ///
  /// Page 不存在或非 Page 节点时返回空列表。
  List<UiNode> getPageChildren(String pageId) {
    final p = _project;
    if (p == null) return const [];
    final page = _findPageNode(p, pageId);
    return page?.children ?? const [];
  }

  /// 获取指定节点的所有后代（递归，不含自身）。
  List<UiNode> getDescendants(String nodeId) {
    final res = findNode(nodeId);
    if (res == null) return const [];
    final result = <UiNode>[];
    void collect(UiNode n) {
      for (final child in n.children) {
        result.add(child);
        collect(child);
      }
    }
    collect(res.node);
    return result;
  }

  /// 获取指定节点的父节点；根节点（Page 顶层）返回 null。
  UiNode? getParent(String nodeId) => findNode(nodeId)?.parent;

  /// 获取节点所属的 Page 节点（特殊 UiNode，type=='page'）。
  ///
  /// - 节点本身是 Page：返回自身。
  /// - 节点是 Page 的直接/间接子节点：沿父链向上找到的 Page。
  /// - 节点不存在或无所属 Page：返回 null。
  UiNode? getNodePage(String nodeId) {
    final p = _project;
    if (p == null) return null;
    final res = findNode(nodeId);
    if (res == null) return null;
    if (res.node.isPage) return res.node;
    // 沿 [UiNode.pageId] 直接定位所属 Page（pageId 由 addComponent 继承设置）。
    final pageId = res.node.pageId;
    if (pageId != null) {
      final byPageId = _findPageNode(p, pageId);
      if (byPageId != null) return byPageId;
    }
    // 退化路径：pageId 缺失时沿父链向上查找 Page 祖先。
    UiNode? parent = res.parent;
    while (parent != null) {
      if (parent.isPage) return parent;
      final parentRes = findNode(parent.id);
      parent = parentRes?.parent;
    }
    return null;
  }

  // ---- 添加 ----

  /// 添加组件；parentId 为 null 时添加为 [pageId] 对应 Page 的直接子节点，
  /// 否则添加为 parentId 的子节点。
  ///
  /// Phase 6 强制 pageId 校验：
  /// - [pageId] 必传且必须对应一个存在的 Page 节点，否则抛出 [ArgumentError]。
  /// - 当 [parentId] 非空（添加到容器内）时，新组件的 pageId 自动继承父组件：
  ///   父为 Page 节点时取父 id，否则取父节点 [UiNode.pageId]。
  /// - 当 [parentId] 为空时，新组件作为 Page[pageId] 的直接子节点插入，
  ///   其 pageId 即为传入的 [pageId]。
  ///
  /// 返回新节点 id（项目未打开时返回空字符串）。
  String addComponent(String type,
      {String? parentId, required String pageId}) {
    final p = _project;
    if (p == null) return '';
    if (pageId.isEmpty) {
      throw ArgumentError.value(pageId, 'pageId', 'pageId 不能为空');
    }
    if (!_pageExists(p, pageId)) {
      throw ArgumentError.value(
          pageId, 'pageId', 'pageId 对应的 Page 不存在');
    }
    final String nodePageId;
    final UiNode node;
    if (parentId != null) {
      final parent = findNode(parentId);
      if (parent == null) {
        throw ArgumentError.value(parentId, 'parentId', 'parentId 不存在');
      }
      // 防御：不允许在 Page 下嵌套另一个 Page（Page 只能作为顶层根节点）。
      if (parent.node.isPage && type == kPageType) {
        throw StateError('不允许在 Page 下嵌套另一个 Page');
      }
      // 继承父组件的 pageId：父为 Page 节点时取父 id，否则取父节点 pageId。
      // 历史数据（父节点无 pageId）回退到传入的 [pageId]（已校验存在）。
      final inherited =
          parent.node.isPage ? parent.node.id : parent.node.pageId;
      nodePageId = (inherited != null && _pageExists(p, inherited))
          ? inherited
          : pageId;
      node = _createDefaultNode(type, pageId: nodePageId);
      final newUi = p.ui
          .map((r) => _insertChild(r, parentId, node))
          .toList(growable: false);
      _commit(p.copyWith(ui: newUi));
    } else {
      // 添加为 Page[pageId] 的直接子节点。
      nodePageId = pageId;
      node = _createDefaultNode(type, pageId: nodePageId);
      final newUi = p.ui
          .map((r) => (r.id == pageId && r.isPage)
              ? r.copyWith(children: [...r.children, node])
              : r)
          .toList(growable: false);
      _commit(p.copyWith(ui: newUi));
    }
    selectComponent(node.id);
    return node.id;
  }

  /// 判断指定 pageId 是否对应一个存在的 Page 节点。
  bool _pageExists(Project p, String pageId) {
    return p.ui.any((n) => n.isPage && n.id == pageId);
  }

  /// 查找指定 pageId 对应的 Page 节点；不存在时返回 null。
  UiNode? _findPageNode(Project p, String pageId) {
    for (final n in p.ui) {
      if (n.isPage && n.id == pageId) return n;
    }
    return null;
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
    // 防御：Page 节点不允许被移动（Page 只能作为 UI 树顶层根节点）。
    if (moving.isPage) {
      throw StateError('Page 节点不允许被移动');
    }
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

  // ---- 布局细粒度变更（Phase 6）----
  //
  // 以下方法在节点已有 [LayoutConfig] 基础上做局部修改；若节点尚无 layout，
  // 会以一份默认配置（relative + 100%×100% + 零间距）为起点再应用变更。
  // 全部走不可变更新模式（copyWith 链），通过 [_updateLayout] 复用提交逻辑。

  /// 默认布局配置（相对布局 + 100%×100% + 零外间距），作为新增布局的起点。
  static LayoutConfig get _defaultLayout => const LayoutConfig(
        mode: LayoutMode.relative,
        width: SizeSpec(value: 100, unit: SizeUnit.percent),
        height: SizeSpec(value: 100, unit: SizeUnit.percent),
      );

  /// 在节点 [id] 的 [LayoutConfig] 上应用 [transformer]；节点无 layout 时
  /// 以 [_defaultLayout] 为起点。
  void _updateLayout(
      String id, LayoutConfig Function(LayoutConfig cur) transformer) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id,
            (n) => n.copyWith(layout: transformer(n.layout ?? _defaultLayout)),))
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 切换节点布局模式（relative / absolute）。
  ///
  /// 切换到 absolute 时清除 cell/distance（相对布局专属字段）；
  /// 切换到 relative 时清除 x/y（绝对布局专属字段），保证配置自洽。
  void setLayoutMode(String id, LayoutMode mode) {
    _updateLayout(id, (cur) {
      var next = cur.copyWith(mode: mode);
      if (mode == LayoutMode.absolute) {
        next = next.copyWith(cell: null, distance: null);
      } else {
        next = next.copyWith(x: null, y: null);
      }
      return next;
    });
  }

  /// 设置 9 宫格归属（相对布局）；同时把模式强制为 relative 并清除 x/y。
  void setGridCell(String id, GridCell cell) {
    _updateLayout(id, (cur) => cur
        .copyWith(mode: LayoutMode.relative, cell: cell, x: null, y: null));
  }

  /// 设置距最近边的距离（相对布局）；保留当前 cell。
  void setDistance(String id, DistanceSpec distance) {
    _updateLayout(id, (cur) => cur.copyWith(distance: distance));
  }

  /// 设置绝对布局坐标（x / y）；同时把模式强制为 absolute 并清除 cell/distance。
  void setPosition(String id, PositionSpec x, PositionSpec y) {
    _updateLayout(id, (cur) => cur.copyWith(
          mode: LayoutMode.absolute,
          x: x,
          y: y,
          cell: null,
          distance: null,
        ));
  }

  /// 设置节点尺寸（宽 / 高）。
  void setSize(String id, SizeSpec width, SizeSpec height) {
    _updateLayout(id, (cur) => cur.copyWith(width: width, height: height));
  }

  /// 设置外间距（4 方向）。
  void setMargin(String id, MarginSpec margin) {
    _updateLayout(id, (cur) => cur.copyWith(margin: margin));
  }

  /// 调整节点在所在父容器 children 列表中的顺序（相对布局堆叠顺序调整）。
  ///
  /// [newIndex] 为目标位置（自动 clamp 到合法范围）；越界或父节点不存在时
  /// 静默忽略。根节点（无父）调用此方法无效。
  void reorderInCell(String id, int newIndex) {
    final p = _project;
    if (p == null) return;
    final found = findNode(id);
    if (found == null || found.parent == null) return;
    final parent = found.parent!;
    final siblings = parent.children;
    final oldIndex = siblings.indexWhere((c) => c.id == id);
    if (oldIndex < 0) return;
    final clamped = newIndex.clamp(0, siblings.length - 1).toInt();
    if (clamped == oldIndex) return;
    final reordered = List<UiNode>.from(siblings);
    final moved = reordered.removeAt(oldIndex);
    // removeAt 后列表长度减 1，插入位置需参照新长度 clamp。
    final insertAt = clamped.clamp(0, reordered.length).toInt();
    reordered.insert(insertAt, moved);
    final newUi = p.ui
        .map((r) => _updateNode(
            r, parent.id, (n) => n.copyWith(children: reordered)))
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 设置单个样式键值（写入 [UiNode.style]）。
  ///
  /// Phase 6 规范方法：[value] 为 null 时移除该样式键。
  /// 等价于旧版 [updateStyleProp]，二者可互换使用。
  void setStyleProp(String id, String key, Object? value) {
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

  /// 更新单个样式键值（[setStyleProp] 的旧名别名）。
  ///
  /// 供 Phase 4 v2 样式段编辑器使用，保留以兼容现有调用点。
  void updateStyleProp(String id, String key, Object? value) =>
      setStyleProp(id, key, value);

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

  // ---- 动画细粒度变更（Phase 6）----
  //
  // 以下方法在节点已有 [AnimationsConfig] 基础上做局部修改；若节点尚无
  // animations，以空配置（entrance/exit 为 null，triggered 为空）为起点。
  // 全部走不可变更新模式（copyWith 链）。

  /// 在节点 [id] 的 [AnimationsConfig] 上应用 [transformer]；节点无
  /// animations 时以空配置为起点。
  void _updateAnimations(
      String id, AnimationsConfig Function(AnimationsConfig cur) transformer) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui
        .map((r) => _updateNode(r, id,
            (n) => n.copyWith(animations: transformer(n.animations ?? const AnimationsConfig())),))
        .toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 设置入场动画；[animation] 为 null 时清除入场动画。
  void setEntranceAnimation(String id, AnimationSpec? animation) {
    _updateAnimations(id, (cur) => cur.copyWith(entrance: animation));
  }

  /// 设置出场动画；[animation] 为 null 时清除出场动画。
  void setExitAnimation(String id, AnimationSpec? animation) {
    _updateAnimations(id, (cur) => cur.copyWith(exit: animation));
  }

  /// 追加一条事件触发动画绑定。
  void addTriggeredAnimation(String id, TriggeredAnimation animation) {
    _updateAnimations(id, (cur) => cur.copyWith(triggered: [...cur.triggered, animation]));
  }

  /// 替换第 [index] 条事件触发动画；越界时静默忽略。
  void updateTriggeredAnimation(
      String id, int index, TriggeredAnimation animation) {
    _updateAnimations(id, (cur) {
      if (index < 0 || index >= cur.triggered.length) return cur;
      final newList = List<TriggeredAnimation>.from(cur.triggered);
      newList[index] = animation;
      return cur.copyWith(triggered: newList);
    });
  }

  /// 移除第 [index] 条事件触发动画；越界时静默忽略。
  void removeTriggeredAnimation(String id, int index) {
    _updateAnimations(id, (cur) {
      if (index < 0 || index >= cur.triggered.length) return cur;
      final newList = List<TriggeredAnimation>.from(cur.triggered)
        ..removeAt(index);
      return cur.copyWith(triggered: newList);
    });
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

  /// 新建页面；返回创建的 Page 节点 id（项目未打开时返回空字符串）。
  ///
  /// Page 节点是特殊 UiNode（type=='page'），其 children 为该页面的 UI
  /// 根节点树（初始为空）。
  ///
  /// 首页规则：项目内尚无任何 Page 时，自动设为首页（isHome=true），
  /// 忽略传入的 [isHome]（保证至少存在一个首页）；否则按 [isHome] 设置。
  ///
  /// [route] 为页面路由路径，可空。 [isHome] 是否设为首页（仅当非首个页面时生效）。
  String addPage(String name, {String? route, bool isHome = false}) {
    final p = _project;
    if (p == null) return '';
    final isFirstPage = p.ui.where((n) => n.isPage).isEmpty;
    final effectiveIsHome = isHome || isFirstPage;
    final pageNode = createPageNode(
      id: _uuid.v4(),
      name: name,
      route: route,
      isHome: effectiveIsHome,
    );
    var newUi = [...p.ui, pageNode];
    // isHome 唯一性：设为 home 时清除其他 Page 节点的 isHome。
    if (effectiveIsHome) {
      newUi = newUi.map((node) {
        if (!node.isPage || node.id == pageNode.id) return node;
        if (!node.isHomePage) return node;
        final newProps = Map<String, dynamic>.from(node.props);
        newProps.remove(PagePropsKeys.isHome);
        return node.copyWith(props: newProps);
      }).toList(growable: false);
    }
    _commit(p.copyWith(ui: newUi));
    return pageNode.id;
  }

  /// 重命名页面。
  void renamePage(String pageId, String newName) {
    updatePage(pageId, name: newName);
  }

  /// 将指定页面设为首页（同时清除其他页面的首页标记）。
  void setHomePage(String pageId) {
    updatePage(pageId, isHome: true);
  }

  /// 合并页面 props（[PagePropsKeys]）。
  ///
  /// 通用 props 合并器：不处理 isHome 唯一性；如需切换首页请用 [setHomePage]。
  void updatePageProps(String pageId, Map<String, dynamic> props) {
    final p = _project;
    if (p == null) return;
    final newUi = p.ui.map((node) {
      if (node.id != pageId || !node.isPage) return node;
      final newProps = Map<String, dynamic>.from(node.props);
      newProps.addAll(props);
      return node.copyWith(props: newProps);
    }).toList(growable: false);
    _commit(p.copyWith(ui: newUi));
  }

  /// 删除页面（Page 节点）；仅当项目存在 >1 个页面时允许。
  ///
  /// 删除最后一个页面会抛出 [StateError]，避免项目无页面可用。
  /// 同时清除关联的页面事件 entry。
  void deletePage(String pageId) {
    final p = _project;
    if (p == null) return;
    final pageCount = p.ui.where((n) => n.isPage).length;
    if (pageCount <= 1) {
      throw StateError('至少保留一个页面，不允许删除最后一个页面');
    }
    removePage(pageId);
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
  ///
  /// [pageId] 标记新节点所属页面；添加到容器内时由 [addComponent] 继承父组件
  /// 的 pageId 传入，添加为 Page 直接子节点时传入该 Page 的 id。
  UiNode _createDefaultNode(String type, {String? pageId}) {
    final id = _uuid.v4();
    switch (type) {
      case 'column':
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'mainAxisAlignment': 'start',
          'crossAxisAlignment': 'center',
        },);
      case 'row':
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'mainAxisAlignment': 'start',
          'crossAxisAlignment': 'center',
        },);
      case 'text':
        return UiNode(id: id, type: type, pageId: pageId,
            props: const {'content': '文本'},);
      case 'button':
        return UiNode(id: id, type: type, pageId: pageId,
            props: const {'label': '按钮'},);
      case 'text_field':
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'hint': '请输入',
          'label': '',
        },);
      case 'image':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'src': ''});
      case 'list_view':
        return UiNode(id: id, type: type, pageId: pageId, props: const {});
      case 'container':
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'color': '#FFFFFF',
          'padding': 8,
        },);
      case 'scaffold':
        return UiNode(id: id, type: type, pageId: pageId, props: const {});
      case 'rich_text':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'content': '富文本内容'});
      case 'icon':
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'name': 'star',
          'size': 24,
        });
      case 'badge':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'count': '0'});
      case 'divider':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'thickness': 1});
      case 'spacer':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'flex': 1});
      case 'video':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'src': ''});
      case 'slider':
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'value': 0.5,
          'min': 0,
          'max': 1,
        });
      case 'switch':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'value': false});
      case 'checkbox':
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'value': false,
          'label': '选项',
        });
      case 'progress':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'value': 0.5});
      case 'list_vertical':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'items': ''});
      case 'list_horizontal':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'items': ''});
      case 'tab_container':
        return UiNode(id: id, type: type, pageId: pageId, props: const {});
      case 'card':
        return UiNode(id: id, type: type, pageId: pageId, props: const {'elevation': 1});
      case 'conditional_container':
        // 选择式容器默认：condition 为空字符串（展示第一个 case 作为预览），
        // mode 为 single（精确匹配 case 名）。
        return UiNode(id: id, type: type, pageId: pageId, props: const {
          'condition': '',
          'mode': 'single',
        });
      default:
        return UiNode(id: id, type: type, pageId: pageId, props: const {});
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
