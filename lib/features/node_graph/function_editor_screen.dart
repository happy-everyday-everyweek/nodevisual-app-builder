import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../data/models/entry.dart';
import '../../data/models/function_def.dart';
import '../../data/models/node.dart';
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
/// - [CustomPaint] + [ConnectionPainter] 绘制控制流连线；
/// - 指针模式：单击打开节点编辑页 / 长按选中 / 拖拽移动节点；
/// - 连线模式：两步点击式（先点击起始节点，再点击终止节点建立连线），
///   多输出节点弹出端口选择菜单。长按连线删除。
///
/// **核心语义**：连线仅代表执行顺序，与参数传递无关。参数通过节点
/// [Node.params] 中的 `#` 引用（[VariableRef]）独立完成，与控制流边解耦。
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

  // 连线模式下的"已选中起始节点 + 端口"状态（仅本地 UI）。
  //
  // 连线交互采用两步点击式：
  // 1. 第一次点击节点 → 设为起始（多输出节点弹出端口选择菜单）；
  // 2. 第二次点击另一节点 → 建立控制流连线（仅代表执行顺序）。
  // 点击空白或同一节点 → 取消起始选择。
  String? _connectSourceNode;
  String? _connectSourcePort;

  // 当前选中的连线键（"fromNode:fromPort:toNode"），用于高亮 + 删除。
  String? _selectedEdgeKey;

  /// 当前编辑器交互模式（指针 / 连线 / 添加）。
  NodeEditorMode _mode = NodeEditorMode.pointer;

  /// 添加模式下是否展开节点面板。
  bool _paletteExpanded = false;

  /// 调色板中已折叠的节点分类（默认全展开，点击分组标题可折叠）。
  final Set<NodeDisplayGroup> _collapsedGroups = <NodeDisplayGroup>{};

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
    // 退出编辑器时自增函数版本号（每次编辑会话 +1）。
    // ref 在 super.dispose() 前仍可用。
    ref.read(graphMutatorProvider.notifier).bumpVersion();
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

    // 节点拖到屏幕边缘时画布自动跟随（指针模式）。
    _autoFollowNode(nodeId, newPos, scale);
  }

  /// 节点拖到视口边缘时，平移画布以保持节点可见。
  ///
  /// 通过将节点画布坐标转为视口坐标，判断是否触及边缘阈值，
  /// 触及时反向平移 `_transformController`，使节点停留在视口内。
  void _autoFollowNode(String nodeId, NodePosition nodePos, double scale) {
    final renderObj = _viewerKey.currentContext?.findRenderObject();
    if (renderObj is! RenderBox || !renderObj.hasSize) return;
    final viewportSize = renderObj.size;

    // 节点中心画布坐标。
    final nodeCanvasCenter = Offset(
      nodePos.x + NodeLayout.width / 2,
      nodePos.y + NodeLayout.headerHeight / 2,
    );
    // 应用当前变换矩阵 → 视口坐标。
    final viewportPos =
        _transformController.value * nodeCanvasCenter;

    const edgeThreshold = 48.0; // 距视口边缘多少像素开始跟随
    const followSpeed = 0.8; // 跟随速度（避免抖动）

    var shiftX = 0.0;
    var shiftY = 0.0;
    if (viewportPos.dx < edgeThreshold) {
      shiftX = (viewportPos.dx - edgeThreshold) * followSpeed;
    } else if (viewportPos.dx > viewportSize.width - edgeThreshold) {
      shiftX =
          (viewportPos.dx - (viewportSize.width - edgeThreshold)) * followSpeed;
    }
    if (viewportPos.dy < edgeThreshold) {
      shiftY = (viewportPos.dy - edgeThreshold) * followSpeed;
    } else if (viewportPos.dy > viewportSize.height - edgeThreshold) {
      shiftY = (viewportPos.dy - (viewportSize.height - edgeThreshold)) *
          followSpeed;
    }
    if (shiftX == 0 && shiftY == 0) return;

    // 平移画布：直接修改变换矩阵的平移分量（视口坐标增量）。
    final matrix = Matrix4.copy(_transformController.value);
    matrix[12] -= shiftX;
    matrix[13] -= shiftY;
    _transformController.value = matrix;
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

  /// 连线模式：节点点击回调（两步点击式连线）。
  ///
  /// 流程：
  /// 1. 无起始节点时：本次点击的节点作为起始。若该节点有多个控制流输出端口，
  ///    弹出端口选择菜单；否则直接用第一个（唯一）端口。
  /// 2. 已有起始节点时：本次点击的节点作为终止，建立控制流连线。
  ///    - 同一节点再次点击 → 取消起始选择（避免自环）；
  ///    - 不同节点 → 调用 [GraphMutator.addEdge] 建立连线；
  ///    - 成功后保留起始节点与端口，便于连续建立多条连线（v1 改为清除，
  ///      避免视觉混乱）。
  ///
  /// 连线仅代表执行顺序，与参数传递无关。
  void _onNodeConnectTap(String nodeId) {
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

    // 已有起始节点：本次点击作为终止。
    final sourceNode = _connectSourceNode;
    final sourcePort = _connectSourcePort;
    if (sourceNode != null && sourcePort != null) {
      if (nodeId == sourceNode) {
        // 同一节点 → 取消起始选择。
        setState(() {
          _connectSourceNode = null;
          _connectSourcePort = null;
        });
        return;
      }
      final result = ref.read(graphMutatorProvider.notifier).addEdge(
            fromNode: sourceNode,
            fromPort: sourcePort,
            toNode: nodeId,
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
      // 建立后清除起始选择（v1：避免视觉混乱，每次只建一根连线）。
      setState(() {
        _connectSourceNode = null;
        _connectSourcePort = null;
      });
      return;
    }

    // 无起始节点：本次点击作为起始。
    if (node.controlOutputs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该节点无控制流输出端口，无法作为连线起点'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (node.controlOutputs.length == 1) {
      // 单输出节点：直接选中。
      setState(() {
        _connectSourceNode = nodeId;
        _connectSourcePort = node.controlOutputs.first.name;
      });
      return;
    }
    // 多输出节点：弹出端口选择菜单。
    _showPortSelectionMenu(node);
  }

  /// 多输出节点的控制流输出端口选择菜单（连线模式起始端口选择）。
  void _showPortSelectionMenu(Node node) {
    final ports = node.controlOutputs
        .map((p) => p.name)
        .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8,),
                  child: Text(
                    '选择起始端口 — ${node.params['name']?.toString() ?? node.kind}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
                for (final port in ports)
                  ListTile(
                    leading: Icon(Icons.arrow_outward,
                        size: 20, color: theme.colorScheme.tertiary,),
                    title: Text(port),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _connectSourceNode = node.id;
                        _connectSourcePort = port;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
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
    // 连线模式下点击空白 → 取消已选中的起始节点。
    if (_connectSourceNode != null) {
      setState(() {
        _connectSourceNode = null;
        _connectSourcePort = null;
      });
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
      // 添加后切回指针模式，便于立即编辑新节点。
      _switchMode(NodeEditorMode.pointer);
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
        title: Text(
          '${fn.name} · v${fn.version}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bolt_outlined),
            tooltip: '触发器',
            onPressed: () => _showTriggerSheet(fn),
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
                // 添加模式下展开节点面板（位于胶囊工具栏上方）。
                if (_mode == NodeEditorMode.add && _paletteExpanded)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 76,
                    child: _buildPalette(theme),
                  ),
                // 底部胶囊工具栏：指针 / 连线 / 添加。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildCapsuleToolbar(theme),
                ),
                if (_mode == NodeEditorMode.connect && _connectSourceNode != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _buildConnectHint(theme, fn),
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
                  mode: _mode,
                  onSelect: () => _onNodeLongPress(node.id),
                  onOpenEditor: () => _openNodeEditor(node.id),
                  onDelete: () => _onNodeDelete(node.id),
                  onDragUpdate: (details) =>
                      _onNodeDragUpdate(node.id, details),
                  onConnectTap: _onNodeConnectTap,
                  isConnectionSource: node.id == _connectSourceNode,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 节点面板（添加模式下展开）。仅展示分组网格，无独立展开/折叠头部。
  Widget _buildPalette(ThemeData theme) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.97),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: _buildPaletteGrid(theme),
      ),
    );
  }

  /// 底部胶囊工具栏：指针 / 连线 / 添加。
  ///
  /// 三段式胶囊，居中悬浮于画布底部，与 [CapsuleTopBar] 视觉一致：
  /// 圆角胶囊 + 半透明 + 描边；当前模式填充主色高亮。
  Widget _buildCapsuleToolbar(ThemeData theme) {
    final cs = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cs.outlineVariant, width: 0.75),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Container(
                height: 56,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModeButton(
                      icon: Icons.pan_tool_outlined,
                      label: '指针',
                      selected: _mode == NodeEditorMode.pointer,
                      onPressed: () => _switchMode(NodeEditorMode.pointer),
                    ),
                    _ModeButton(
                      icon: Icons.timeline,
                      label: '连线',
                      selected: _mode == NodeEditorMode.connect,
                      onPressed: () => _switchMode(NodeEditorMode.connect),
                    ),
                    _ModeButton(
                      icon: Icons.add_circle_outline,
                      label: '添加',
                      selected: _mode == NodeEditorMode.add,
                      onPressed: () => _switchMode(NodeEditorMode.add),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 切换编辑器模式。
  ///
  /// 切换到"添加"时默认展开节点面板；切换到其它模式时折叠面板并清除
  /// 连线起始选择态。
  void _switchMode(NodeEditorMode newMode) {
    setState(() {
      _mode = newMode;
      if (newMode == NodeEditorMode.add) {
        _paletteExpanded = true;
      } else {
        _paletteExpanded = false;
      }
      // 切换模式时清理未完成的连线起始选择。
      _connectSourceNode = null;
      _connectSourcePort = null;
    });
  }

  Widget _buildPaletteGrid(ThemeData theme) {
    // 收集所有节点种类：注册表内置规格 + 市场插件（plugin_<id>）。
    // 过滤掉自动生成的节点（不允许用户手动添加）：
    // - branch：子母节点设计的子节点，由多输出母节点自动生成
    // - function_input / function_output：函数创建时自动生成，每函数各 1 个
    final installedSpecs = ref.watch(installedPluginSpecsProvider);
    final autoKinds = const {'branch', 'function_input', 'function_output'};
    final entries = <_NodeKindEntry>[
      for (final spec in NodeKindRegistry.allKinds())
        if (!autoKinds.contains(spec.kind))
          _NodeKindEntry(
            kind: spec.kind,
            label: spec.displayName,
            icon: _iconForKind(spec.kind, spec.category),
            category: spec.category,
            group: displayGroupOf(spec.category),
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
        group: displayGroupOf(NodeCategory.plugin),
      ));
    }

    // 按 3 大展示分组：变量与数据库 / 逻辑与流程 / 执行与函数。
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        children: [
          for (final group in NodeDisplayGroup.values)
            if (entries.any((e) => e.group == group))
              _PaletteGroupWidget(
                group: group,
                entries: entries
                    .where((e) => e.group == group)
                    .toList(growable: false),
                collapsed: _collapsedGroups.contains(group),
                onToggle: () => setState(() {
                  if (_collapsedGroups.contains(group)) {
                    _collapsedGroups.remove(group);
                  } else {
                    _collapsedGroups.add(group);
                  }
                }),
                onTapEntry: _addNodeOfKind,
              ),
        ],
      ),
    );
  }

  Widget _buildConnectHint(ThemeData theme, FunctionDef fn) {
    final sourceNode = _connectSourceNode;
    final sourcePort = _connectSourcePort;
    String sourceLabel = '';
    if (sourceNode != null) {
      for (final n in fn.nodes) {
        if (n.id == sourceNode) {
          final name = n.params['name']?.toString();
          sourceLabel = (name != null && name.isNotEmpty)
              ? '$name${sourcePort != null ? ' · $sourcePort' : ''}'
              : '${n.kind}${sourcePort != null ? ' · $sourcePort' : ''}';
          break;
        }
      }
    }
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
                  sourceLabel.isEmpty
                      ? '点击起始节点（连线仅代表执行顺序）'
                      : '已选起点：$sourceLabel，点击目标节点建立连线',
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

  /// 打开当前函数的触发器编辑面板。
  ///
  /// 触发器（entry）声明函数"如何被触发"。本编辑器只编辑与 UI 无关的两类：
  /// - timer：定时触发（按毫秒间隔）
  /// - external：外部触发（深链 / 推送 / app_start 等）
  /// uiEvent / pageEvent 仍由 UI 编辑器编辑（与组件 / 页面绑定）。
  void _showTriggerSheet(FunctionDef fn) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _FunctionTriggerSheet(initial: fn),
    );
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
    required this.group,
  });

  final String kind;
  final String label;
  final IconData icon;
  final NodeCategory category;
  final NodeDisplayGroup group;
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
  // 兜底：plugin_<id> 等市场插件用扩展图标，其余用展示分组图标。
  if (kind.startsWith('plugin_')) return Icons.extension;
  return displayGroupIcon(displayGroupOf(category));
}

