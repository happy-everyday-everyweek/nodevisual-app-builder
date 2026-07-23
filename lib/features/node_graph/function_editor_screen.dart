import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/function_def.dart';
import '../../data/models/node.dart';
import 'connection_painter.dart';
import 'dag_validator.dart';
import 'graph_providers.dart';
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
    const kinds = <_NodeKindEntry>[
      _NodeKindEntry(kind: 'variable_set', label: 'Set Var', icon: Icons.label_outline),
      _NodeKindEntry(kind: 'variable_get', label: 'Get Var', icon: Icons.label_outline),
      _NodeKindEntry(kind: 'arithmetic', label: 'Arithmetic', icon: Icons.calculate_outlined),
      _NodeKindEntry(kind: 'logic', label: 'Logic', icon: Icons.account_tree_outlined),
      _NodeKindEntry(kind: 'string_op', label: 'String', icon: Icons.text_fields),
      _NodeKindEntry(kind: 'if', label: 'If', icon: Icons.call_split),
      _NodeKindEntry(kind: 'loop', label: 'Loop', icon: Icons.loop),
      _NodeKindEntry(kind: 'db_query', label: 'DB Query', icon: Icons.storage_outlined),
      _NodeKindEntry(kind: 'db_insert', label: 'DB Insert', icon: Icons.storage_outlined),
      _NodeKindEntry(kind: 'db_update', label: 'DB Update', icon: Icons.storage_outlined),
      _NodeKindEntry(kind: 'db_delete', label: 'DB Delete', icon: Icons.storage_outlined),
      _NodeKindEntry(kind: 'function_call', label: 'Call Func', icon: Icons.functions),
      _NodeKindEntry(kind: 'plugin', label: 'Plugin', icon: Icons.extension),
    ];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kinds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final entry = kinds[i];
          return _PaletteButton(
            entry: entry,
            color: theme.colorScheme.primary,
            onTap: () => _addNodeOfKind(entry.kind),
          );
        },
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
}

/// 节点面板条目。
class _NodeKindEntry {
  const _NodeKindEntry({
    required this.kind,
    required this.label,
    required this.icon,
  });

  final String kind;
  final String label;
  final IconData icon;
}

/// 面板按钮。
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.entry,
    required this.color,
    required this.onTap,
  });

  final _NodeKindEntry entry;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  entry.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
