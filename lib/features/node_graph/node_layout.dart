import 'dart:ui';

/// 节点画布共享布局常量。
///
/// 这些常量是 [NodeCard] 渲染布局与 [ConnectionPainter] /
/// [FunctionEditorScreen] 连线坐标计算之间的契约：
/// - [NodeCard] 按这些值布局节点行；
/// - 画布与连线层用这些值由节点 [Node.position] 反推端口在画布坐标系的位置。
///
/// 改动任一值需同步三者。
///
/// **节点显示简化**：节点卡片只渲染头部（图标+名称+关联标签+删除）+
/// 可选注释行。不再渲染控制流输出行 / 数据输出行（节点系统已统一为
/// 单输入单输出，多输出由子母节点表达）。
///
/// **端口位置**：
/// - 入口端口：头部左侧中点 `Offset(0, headerHeight/2)`。
/// - 单输出端口（含 `branch` 子节点）：头部右侧中点 `Offset(width, headerHeight/2)`。
/// - 母节点（`controlOutputs.length >= 2` 且非 `branch`）的多输出端口：
///   头部底部中央 `Offset(width/2, headerHeight + annotationHeight)`，
///   多个端口共用同一位置，连线自然向下方各 `branch` 子节点分散。
///
/// **连线交互**：采用两步点击式（先点起始节点，再点终止节点），
/// 无端口圆点。连线仅表达执行顺序，与参数传递无关。
class NodeLayout {
  NodeLayout._();

  /// 节点卡片宽度。
  static const double width = 160;

  /// 节点头部高度（标题所在行）。
  static const double headerHeight = 36;

  /// 注释行高度（节点有 annotation 时显示在头部下方）。
  static const double annotationRowHeight = 18;

  /// 控制流连线粗细。
  static const double connectionStrokeWidth = 3;

  /// 命中连线时的容差（点击 / 长按连线检测）。
  static const double edgeHitThreshold = 14;

  /// 计算节点入口端口（"in"）相对节点左上角的偏移。
  static Offset inputPortOffset() => const Offset(0, headerHeight / 2);

  /// 计算单输出节点（含 `branch` 子节点）的输出端口相对节点左上角的偏移。
  ///
  /// 单输出节点的唯一控制流输出（通常为 `next`）位于头部右侧中点，
  /// 与入口端口对称。
  static Offset singleOutputPortOffset() =>
      const Offset(width, headerHeight / 2);

  /// 计算母节点（多输出）的输出端口相对节点左上角的偏移。
  ///
  /// 母节点的所有控制流输出端口共用底部中央位置，连线自然向下方
  /// 各 `branch` 子节点分散。[annotationHeight] 为注释行高度（无注释传 0）。
  static Offset multiOutputPortOffset(double annotationHeight) =>
      Offset(width / 2, headerHeight + annotationHeight);

  /// 计算节点卡片高度（基于是否有注释）。
  ///
  /// 简化后节点高度仅由头部 + 可选注释行决定，不再受控制流/数据输出
  /// 数量影响（这些行不再渲染）。
  static double nodeHeight({bool hasAnnotation = false}) {
    return headerHeight + (hasAnnotation ? annotationRowHeight : 0);
  }
}

/// 生成端口位置键（用于 [ConnectionPainter.portPositions] 映射）。
///
/// - 输出端口键：`nodeId:portName`
/// - 入口端口键：`nodeId:in`
String portKey(String nodeId, String portName) => '$nodeId:$portName';

/// 入口端口键后缀。
const String inputPortSuffix = 'in';
