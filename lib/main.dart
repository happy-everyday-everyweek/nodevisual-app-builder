import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';

/// 应用入口。
///
/// 使用 [ProviderScope] 包裹根 Widget，启用 Riverpod 状态管理。
/// 同时安装顶层异常捕获器，将 Dart 层崩溃信息写入日志文件，便于在
/// 无法连接 ADB 的真机环境中排查启动闪退问题。
void main() {
  // 确保 Flutter 绑定与插件已初始化，否则异常处理器中调用 path_provider
  // 等插件时可能出现未初始化错误。
  WidgetsFlutterBinding.ensureInitialized();

  // 同步注册 Flutter 框架错误回调，捕获 build/layout 等异常。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _writeCrashLog('FlutterError', details.exception, details.stack);
  };

  // 用 Zone 包裹异步异常与未捕获同步异常。
  runZonedGuarded(
    () => runApp(
      const ProviderScope(
        child: NodeVisualApp(),
      ),
    ),
    (error, stack) => _writeCrashLog('ZoneError', error, stack),
  );
}

/// 将异常信息追加写入应用内部与外部可访问的日志文件。
///
/// 写入路径：
/// - 内部：`/data/data/<package>/files/crash.log`
/// - 外部：`/sdcard/Android/data/<package>/files/crash.log`
///
/// 外部路径无需运行时权限（Android 10+ 对应用专属目录豁免），
/// 方便用户通过 MT 管理器等文件浏览器直接读取。
Future<void> _writeCrashLog(String type, Object error, StackTrace? stack) async {
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
    final externalDir = Directory('/sdcard/Android/data/com.nodevisual.nodevisual_app_builder/files');
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
