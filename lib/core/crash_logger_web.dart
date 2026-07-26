import 'package:flutter/foundation.dart';

import 'crash_logger.dart';

/// Web 平台崩溃日志空实现。
///
/// Web 端没有文件系统访问能力，崩溃信息直接输出到浏览器控制台。
Future<void> writeCrashLog(String type, Object error, StackTrace? stack) async {
  debugPrint('Web crash log [$type]: $error');
  if (stack != null) {
    debugPrint(stack.toString());
  }
}
