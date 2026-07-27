import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'graph_providers.dart';

/// 测试运行环境预设。
///
/// 描述函数在测试运行时可用的平台信息、设备尺寸、环境变量等。
/// 用户可选择预设，也可基于预设自定义。
class TestEnvironment {
  const TestEnvironment({
    required this.id,
    required this.name,
    required this.platform,
    this.screenWidth = 360,
    this.screenHeight = 640,
    this.devicePixelRatio = 1.0,
    this.userAgent,
    this.locale = 'zh-CN',
    this.extra = const {},
  });

  /// 环境唯一标识。
  final String id;

  /// 展示名称。
  final String name;

  /// 目标平台（影响 platform 节点与部分插件行为）。
  final TargetPlatform platform;

  /// 屏幕宽度（逻辑像素）。
  final double screenWidth;

  /// 屏幕高度（逻辑像素）。
  final double screenHeight;

  /// 设备像素比。
  final double devicePixelRatio;

  /// User-Agent（Web 环境用）。
  final String? userAgent;

  /// 区域语言。
  final String locale;

  /// 额外环境变量（key-value）。
  final Map<String, dynamic> extra;

  /// 复制并覆盖部分字段。
  TestEnvironment copyWith({
    String? id,
    String? name,
    TargetPlatform? platform,
    double? screenWidth,
    double? screenHeight,
    double? devicePixelRatio,
    String? userAgent,
    String? locale,
    Map<String, dynamic>? extra,
  }) {
    return TestEnvironment(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      screenWidth: screenWidth ?? this.screenWidth,
      screenHeight: screenHeight ?? this.screenHeight,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
      userAgent: userAgent ?? this.userAgent,
      locale: locale ?? this.locale,
      extra: extra ?? this.extra,
    );
  }

  /// 转换为运行时 Map，供节点执行器读取。
  Map<String, dynamic> toRuntimeMap() {
    return {
      'platform': _platformName(platform),
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      'devicePixelRatio': devicePixelRatio,
      'userAgent': userAgent,
      'locale': locale,
      'isWeb': platform == TargetPlatform.linux ||
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.windows,
      ...extra,
    };
  }

  static String _platformName(TargetPlatform p) {
    return switch (p) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}

/// 内置测试环境预设。
final List<TestEnvironment> builtinTestEnvironments = [
  const TestEnvironment(
    id: 'android_mobile',
    name: 'Android 手机',
    platform: TargetPlatform.android,
    screenWidth: 360,
    screenHeight: 780,
    devicePixelRatio: 2.75,
    userAgent:
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36',
    extra: {'brand': 'Google', 'model': 'Pixel 8'},
  ),
  const TestEnvironment(
    id: 'windows_desktop',
    name: 'Windows 桌面',
    platform: TargetPlatform.windows,
    screenWidth: 1280,
    screenHeight: 720,
    devicePixelRatio: 1.0,
    userAgent: 'NodeVisual/Windows Test Environment',
    extra: {'osVersion': 'Windows 11'},
  ),
  const TestEnvironment(
    id: 'web_desktop',
    name: 'Web 桌面',
    platform: TargetPlatform.linux,
    screenWidth: 1280,
    screenHeight: 720,
    devicePixelRatio: 1.0,
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    extra: {'browser': 'Chrome'},
  ),
  const TestEnvironment(
    id: 'web_mobile',
    name: 'Web 移动端',
    platform: TargetPlatform.linux,
    screenWidth: 375,
    screenHeight: 812,
    devicePixelRatio: 2.0,
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
    extra: {'browser': 'Safari'},
  ),
];

/// 测试运行单条日志。
class TestRunLog {
  const TestRunLog({
    required this.nodeId,
    required this.nodeKind,
    required this.timestamp,
  });

  final String nodeId;
  final String nodeKind;
  final DateTime timestamp;
}

/// 测试运行结果。
class TestRunResult {
  const TestRunResult({
    this.outputs = const {},
    this.error,
    this.logs = const [],
    this.durationMs = 0,
  });

  final Map<String, dynamic> outputs;
  final String? error;
  final List<TestRunLog> logs;
  final int durationMs;
}

/// 测试运行状态。
class TestRunState {
  const TestRunState({
    this.isRunning = false,
    this.currentNodeId,
    this.inputs = const {},
    this.environment,
    this.result,
    this.customEnvironment,
  });

  final bool isRunning;
  final String? currentNodeId;
  final Map<String, dynamic> inputs;
  final TestEnvironment? environment;
  final TestRunResult? result;
  final TestEnvironment? customEnvironment;

  TestRunState copyWith({
    bool? isRunning,
    String? currentNodeId,
    Map<String, dynamic>? inputs,
    TestEnvironment? environment,
    TestRunResult? result,
    TestEnvironment? customEnvironment,
  }) {
    return TestRunState(
      isRunning: isRunning ?? this.isRunning,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      inputs: inputs ?? this.inputs,
      environment: environment ?? this.environment,
      result: result ?? this.result,
      customEnvironment: customEnvironment ?? this.customEnvironment,
    );
  }
}

/// 当前函数编辑器的测试运行状态控制器。
///
/// 与 [editedFunctionIdProvider] 生命周期绑定：函数编辑器打开时创建，
/// 关闭时释放。提供设置入参、选择环境、启动测试运行、高亮当前节点能力。
class TestRunNotifier extends Notifier<TestRunState> {
  @override
  TestRunState build() {
    // 监听当前编辑函数，函数切换时重置状态。
    ref.watch(editedFunctionIdProvider);
    final env = _defaultEnvironment();
    return TestRunState(environment: env);
  }

  TestEnvironment _defaultEnvironment() {
    if (kIsWeb) return builtinTestEnvironments.firstWhere((e) => e.id == 'web_desktop');
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => builtinTestEnvironments.firstWhere((e) => e.id == 'android_mobile'),
      TargetPlatform.windows => builtinTestEnvironments.firstWhere((e) => e.id == 'windows_desktop'),
      _ => builtinTestEnvironments.firstWhere((e) => e.id == 'web_desktop'),
    };
  }

  /// 设置测试入参。
  void setInputs(Map<String, dynamic> inputs) {
    state = state.copyWith(inputs: inputs);
  }

  /// 设置单个入参。
  void setInput(String name, dynamic value) {
    final newInputs = Map<String, dynamic>.from(state.inputs);
    newInputs[name] = value;
    state = state.copyWith(inputs: newInputs);
  }

  /// 选择测试环境。
  void selectEnvironment(TestEnvironment env) {
    state = state.copyWith(environment: env);
  }

  /// 设置自定义环境。
  void setCustomEnvironment(TestEnvironment env) {
    state = state.copyWith(customEnvironment: env, environment: env);
  }

  /// 更新当前执行到的节点 id（供解释器回调）。
  void setCurrentNode(String? nodeId) {
    state = state.copyWith(currentNodeId: nodeId);
  }

  /// 标记运行开始。
  void startRun() {
    state = state.copyWith(
      isRunning: true,
      currentNodeId: null,
      result: null,
    );
  }

  /// 标记运行结束并记录结果。
  void finishRun(TestRunResult result) {
    state = state.copyWith(
      isRunning: false,
      currentNodeId: null,
      result: result,
    );
  }

  /// 取消/停止运行（仅清除运行态，不中断实际解释器执行）。
  void reset() {
    state = state.copyWith(
      isRunning: false,
      currentNodeId: null,
      result: null,
    );
  }
}

/// 测试运行状态 provider（与函数编辑器绑定）。
final testRunProvider = NotifierProvider<TestRunNotifier, TestRunState>(TestRunNotifier.new);
