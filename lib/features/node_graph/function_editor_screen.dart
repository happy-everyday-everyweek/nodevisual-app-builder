import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/models/func_param.dart';
import '../../data/models/function_def.dart';
import '../../data/models/node.dart';
import '../../data/models/port.dart';
import '../marketplace/marketplace_providers.dart';
import 'connection_painter.dart';
import 'dag_validator.dart';
import 'graph_providers.dart';
import 'node_kinds.dart';
import 'node_layout.dart';
import 'node_widget.dart';

/// 函数节点图编辑器屏幕（Task 4 核心）。
///
/// 接收 [functionId]，从当前项目中加载对应 [FunctionDef] 并通过
/// [graphMutatorProvider] 进行节点 / 控制流边的所有变更。
///
/// 画布层（控制平面）：
/// - [InteractiveViewer] 提供双指缩放 + 双指平移；
/// - 内部 Stack 为虚拟画布坐标系，节点用 [Positioned] 摆放；
/// - [CustomPaint] + [ConnectionPainter] 绘制控制流连线与拖拽中的临时连线；
/// - 单指拖节点 body 移动节点；单指拖端口画线；长按节点选中；长按连线删除。
///
/// 数据平面（节点编辑页）由 Task 5/7 实现，本屏幕不展开。
class FunctionEditorScreen extends ConsumerStatefulWidget {
  const FunctionEditorScreen({
    super.key,
    required this.projectId,
    required this.functionId,
  });

  final String projectId;
  final String functionId;

  @override
  ConsumerState<FunctionEditorScreen> createState() =>
      _FunctionEditorScreenState();
}

class _FunctionEditorScreenState extends ConsumerState<FunctionEditorScreen> {
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  // 连线拖拽中的临时状态（仅本地 UI）。
  String? _dragFromNode;
  String? _dragFromPort;
  Offset? _dragFromCanvasPos;
  Offset? _dragCurrentCanvasPos;

  // 当前选中的连线键（"fromNode:fromPort:toNode"），用于高亮 + 删除。
  String? _selectedEdgeKey;

  bool _paletteExpanded = false;

  /// 调色板中已折叠的节点分类（默认全展开，点击分组标题可折叠）。
  final Set<NodeCategory> _collapsedCategories = <NodeCategory>{};

