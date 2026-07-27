/// 动画系统 barrel file（Phase 5）。
///
/// 统一导出动画相关类，便于外部一次性 import：
/// ```dart
/// import 'package:nodevisual_app_builder/features/ui_editor/animations/animations.dart';
/// ```
///
/// 包含：
/// - [PresetAnimationExecutor]：预设动画执行器（Tween/Curve/Controller 工厂）。
/// - [KeyframeAnimationExecutor]：关键帧动画执行器（关键帧间插值）。
/// - [AnimationRuntime]：动画运行时（播放入口/出场/触发动画）。
/// - [AnimatedComponent]：动画包装器 Widget（自动播放入场动画）。
/// - [PresetAnimationEditor]：预设动画编辑器（带预览播放）。
/// - [KeyframeAnimationEditor]：关键帧动画编辑器（带可视化时间轴）。
/// - [AnimationPanel]：动画配置面板（入场/出场/触发三段折叠）。
library;

export 'animation_presets.dart';
export 'animation_runtime.dart';
export 'animated_component.dart';
export 'animation_panel.dart';
export 'keyframe_editor.dart';
export 'keyframe_executor.dart';
export 'preset_editor.dart';
