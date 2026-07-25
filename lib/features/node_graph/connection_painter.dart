import 'package:flutter/material.dart';

import '../../data/models/control_edge.dart';
import 'node_layout.dart';

/// 控制流连线绘制器（双平面模型的"控制平面"画布层）。
///
/// 在画布坐标系（即 [InteractiveViewer] 内部 Stack 的坐标系）下绘制：
/// - 已建立的 [ControlEdge] 列表，用贝塞尔曲线连接源端口与目标入口端口；
/// - 选中态连线高亮。
///
/// 端口位置由外部通过 [portPositions] 提供（键为 [portKey] 计算结果，
/// 入口端口键为 `nodeId:in`）。
///
/// **连线语义**：连线仅表达执行顺序与控制流分支，与参数传递无关。
/// 数据平面通过节点 [Node.params] 中的 `#` 引用独立完成。
class ConnectionPainter extends CustomPainter {
  ConnectionPainter({
    required this.edges,
    required this.portPositions,
    required this.color,
    this.selectedEdgeKey,
    this.selectedColor = const Color(0xFFE53935),
    super.repaint,
  });

  /// 当前所有控制流边。
  final List<ControlEdge> edges;

  /// 端口画布坐标映射（键：`nodeId:portName` 或 `nodeId:in`）。
  final Map<String, Offset> portPositions;

  /// 连线默认颜色。
  final Color color;

  /// 选中边的高亮颜色。
  final Color selectedColor;

  /// 选中边的键（`fromNode:fromPort:toNode`），null 表示无选中。
  final String? selectedEdgeKey;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final fromKey = portKey(edge.fromNode, edge.fromPort);
      final toKey = '${edge.toNode}:$inputPortSuffix';
      final from = portPositions[fromKey];
      final to = portPositions[toKey];
      if (from == null || to == null) continue;
      final key = '${edge.fromNode}:${edge.fromPort}:${edge.toNode}';
      final isSelected = key == selectedEdgeKey;
      final path = _bezierPath(from, to);
      final paint = _strokePaint(
        isSelected ? selectedColor : color,
        isSelected
            ? NodeLayout.connectionStrokeWidth + 1.5
            : NodeLayout.connectionStrokeWidth,
      );
      canvas.drawPath(path, paint);
      // 在目标端口处画一个小箭头，强化方向感。
      _drawArrow(canvas, to, from, isSelected ? selectedColor : color);
    }
  }

  Paint _strokePaint(Color c, double width) => Paint()
    ..color = c
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  /// 构造水平贝塞尔曲线（控制点水平偏移，营造"流"的视觉）。
  Path _bezierPath(Offset from, Offset to) {
    final dx = (to.dx - from.dx).abs();
    final cp = (dx * 0.5 + 40).clamp(20.0, 200.0);
    // 起点向右延伸控制点；终点向左延伸控制点（兼容反向）。
    final sign = to.dx >= from.dx ? 1.0 : -1.0;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx + cp * sign,
        from.dy,
        to.dx - cp * sign,
        to.dy,
        to.dx,
        to.dy,
      );
  }

  /// 在 [to] 端绘制一个三角形箭头，朝向 [from] -> [to] 的方向。
  void _drawArrow(Canvas canvas, Offset to, Offset from, Color color) {
    final direction = (to - from);
    final len = direction.distance;
    if (len < 1) return;
    final unit = direction / len;
    const arrowSize = 7.0;
    final tip = to - unit * 2; // 略微缩进，避免覆盖端口圆点。
    final base = to - unit * (2 + arrowSize);
    final perp = Offset(-unit.dy, unit.dx) * (arrowSize * 0.6);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + perp.dx, base.dy + perp.dy)
      ..lineTo(base.dx - perp.dx, base.dy - perp.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.portPositions != portPositions ||
        oldDelegate.color != color ||
        oldDelegate.selectedEdgeKey != selectedEdgeKey ||
        oldDelegate.selectedColor != selectedColor;
  }
}

/// 判断画布坐标 [point] 是否贴近 [from] -> [to] 的贝塞尔连线
/// （用于点击 / 长按连线命中检测）。
///
/// 通过对曲线采样若干点取最近距离，避免解析求解贝塞尔最近点的复杂度。
bool isPointNearEdge(
  Offset point,
  Offset from,
  Offset to, {
  double threshold = NodeLayout.edgeHitThreshold,
}) {
  final dx = (to.dx - from.dx).abs();
  final cp = (dx * 0.5 + 40).clamp(20.0, 200.0);
  final sign = to.dx >= from.dx ? 1.0 : -1.0;
  final cp1 = Offset(from.dx + cp * sign, from.dy);
  final cp2 = Offset(to.dx - cp * sign, to.dy);
  const samples = 24;
  for (var i = 0; i <= samples; i++) {
    final t = i / samples;
    final p = _cubicAt(from, cp1, cp2, to, t);
    if ((p - point).distance <= threshold) return true;
  }
  return false;
}

Offset _cubicAt(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final u = 1 - t;
  final a = u * u * u;
  final b = 3 * u * u * t;
  final c = 3 * u * t * t;
  final d = t * t * t;
  return Offset(
    a * p0.dx + b * p1.dx + c * p2.dx + d * p3.dx,
    a * p0.dy + b * p1.dy + c * p2.dy + d * p3.dy,
  );
}