/// 可折叠的节点展示分组。
///
/// 标题行展示分组图标 + 名称 + 节点数 + 折叠箭头；展开时下方横向滚动节点按钮。
class _PaletteGroupWidget extends StatelessWidget {
  const _PaletteGroupWidget({
    required this.group,
    required this.entries,
    required this.collapsed,
    required this.onToggle,
    required this.onTapEntry,
  });

  final NodeDisplayGroup group;
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
                  Icon(displayGroupIcon(group),
                      size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    displayGroupLabel(group),
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

/// 胶囊工具栏中的模式按钮。
///
/// 选中态：填充主色 + onPrimary 图标文字；未选中态：透明 + onSurfaceVariant。
/// 触控区充足（宽 72，高 48），圆角 24，与胶囊外形一致。
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 函数触发器编辑面板（每个函数编辑自己的 entry）。
///
/// 仅编辑与 UI 无关的两类触发器：
/// - [EntryKind.timer]：定时触发，[FunctionEntry.ref] 存间隔毫秒数字符串。
/// - [EntryKind.external]：外部触发，[FunctionEntry.ref] 存触发标识
///   （深链路径或推送事件名）。
///
/// UI 事件（uiEvent）与页面事件（pageEvent）触发器由 UI 编辑器编辑，
/// 不在此面板内。当前函数已有的 uiEvent / pageEvent entry 仅作只读展示。
class _FunctionTriggerSheet extends ConsumerStatefulWidget {
  const _FunctionTriggerSheet({required this.initial});

  final FunctionDef initial;

  @override
  ConsumerState<_FunctionTriggerSheet> createState() =>
      _FunctionTriggerSheetState();
}

class _FunctionTriggerSheetState extends ConsumerState<_FunctionTriggerSheet> {
  late final TextEditingController _intervalController;
  late final TextEditingController _extRefController;

  @override
  void initState() {
    super.initState();
    final entry = widget.initial.entry;
    _intervalController = TextEditingController(
      text: entry?.kind == EntryKind.timer ? (entry?.ref ?? '5000') : '5000',
    );
    _extRefController = TextEditingController(
      text: entry?.kind == EntryKind.external ? (entry?.ref ?? '') : '',
    );
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _extRefController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.initial.entry;
    final mutator = ref.read(graphMutatorProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ListView(
            controller: controller,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '触发器 — ${widget.initial.name}',
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '声明此函数如何被触发。UI 事件与页面事件触发器请在 UI 编辑器中绑定。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 12),

              // ---- 当前触发器状态 ----
              _CurrentEntryCard(entry: entry, onClear: mutator.clearEntry),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // ---- 定时器区 ----
              _SectionTitle(text: '定时器'),
              const SizedBox(height: 6),
              Text(
                '按固定间隔（毫秒）重复触发此函数。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '间隔（毫秒）',
                        hintText: '如 5000',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      final ms = int.tryParse(_intervalController.text.trim());
                      if (ms == null || ms <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入正整数间隔')),
                        );
                        return;
                      }
                      mutator.setTimerEntry(ms);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已设置定时器：每 $ms ms 触发')),
                      );
                    },
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('设置'),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // ---- 外部触发区 ----
              _SectionTitle(text: '外部触发（深链 / 推送）'),
              const SizedBox(height: 6),
              Text(
                '宿主应用通过匹配标识唤起此函数（如 app_start、/page/detail、'
                'push_event_name）。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _extRefController,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '触发标识',
                        hintText: '如 /page/detail 或 push_event_name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final ref = _extRefController.text.trim();
                      if (ref.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入触发标识')),
                        );
                        return;
                      }
                      mutator.setExternalEntry(ref);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已设置外部触发：$ref')),
                      );
                    },
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('设置'),
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

/// 当前触发器状态卡片（只读展示 + 清除按钮）。
class _CurrentEntryCard extends StatelessWidget {
  const _CurrentEntryCard({required this.entry, required this.onClear});

  final FunctionEntry? entry;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (entry == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.flag_outlined, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '当前未声明触发器：函数仅能被其他函数显式调用。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    final kind = entry!.kind;
    final label = switch (kind) {
      EntryKind.timer => '定时器',
      EntryKind.external => '外部触发',
      EntryKind.uiEvent => 'UI 事件（请在 UI 编辑器编辑）',
      EntryKind.pageEvent => '页面事件（请在 UI 编辑器编辑）',
      EntryKind.funcCall => '函数调用',
    };
    final icon = switch (kind) {
      EntryKind.timer => Icons.timer,
      EntryKind.external => Icons.link,
      EntryKind.uiEvent => Icons.touch_app_outlined,
      EntryKind.pageEvent => Icons.article_outlined,
      EntryKind.funcCall => Icons.functions,
    };
    final editable = kind == EntryKind.timer || kind == EntryKind.external;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                if ((entry!.ref ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'ref: ${entry!.ref}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (editable)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '清除触发器',
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}
