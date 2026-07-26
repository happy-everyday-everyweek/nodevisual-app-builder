import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// IO 平台崩溃日志实现（Android / iOS / Windows / macOS / Linux）。
///
/// 将异常信息追加写入应用内部与外部可访问的日志文件。
/// 外部路径无需运行时权限（Android 10+ 对应用专属目录豁免），
/// 方便用户通过 MT 管理器等文件浏览器直接读取。
Future<void> writeCrashLog(String type, Object error, StackTrace? stack) async {
  final buffer = StringBuffer()
    ..writeln('=== NodeVisual Crash Log ===')
    ..writeln('Time: ${DateTime.now().toIso8601String()}')
    ..writeln('Type: $type')
    ..writeln('Error: $error');
  if (stack != null) {
    buffer.writeln('Stack:\n$stack');
  }
  buffer.writeln('==============================');
  final text = buffer.toString();

  // 1) 写入内部文档目录（一定成功）。
  try {
    final dir = await getApplicationDocumentsDirectory();
    await _append(p.join(dir.path, 'crash.log'), text);
  } catch (e) {
    debugPrint('写入内部崩溃日志失败: $e');
  }

  // 2) 尝试写入应用专属外部目录，便于用户直接导出。
  try {
    // Android 应用专属外部目录：/sdcard/Android/data/<package>/files/
    final externalDir = Directory(
      '/sdcard/Android/data/com.nodevisual.nodevisual_app_builder/files',
    );
    if (!externalDir.existsSync()) {
      externalDir.createSync(recursive: true);
    }
    await _append(p.join(externalDir.path, 'crash.log'), text);
  } catch (e) {
    debugPrint('写入外部崩溃日志失败: $e');
  }
}

Future<void> _append(String path, String text) async {
  final file = File(path);
  if (await file.exists()) {
    await file.writeAsString('\n$text', mode: FileMode.append, flush: true);
  } else {
    await file.writeAsString(text, flush: true);
  }
}
