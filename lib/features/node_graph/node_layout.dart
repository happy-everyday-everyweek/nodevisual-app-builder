import 'dart:ui';

/// 节点画布共享布局常量。
///
/// 这些常量是 [NodeCard] 渲染布局与 [ConnectionPainter] /
/// [FunctionEditorScreen] 端口命中检测之间的契约：
/// - [NodeCard] 按这些值布局端口；
/// - 画布与连线层用这些值由节点 [Node.position] 反推端口在画布坐标系的位置。
///
/// 改动任一值需同步三者。
class NodeLayout {
  NodeLayout._();

  /// 节点卡片宽度。
  static const double width = 160;

  /// 节点头部高度（标题 + 入口端口所在行）。
  static const double headerHeight = 36;

  /// 单个控制流输出端口行高度。
  static const double outputRowHeight = 24;

  /// 单个数据输出展示行高度。
  static const double dataRowHeight = 20;

  /// 端口视觉圆点半径。
  static const double portRadius = 6;

  /// 端口触控命中半径（移动端放大触控区，44dp 命中区）。
  static const double portHitRadius = 22;

  /// 控制流连线粗细。
  static const double connectionStrokeWidth = 3;

  /// 拖拽连线释放时，寻找目标入口端口的命中阈值（画布坐标）。
  static const double portHitThreshold = 36;

  /// 命中连线时的容差（点击 / 长按连线检测）。
  static const double edgeHitThreshold = 14;

  /// 计算节点入口端口（"in"）相对节点左上角的偏移。
  static Offset inputPortOffset() =>
      const Offset(0, headerHeight / 2);

  /// 计算第 [index] 个控制流输出端口相对节点左上角的偏移。
  static Offset outputPortOffset(int index) =>
      Offset(width, headerHeight + index * outputRowHeight + outputRowHeight / 2);

  /// 计算节点卡片高度（基于控制流输出 + 数据输出数量）。
  static double nodeHeight({
    required int controlOutputCount,
    required int dataOutputCount,
  }) {
    var h = headerHeight + controlOutputCount * outputRowHeight;
    if (dataOutputCount > 0) {
      h += 1 + dataOutputCount * dataRowHeight; // 1px 分割线
    }
    return h;
  }
}

/// 生成端口位置键（用于 [ConnectionPainter.portPositions] 映射）。
///
/// - 输出端口键：`nodeId:portName`
/// - 入口端口键：`nodeId:in`
String portKey(String nodeId, String portName) => '$nodeId:$portName';

/// 入口端口键后缀。
const String inputPortSuffix = 'in';
