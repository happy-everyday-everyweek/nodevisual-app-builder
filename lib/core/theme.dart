import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';

/// 应用极简黑白灰主题。
///
/// 设计准则：
/// - **纯黑白灰**：白底黑字，灰阶 (#F5F5F7 / #E5E5EA / #D1D1D6 / #8E8E93)
///   承担分隔与层级；强调色用近黑 (#1C1C1E)，暗色模式则反相。
/// - **中等宽松**：Card 圆角 16、按钮高度 48+、列表行距适度加大；
///   全局页面内边距 16→20，组件间垂直节奏 8→12。
/// - **动画"哪去哪回"**：路由过渡使用 [ReverseTransition] 自定义 pageBuilder，
///   退出原路反向；组件显隐用 [AnimatedSwitcher] / [AnimatedSize]，
///   切换曲线统一 [Curves.easeOutCubic]（正向）与 [Curves.easeInCubic]（反向）。
class AppTheme {
  AppTheme._();

  // ---- 灰阶色板（亮色 / 暗色共享）----
  // 命名遵循 iOS HIG 灰阶，便于记忆。
  static const Color _lightBg = Color(0xFFFFFFFF);
  static const Color _lightSurface = Color(0xFFF7F7F9);
  static const Color _lightSurfaceHigh = Color(0xFFEFEFF2);
  static const Color _lightSurfaceHighest = Color(0xFFE5E5EA);
  static const Color _lightBorder = Color(0xFFD1D1D6);
  static const Color _lightBorderStrong = Color(0xFFC7C7CC);
  static const Color _lightText = Color(0xFF1C1C1E);
  static const Color _lightTextSecondary = Color(0xFF3C3C43);
  static const Color _lightTextTertiary = Color(0xFF8E8E93);
  static const Color _lightAccent = Color(0xFF1C1C1E); // 强调用近黑

  static const Color _darkBg = Color(0xFF000000);
  static const Color _darkSurface = Color(0xFF1C1C1E);
  static const Color _darkSurfaceHigh = Color(0xFF2C2C2E);
  static const Color _darkSurfaceHighest = Color(0xFF3A3A3C);
  static const Color _darkBorder = Color(0xFF38383A);
  static const Color _darkBorderStrong = Color(0xFF48484A);
  static const Color _darkText = Color(0xFFFFFFFF);
  static const Color _darkTextSecondary = Color(0xFFEBEBF0);
  static const Color _darkTextTertiary = Color(0xFF9C9CA0);
  static const Color _darkAccent = Color(0xFFFFFFFF); // 暗色强调用白

  /// 亮色主题。
  static ThemeData get light {
    final scheme = _buildScheme(brightness: Brightness.light);
    return _base(scheme, brightness: Brightness.light);
  }

  /// 暗色主题。
  static ThemeData get dark {
    final scheme = _buildScheme(brightness: Brightness.dark);
    return _base(scheme, brightness: Brightness.dark);
  }

  static ColorScheme _buildScheme({required Brightness brightness}) {
    final isLight = brightness == Brightness.light;
    return ColorScheme(
      brightness: brightness,
      primary: isLight ? _lightAccent : _darkAccent,
      onPrimary: isLight ? _lightBg : _darkBg,
      primaryContainer: isLight ? _lightSurfaceHigh : _darkSurfaceHigh,
      onPrimaryContainer: isLight ? _lightText : _darkText,
      secondary: isLight ? _lightTextSecondary : _darkTextSecondary,
      onSecondary: isLight ? _lightBg : _darkBg,
      secondaryContainer: isLight ? _lightSurfaceHigh : _darkSurfaceHigh,
      onSecondaryContainer: isLight ? _lightText : _darkText,
      tertiary: isLight ? _lightTextTertiary : _darkTextTertiary,
      onTertiary: isLight ? _lightBg : _darkBg,
      tertiaryContainer: isLight ? _lightSurfaceHighest : _darkSurfaceHighest,
      onTertiaryContainer: isLight ? _lightText : _darkText,
      error: isLight ? const Color(0xFFB00020) : const Color(0xFFFF453A),
      onError: Colors.white,
      errorContainer:
          isLight ? const Color(0xFFFDECEC) : const Color(0xFF4C0A0A),
      onErrorContainer: isLight ? const Color(0xFFB00020) : Colors.white,
      surface: isLight ? _lightBg : _darkBg,
      onSurface: isLight ? _lightText : _darkText,
      surfaceDim: isLight ? _lightSurface : _darkSurface,
      surfaceBright: isLight ? _lightBg : _darkSurfaceHigh,
      surfaceContainerLowest: isLight ? _lightBg : _darkBg,
      surfaceContainerLow: isLight ? _lightSurface : _darkSurface,
      surfaceContainer: isLight ? _lightSurface : _darkSurface,
      surfaceContainerHigh: isLight ? _lightSurfaceHigh : _darkSurfaceHigh,
      surfaceContainerHighest:
          isLight ? _lightSurfaceHighest : _darkSurfaceHighest,
      outline: isLight ? _lightBorderStrong : _darkBorderStrong,
      outlineVariant: isLight ? _lightBorder : _darkBorder,
      shadow: isLight ? const Color(0xFF1C1C1E) : Colors.black,
      scrim: isLight ? const Color(0xFF1C1C1E) : Colors.black,
      inverseSurface: isLight ? _lightText : _darkText,
      onInverseSurface: isLight ? _lightBg : _darkBg,
      inversePrimary: isLight ? _lightText : _darkText,
    );
  }

  static ThemeData _base(
    ColorScheme colorScheme, {
    required Brightness brightness,
  }) {
    final isLight = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      // 系统状态栏：亮色模式黑字 / 暗色模式白字。
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      // 中等宽松：圆角 16，描边替代强阴影（极简风）
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant,
            width: 0.75,
          ),
        ),
      ),
      // 触控友好：行距适度加大。
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: const CircleBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(56, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(56, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(56, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 0.75,
        color: colorScheme.outlineVariant,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primary,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      // Tab 极简：下划线指示器 + 无背景。
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.onSurface,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 2,
          ),
          insets: const EdgeInsets.symmetric(horizontal: 0),
        ),
        dividerColor: colorScheme.outlineVariant,
        dividerHeight: 0.75,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.onSurface,
        contentTextStyle: TextStyle(color: colorScheme.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: colorScheme.outline,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        extendedPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      // 默认页面切换动画时长（与 GoRouter pageBuilder 配合）。
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoTransitionBuilder(),
          TargetPlatform.iOS: _NoTransitionBuilder(),
        },
      ),
    );
  }
}

/// 空白 PageTransitionsBuilder：禁用 Material 默认页面切换，
/// 让 GoRouter 的自定义 pageBuilder 接管全部过渡。
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
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
