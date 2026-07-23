import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// 应用入口。
///
/// 使用 [ProviderScope] 包裹根 Widget，启用 Riverpod 状态管理。
void main() {
  runApp(
    const ProviderScope(
      child: NodeVisualApp(),
    ),
  );
}
