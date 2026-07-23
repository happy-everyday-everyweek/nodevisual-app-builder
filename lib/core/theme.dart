import 'package:flutter/material.dart';

import 'constants.dart';

/// 应用 Material 主题定义。
///
/// 采用 Material 3 设计规范，定义亮色与暗色两套配色方案，
/// 统一控件外观，方便后续节点画布等自定义视图复用。
class AppTheme {
  AppTheme._();

  /// 亮色主题。
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2196F3),
      brightness: Brightness.light,
    );
    return _base(colorScheme);
  }

  /// 暗色主题。
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2196F3),
      brightness: Brightness.dark,
    );
    return _base(colorScheme);
  }

  static ThemeData _base(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      // 触控友好：不强制 dense（保留默认行高，确保 >=48dp 命中区）。
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 8,
      ),
      // 触控目标最小化：IconButton 默认 48dp 命中区。
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      // 按钮默认 minimumSize 满足触控目标。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: colorScheme.outlineVariant,
      ),
    );
  }
}

/// 应用标题栏通用工具（供占位页面复用）。
AppBar buildScaffoldAppBar(String title) {
  return AppBar(
    title: Text(title),
    titleSpacing: 0,
  );
}

/// 应用标题字符串便捷拼接。
String get appTitle => AppConstants.appName;
