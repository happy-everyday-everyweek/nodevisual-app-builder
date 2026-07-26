import 'package:flutter/foundation.dart';

/// 崩溃日志写入接口。
///
/// 通过条件导入在 IO 平台实现文件写入，在 Web 平台为空实现。
/// 默认实现仅输出到控制台，确保条件导入解析前代码仍能通过编译。
Future<void> writeCrashLog(String type, Object error, StackTrace? stack) async {
  debugPrint('Crash log [$type]: $error');
  if (stack != null) {
    debugPrint(stack.toString());
  }
}