  @override
  void initState() {
    super.initState();
    // 进入时设置当前编辑函数 id，GraphMutator 据此镜像函数。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(editedFunctionIdProvider.notifier).state = widget.functionId;
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// 将屏幕全局坐标转为画布坐标。
  Offset? _globalToCanvas(Offset globalPosition) {
    final renderObj = _viewerKey.currentContext?.findRenderObject();
    if (renderObj is! RenderBox || !renderObj.hasSize) return null;
    final local = renderObj.globalToLocal(globalPosition);
    return _transformController.toScene(local);
  }

  /// 计算所有节点的端口画布坐标映射。
  ///
  /// 键：[portKey] 结果（输出端口）或 `nodeId:in`（入口端口）。
  Map<String, Offset> _computePortPositions(List<Node> nodes) {
    final result = <String, Offset>{};
    for (final node in nodes) {
      final origin = node.position;
      final inOffset = NodeLayout.inputPortOffset();
      result['${node.id}:$inputPortSuffix'] =
          Offset(origin.x + inOffset.dx, origin.y + inOffset.dy);
      for (var i = 0; i < node.controlOutputs.length; i++) {
        final off = NodeLayout.outputPortOffset(i);
        result[portKey(node.id, node.controlOutputs[i].name)] =
            Offset(origin.x + off.dx, origin.y + off.dy);
      }
    }
    return result;
  }

  /// 计算画布尺寸（覆盖所有节点 + 留白，且至少为视口 ×2）。
  Size _computeCanvasSize(List<Node> nodes, Size viewportSize) {
    var maxX = viewportSize.width * 2;
    var maxY = viewportSize.height * 2;
    for (final node in nodes) {
      final w = node.position.x + NodeLayout.width;
      final h = node.position.y +
          NodeLayout.nodeHeight(
            controlOutputCount: node.controlOutputs.length,
            dataOutputCount: node.dataOutputs.length,
          );
      if (w > maxX) maxX = w;
      if (h > maxY) maxY = h;
    }
    return Size(maxX + 200, maxY + 200);
  }

  // ---- 节点交互 ----

  void _onNodeLongPress(String nodeId) {
    ref.read(selectedNodeIdProvider.notifier).state = nodeId;
    // 同时清除连线选中。
    if (_selectedEdgeKey != null) {
      setState(() => _selectedEdgeKey = null);
    }
  }

  void _onNodeDragUpdate(String nodeId, DragUpdateDetails details) {
    final fn = ref.read(graphMutatorProvider);
    if (fn == null) return;
    Node? node;
    for (final n in fn.nodes) {
      if (n.id == nodeId) {
        node = n;
        break;
      }
    }
    if (node == null) return;

    // details.delta 是视口坐标增量，需除以当前缩放转为画布增量。
    final scale = _transformController.value.getMaxScaleOnAxis();
    if (scale == 0) return;
    final dx = details.delta.dx / scale;
    final dy = details.delta.dy / scale;
    final newPos = NodePosition(
      x: node.position.x + dx,
      y: node.position.y + dy,
    );
    ref.read(graphMutatorProvider.notifier).moveNode(nodeId, newPos);
  }

  void _onNodeDelete(String nodeId) {
    ref.read(graphMutatorProvider.notifier).removeNode(nodeId);
  }

  /// 单击节点 → 打开节点编辑页（数据平面入口）。
  void _openNodeEditor(String nodeId) {
    context.push(
      AppConstants.nodeEditorRoute(widget.projectId, widget.functionId, nodeId),
    );
  }

  // ---- 连线交互 ----

  void _onConnectionDragStart(String portName) {
    final selectedId = ref.read(selectedNodeIdProvider);
    if (selectedId == null) return;
    final fn = ref.read(graphMutatorProvider);
    if (fn == null) return;
    Node? nodeFound;
    for (final n in fn.nodes) {
      if (n.id == selectedId) {
        nodeFound = n;
        break;
      }
    }
    final node = nodeFound;
    if (node == null) return;
    final portIndex = node.controlOutputs.indexWhere((p) => p.name == portName);
    if (portIndex < 0) return;
    final off = NodeLayout.outputPortOffset(portIndex);
    final origin = node.position;
    final fromPos = Offset(origin.x + off.dx, origin.y + off.dy);
    setState(() {
      _dragFromNode = selectedId;
      _dragFromPort = portName;
      _dragFromCanvasPos = fromPos;
      _dragCurrentCanvasPos = fromPos;
    });
  }

  void _onConnectionDragUpdate(Offset globalPosition) {
    final canvasPos = _globalToCanvas(globalPosition);
    if (canvasPos == null) return;
    setState(() => _dragCurrentCanvasPos = canvasPos);
  }

  void _onConnectionDragEnd(Offset? globalPosition) {
    final dragFromNode = _dragFromNode;
    final dragFromPort = _dragFromPort;
    final dragFromPos = _dragFromCanvasPos;
    final endCanvasPos =
        globalPosition == null ? _dragCurrentCanvasPos : _globalToCanvas(globalPosition);

    // 清理拖拽状态。
    setState(() {
      _dragFromNode = null;
      _dragFromPort = null;
      _dragFromCanvasPos = null;
      _dragCurrentCanvasPos = null;
    });

    if (dragFromNode == null ||
        dragFromPort == null ||
        dragFromPos == null ||
        endCanvasPos == null) {
      return;
    }

    // 在所有节点入口端口中找最近的命中。
    final fn = ref.read(graphMutatorProvider);
    if (fn == null) return;
    String? bestTarget;
    double bestDist = double.infinity;
    for (final node in fn.nodes) {
      if (node.id == dragFromNode) continue; // 不能连自己
      final inOff = NodeLayout.inputPortOffset();
      final pos =
          Offset(node.position.x + inOff.dx, node.position.y + inOff.dy);
      final d = (pos - endCanvasPos).distance;
      if (d < bestDist) {
        bestDist = d;
        bestTarget = node.id;
      }
    }

    if (bestTarget == null ||
        bestDist > NodeLayout.portHitThreshold) {
      return; // 未命中任何端口
    }

    final result = ref.read(graphMutatorProvider.notifier).addEdge(
          fromNode: dragFromNode,
          fromPort: dragFromPort,
          toNode: bestTarget,
        );
    if (!mounted) return;
    switch (result) {
      case AddEdgeResult.cycle:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连线会形成环，已拒绝'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case AddEdgeResult.invalid:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('端口或节点不存在，已忽略'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case AddEdgeResult.success:
        // 静默成功（v1 无须提示）。
        break;
    }
  }

  void _onConnectionDragCancel() {
    setState(() {
      _dragFromNode = null;
      _dragFromPort = null;
      _dragFromCanvasPos = null;
      _dragCurrentCanvasPos = null;
    });
  }

  // ---- 连线选中 / 删除 ----

  void _onCanvasLongPressStart(LongPressStartDetails details) {
    final canvasPos = _globalToCanvas(details.globalPosition);
    if (canvasPos == null) return;
    final fn = ref.read(graphMutatorProvider);
    if (fn == null) return;
    final portPositions = _computePortPositions(fn.nodes);
    // 找最近命中的边。
    for (final edge in fn.controlEdges) {
      final from = portPositions[portKey(edge.fromNode, edge.fromPort)];
      final to = portPositions['${edge.toNode}:$inputPortSuffix'];
      if (from == null || to == null) continue;
      if (isPointNearEdge(canvasPos, from, to)) {
        // 长按连线直接删除（带 SnackBar 提示）。
        ref.read(graphMutatorProvider.notifier).removeEdge(
              fromNode: edge.fromNode,
              fromPort: edge.fromPort,
              toNode: edge.toNode,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已删除连线'),
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }
    }
  }

  void _onCanvasTapUp(TapUpDetails details) {
    final canvasPos = _globalToCanvas(details.globalPosition);
    if (canvasPos == null) return;
    final fn = ref.read(graphMutatorProvider);
    if (fn == null) return;
    final portPositions = _computePortPositions(fn.nodes);
    // 点击命中连线 → 选中（再次点击同一边或空白 → 取消）。
    String? hitKey;
    for (final edge in fn.controlEdges) {
      final from = portPositions[portKey(edge.fromNode, edge.fromPort)];
      final to = portPositions['${edge.toNode}:$inputPortSuffix'];
      if (from == null || to == null) continue;
      if (isPointNearEdge(canvasPos, from, to)) {
        hitKey = '${edge.fromNode}:${edge.fromPort}:${edge.toNode}';
        break;
      }
    }
    setState(() {
      _selectedEdgeKey = (hitKey == _selectedEdgeKey) ? null : hitKey;
    });
  }

  void _onCanvasBackgroundTap() {
    // 点击空白 → 清除所有选中。
    if (ref.read(selectedNodeIdProvider) != null) {
      ref.read(selectedNodeIdProvider.notifier).state = null;
    }
    if (_selectedEdgeKey != null) {
      setState(() => _selectedEdgeKey = null);
    }
  }

  // ---- 节点添加 ----

  void _addNodeOfKind(String kind) {
    final renderObj = _viewerKey.currentContext?.findRenderObject();
    if (renderObj is! RenderBox || !renderObj.hasSize) return;
    final viewportSize = renderObj.size;
    // 把视口中心映射到画布坐标，作为新节点中心。
    final viewportCenter = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    final canvasCenter = _transformController.toScene(viewportCenter);
    // 新增节点时给一个微抖动避免完全重叠。
    final existing = ref.read(graphMutatorProvider)?.nodes.length ?? 0;
    final jitter = (existing % 5) * 24.0;
    final position = NodePosition(
      x: canvasCenter.dx - NodeLayout.width / 2 + jitter,
      y: canvasCenter.dy - NodeLayout.headerHeight / 2 + jitter,
    );
    final id = ref
        .read(graphMutatorProvider.notifier)
        .addNode(kind, position: position);
    if (id.isNotEmpty) {
      ref.read(selectedNodeIdProvider.notifier).state = id;
    }
  }

  // ---- 构建 UI ----

  @override
  Widget build(BuildContext context) {
    final fn = ref.watch(graphMutatorProvider);
    final selectedNodeId = ref.watch(selectedNodeIdProvider);
    final theme = Theme.of(context);

    if (fn == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('函数编辑器'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.go('/project/${widget.projectId}'),
          ),
        ),
        body: const Center(
          child: Text('函数不存在或未加载'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () =>
              context.go('/project/${widget.projectId}'),
        ),
        title: Text(fn.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_outlined),
            tooltip: '函数签名',
            onPressed: () => _showSignatureSheet(fn),
          ),
          if (selectedNodeId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除选中节点',
              onPressed: () => _onNodeDelete(selectedNodeId),
            ),
          IconButton(
            icon: const Icon(Icons.warning_amber_outlined),
            tooltip: '校验图',
            onPressed: () => _showValidation(fn),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize =
                Size(constraints.maxWidth, constraints.maxHeight);
            final canvasSize = _computeCanvasSize(fn.nodes, viewportSize);
            final portPositions = _computePortPositions(fn.nodes);
            return Stack(
              children: [
                Positioned.fill(
                  child: _buildCanvas(
                    fn,
                    canvasSize,
                    portPositions,
                    selectedNodeId,
                    theme,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildPalette(theme),
                ),
                if (_dragFromCanvasPos != null &&
                    _dragCurrentCanvasPos != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _buildDragHint(theme),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCanvas(
    FunctionDef fn,
    Size canvasSize,
    Map<String, Offset> portPositions,
    String? selectedNodeId,
    ThemeData theme,
  ) {
    return InteractiveViewer(
      key: _viewerKey,
      transformationController: _transformController,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.3,
      maxScale: 2.5,
      clipBehavior: Clip.none,
      child: SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 背景：点击空白取消选中 + 长按 / 点击连线命中检测。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onCanvasBackgroundTap,
                onTapUp: _onCanvasTapUp,
                onLongPressStart: _onCanvasLongPressStart,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerLowest,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // 控制流连线层。
            Positioned.fill(
              child: CustomPaint(
                painter: ConnectionPainter(
                  edges: fn.controlEdges,
                  portPositions: portPositions,
                  color: theme.colorScheme.primary,
                  selectedEdgeKey: _selectedEdgeKey,
                  selectedColor: theme.colorScheme.error,
                  dragFrom: _dragFromCanvasPos,
                  dragTo: _dragCurrentCanvasPos,
                  dragColor: theme.colorScheme.tertiary,
                ),
              ),
            ),
            // 节点层。
            for (final node in fn.nodes)
              Positioned(
                left: node.position.x,
                top: node.position.y,
                child: NodeCard(
                  node: node,
                  selected: node.id == selectedNodeId,
                  onSelect: () => _onNodeLongPress(node.id),
                  onOpenEditor: () => _openNodeEditor(node.id),
                  onDelete: () => _onNodeDelete(node.id),
                  onDragUpdate: (details) =>
                      _onNodeDragUpdate(node.id, details),
                  onConnectionDragStart: _onConnectionDragStart,
                  onConnectionDragUpdate: _onConnectionDragUpdate,
                  onConnectionDragEnd: _onConnectionDragEnd,
                  onConnectionDragCancel: _onConnectionDragCancel,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPalette(ThemeData theme) {
    return Material(
      elevation: 6,
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.97),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _paletteExpanded = !_paletteExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 18, color: theme.colorScheme.primary,),
                  const SizedBox(width: 8),
                  Text('添加节点',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600,),),
                  const Spacer(),
                  Icon(
                    _paletteExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _paletteExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 0, width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
              child: _buildPaletteGrid(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteGrid(ThemeData theme) {
    // 收集所有节点种类：注册表内置规格 + 市场插件（plugin_<id>）。
    final installedSpecs = ref.watch(installedPluginSpecsProvider);
    final entries = <_NodeKindEntry>[
      for (final spec in NodeKindRegistry.allKinds())
        _NodeKindEntry(
          kind: spec.kind,
          label: spec.displayName,
          icon: _iconForKind(spec.kind, spec.category),
          category: spec.category,
        ),
    ];
    // 追加市场插件（去重：避免与内置 plugin_openai/anthropic 等 kind 冲突）。
    for (final s in installedSpecs) {
      final kind = 'plugin_${s.id}';
      if (entries.any((e) => e.kind == kind)) continue;
      entries.add(_NodeKindEntry(
        kind: kind,
        label: s.displayName,
        icon: Icons.extension,
        category: NodeCategory.plugin,
      ));
    }

    // 按 NodeCategory 声明序分组，确保调色板分组顺序稳定。
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        children: [
          for (final cat in NodeCategory.values)
            if (entries.any((e) => e.category == cat))
              _PaletteCategoryGroup(
                category: cat,
                entries: entries
                    .where((e) => e.category == cat)
                    .toList(growable: false),
                collapsed: _collapsedCategories.contains(cat),
                onToggle: () => setState(() {
                  if (_collapsedCategories.contains(cat)) {
                    _collapsedCategories.remove(cat);
                  } else {
                    _collapsedCategories.add(cat);
                  }
                }),
                onTapEntry: _addNodeOfKind,
              ),
        ],
      ),
    );
  }

  Widget _buildDragHint(ThemeData theme) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timeline,
                    size: 14, color: theme.colorScheme.onTertiaryContainer,),
                const SizedBox(width: 4),
                Text(
                  '拖到目标节点的入口端口释放',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showValidation(FunctionDef fn) {
    final errors = DagValidator.validateGraph(fn);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      errors.isEmpty ? Icons.check_circle : Icons.error_outline,
                      color: errors.isEmpty
                          ? Colors.green
                          : Theme.of(ctx).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      errors.isEmpty ? '图校验通过' : '图校验发现 ${errors.length} 个问题',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (errors.isEmpty)
                  const Text('当前控制流图无环、无孤立节点、无悬挂引用。')
                else
                  ...errors.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(e)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 函数签名编辑面板（T26）：CRUD 入参 / 出参。
  ///
  /// 展示当前函数的 inputs / outputs 签名，每项可编辑名称、类型、默认值（仅
  /// inputs）、描述，可增删。修改后通过 [GraphMutator._commit] 写回项目，
  /// 触发依赖此函数签名的 `function_call` 节点在下次编辑时同步端口。
  void _showSignatureSheet(FunctionDef fn) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SignatureSheet(initial: fn),
    );
  }
}

/// 函数签名编辑面板。
///
/// 内部维护 inputs / outputs 的本地副本，确认后一次性提交到项目，避免逐次
/// 修改触发频繁落盘。提交时：
/// - 调用 [FunctionDef.copyWith] 替换 inputs / outputs；
/// - 通过 [GraphMutator._commit] → [ProjectMutator.replaceFunction] 写回项目；
/// - 关联的 `function_call` 节点 outputs 会在下次进入节点编辑页时按
///   [NodeKindSpec.projectOutputs] 重新派生（参见 [NodeEditorScreen]）。
class _SignatureSheet extends ConsumerStatefulWidget {
  const _SignatureSheet({required this.initial});

  final FunctionDef initial;

  @override
  ConsumerState<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends ConsumerState<_SignatureSheet> {
  late List<FuncParam> _inputs;
  late List<FuncParam> _outputs;

  @override
  void initState() {
    super.initState();
    _inputs = List<FuncParam>.from(widget.initial.inputs);
    _outputs = List<FuncParam>.from(widget.initial.outputs);
  }

  void _commit() {
    final fn = widget.initial.copyWith(inputs: _inputs, outputs: _outputs);
    ref.read(graphMutatorProvider.notifier).replaceFunction(fn);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ListView(
            controller: controller,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('函数签名 — ${widget.initial.name}',
                      style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '声明函数的入参 / 出参。function_call 节点按此动态生成参数与返回值端口。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              _SectionTitle(text: '入参（${_inputs.length}）'),
              const SizedBox(height: 6),
              for (var i = 0; i < _inputs.length; i++)
                _ParamEditRow(
                  param: _inputs[i],
                  isOutput: false,
                  onChanged: (p) => setState(() => _inputs[i] = p),
                  onRemove: () => setState(() => _inputs.removeAt(i)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _inputs.add(FuncParam(
                      name: 'arg${_inputs.length + 1}',
                      type: PortType.any,
                    ));
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加入参'),
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle(text: '出参（${_outputs.length}）'),
              const SizedBox(height: 6),
              if (_outputs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '无显式出参：函数沿用 return 节点的 value 单返回语义。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              for (var i = 0; i < _outputs.length; i++)
                _ParamEditRow(
                  param: _outputs[i],
                  isOutput: true,
                  onChanged: (p) => setState(() => _outputs[i] = p),
                  onRemove: () => setState(() => _outputs.removeAt(i)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _outputs.add(FuncParam(
                      name: 'out${_outputs.length + 1}',
                      type: PortType.any,
                    ));
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加出参'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      _commit();
                      Navigator.pop(ctx);
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个 FuncParam 编辑行（名称 / 类型 / 默认值 / 描述 / 删除）。
class _ParamEditRow extends StatelessWidget {
  const _ParamEditRow({
    required this.param,
    required this.isOutput,
    required this.onChanged,
    required this.onRemove,
  });

  final FuncParam param;
  final bool isOutput;
  final ValueChanged<FuncParam> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: TextEditingController(text: param.name),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '参数名',
                  ),
                  onChanged: (v) => onChanged(param.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<PortType>(
                  value: param.type,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '类型',
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: PortType.any, child: Text('any')),
                    DropdownMenuItem(
                        value: PortType.string, child: Text('string')),
                    DropdownMenuItem(
                        value: PortType.number, child: Text('number')),
                    DropdownMenuItem(
                        value: PortType.boolean, child: Text('boolean')),
                    DropdownMenuItem(
                        value: PortType.list, child: Text('list')),
                    DropdownMenuItem(
                        value: PortType.map, child: Text('map')),
                  ],
                  onChanged: (v) {
                    if (v != null) onChanged(param.copyWith(type: v));
                  },
                ),
              ),
              IconButton(
                tooltip: '删除',
                icon: Icon(Icons.remove_circle_outline,
                    size: 20, color: theme.colorScheme.error),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!isOutput)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextField(
                controller:
                    TextEditingController(text: _defaultText(param.defaultValue)),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '默认值（字面值；可空）',
                ),
                onChanged: (v) {
                  // 简单字符串化默认值；number 解析为 num，bool 为 true/false，否则字符串。
                  final parsed = _parseDefault(v);
                  onChanged(param.copyWith(defaultValue: parsed));
                },
              ),
            ),
          TextField(
            controller: TextEditingController(text: param.description ?? ''),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '描述（可选）',
            ),
            onChanged: (v) => onChanged(param.copyWith(description: v)),
          ),
        ],
      ),
    );
  }

  static String _defaultText(Object? v) {
    if (v == null) return '';
    return v.toString();
  }

  /// 简单解析默认值字面值字符串。
  ///
  /// - 空字符串 → null
  /// - "true"/"false" → bool
  /// - 数字 → num (int/double)
  /// - 其他 → 字符串原值
  static Object? _parseDefault(String v) {
    if (v.isEmpty) return null;
    if (v == 'true') return true;
    if (v == 'false') return false;
    final num? parsed = num.tryParse(v);
    if (parsed != null) return parsed;
    return v;
  }
}

/// 签名面板小标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// 节点面板条目。
class _NodeKindEntry {
  const _NodeKindEntry({
    required this.kind,
    required this.label,
    required this.icon,
    required this.category,
  });

  final String kind;
  final String label;
  final IconData icon;
  final NodeCategory category;
}

/// 节点分类分组标签。
String _categoryLabel(NodeCategory c) {
  switch (c) {
    case NodeCategory.variable:
      return '变量';
    case NodeCategory.operation:
      return '运算';
    case NodeCategory.logic:
      return '逻辑';
    case NodeCategory.flow:
      return '流程';
    case NodeCategory.function:
      return '函数';
    case NodeCategory.database:
      return '数据库';
    case NodeCategory.uiControl:
      return 'UI 控制';
    case NodeCategory.plugin:
      return '插件';
  }
}

/// 分类分组标题左侧的图标。
IconData _categoryIcon(NodeCategory c) {
  switch (c) {
    case NodeCategory.variable:
      return Icons.label_outline;
    case NodeCategory.operation:
      return Icons.calculate_outlined;
    case NodeCategory.logic:
      return Icons.account_tree_outlined;
    case NodeCategory.flow:
      return Icons.call_split;
    case NodeCategory.function:
      return Icons.functions;
    case NodeCategory.database:
      return Icons.storage_outlined;
    case NodeCategory.uiControl:
      return Icons.touch_app_outlined;
    case NodeCategory.plugin:
      return Icons.extension;
  }
}

/// 按 kind 推断调色板按钮图标（与节点类别语义对齐）。
IconData _iconForKind(String kind, NodeCategory category) {
  // 细分按 kind 名匹配更直观的图标。
  switch (kind) {
    case 'variable_set':
      return Icons.label_outline;
    case 'arithmetic':
      return Icons.calculate_outlined;
    case 'math_func':
      return Icons.functions;
    case 'string_op':
      return Icons.text_fields;
    case 'list_op':
      return Icons.list_alt;
    case 'date_op':
      return Icons.event_outlined;
    case 'logic':
      return Icons.account_tree_outlined;
    case 'compare':
      return Icons.compare_arrows;
    case 'type_check':
      return Icons.fact_check_outlined;
    case 'ternary':
      return Icons.alt_route;
    case 'if':
      return Icons.call_split;
    case 'loop':
      return Icons.loop;
    case 'return':
      return Icons.subdirectory_arrow_right;
    case 'function_call':
      return Icons.functions;
    case 'db_query_one':
    case 'db_query_rows':
      return Icons.search;
    case 'db_aggregate':
      return Icons.functions;
    case 'db_insert':
    case 'db_insert_rows':
      return Icons.add_circle_outline;
    case 'db_update':
      return Icons.edit;
    case 'db_delete':
      return Icons.delete_outline;
    case 'db_create_table':
      return Icons.table_chart_outlined;
    case 'db_alter_table':
      return Icons.table_rows_outlined;
    case 'ui_set_text':
      return Icons.text_fields;
    case 'ui_set_visible':
      return Icons.visibility_outlined;
    case 'ui_set_enabled':
      return Icons.toggle_on_outlined;
    case 'ui_set_prop':
      return Icons.tune;
    case 'ui_navigate':
      return Icons.navigation_outlined;
    case 'ui_show_toast':
      return Icons.notifications_outlined;
    case 'plugin_openai':
      return Icons.psychology_outlined;
    case 'plugin_anthropic':
      return Icons.auto_awesome_outlined;
  }
  // 兜底：plugin_<id> 等市场插件用扩展图标，其余用分类图标。
  if (kind.startsWith('plugin_')) return Icons.extension;
  return _categoryIcon(category);
}

/// 可折叠的节点分类分组。
///
/// 标题行展示分类图标 + 名称 + 节点数 + 折叠箭头；展开时下方横向滚动节点按钮。
class _PaletteCategoryGroup extends StatelessWidget {
  const _PaletteCategoryGroup({
    required this.category,
    required this.entries,
    required this.collapsed,
    required this.onToggle,
    required this.onTapEntry,
  });

  final NodeCategory category;
  final List<_NodeKindEntry> entries;
  final bool collapsed;
  final VoidCallback onToggle;

  /// 点击某节点按钮回调（参数：kind）。
  final ValueChanged<String> onTapEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(_categoryIcon(category),
                      size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    _categoryLabel(category),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entries.length}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.outline),
                  ),
                  const Spacer(),
                  Icon(
                    collapsed
                        ? Icons.keyboard_arrow_right
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: collapsed
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: const SizedBox(height: 0, width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return _PaletteButton(
                      entry: e,
                      isPlugin: e.category == NodeCategory.plugin,
                      onTap: () => onTapEntry(e.kind),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 面板按钮。
///
/// 极简风：插件与基础节点统一灰阶，仅通过描边样式区分（插件节点用虚线感
/// 的浅描边+斜角图标）。点击有缩放反馈（原路反向恢复）。
class _PaletteButton extends StatefulWidget {
  const _PaletteButton({
    required this.entry,
    required this.isPlugin,
    required this.onTap,
  });

  final _NodeKindEntry entry;
  final bool isPlugin;
  final VoidCallback onTap;

  @override
  State<_PaletteButton> createState() => _PaletteButtonState();
}

class _PaletteButtonState extends State<_PaletteButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isPlugin ? cs.outline : cs.outlineVariant,
              width: widget.isPlugin ? 1 : 0.75,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.entry.icon,
                size: 22,
                color: widget.isPlugin ? cs.onSurface : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                widget.entry.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  fontWeight: widget.isPlugin ? FontWeight.w600 : FontWeight.w500,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
