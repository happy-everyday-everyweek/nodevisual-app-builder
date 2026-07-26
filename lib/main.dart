import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/crash_logger.dart'
    if (dart.library.html) 'core/crash_logger_web.dart'
    if (dart.library.io) 'core/crash_logger_io.dart';

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
    writeCrashLog('FlutterError', details.exception, details.stack);
  };

  // 用 Zone 包裹异步异常与未捕获同步异常。
  runZonedGuarded(
    () => runApp(
      const ProviderScope(
        child: NodeVisualApp(),
      ),
    ),
    (error, stack) => writeCrashLog('ZoneError', error, stack),
  );
}
