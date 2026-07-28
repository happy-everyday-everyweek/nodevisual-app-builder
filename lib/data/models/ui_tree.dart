import 'package:collection/collection.dart';

import 'variable_ref.dart';

const DeepCollectionEquality _uiDeepEq = DeepCollectionEquality();

/// 加载态策略（仅用于含时间线的引用：函数变量、组件上下文未渲染对应项）。
///
/// 当 `#` 引用解析时变量未就绪（函数未执行/执行中/失败，或容器组件
/// 未渲染到对应项），系统按此策略返回占位值，避免 UI 出现 undefined。
enum LoadingStrategy {
  /// 按类型返回默认值（number→0, string→'', list→[], map→{}, bool→false）。
  typeDefault,

  /// 返回用户填写的占位文字（[Binding.placeholderText]）。
  placeholder,

  /// 不渲染该属性（文本类返回空串，图片类返回 null 触发不渲染）。
  blank;

  /// 序列化为字符串。
  String toJson() => name;

  /// 反序列化，未知值降级为 [typeDefault]。
  static LoadingStrategy fromJson(Object? value) {
    if (value is LoadingStrategy) return value;
    if (value is String) {
      return LoadingStrategy.values.firstWhere(
        (e) => e.name == value,
        orElse: () => LoadingStrategy.typeDefault,
      );
    }
    return LoadingStrategy.typeDefault;
  }
}

/// UI 属性绑定（UI 段的 IR 元素）。
///
/// 将 UI 节点的某个属性绑定到一个变量引用，实现 UI 与数据联动。
/// 绑定的 [ref] 可引用项目变量 / 组件上下文变量 / 函数变量 / 上游节点输出。
///
/// 当 [ref] 指向函数变量或组件上下文变量时，可能因时间线或容器渲染
/// 时机未就绪，由 [loadingStrategy] 决定占位行为，避免用户手动处理。
class Binding {
  /// 绑定的变量引用。
  final VariableRef ref;

  /// 加载态策略（默认 [LoadingStrategy.typeDefault]）。
  final LoadingStrategy loadingStrategy;

  /// 占位文字（仅 [LoadingStrategy.placeholder] 时使用）。
  final String? placeholderText;

  const Binding({
    required this.ref,
    this.loadingStrategy = LoadingStrategy.typeDefault,
    this.placeholderText,
  });

  /// 向后兼容构造：仅 ref，默认 typeDefault 策略。
  factory Binding.fromRef(VariableRef ref) => Binding(ref: ref);

  Binding copyWith({
    VariableRef? ref,
    LoadingStrategy? loadingStrategy,
    Object? placeholderText = _sentinel,
  }) =>
      Binding(
        ref: ref ?? this.ref,
        loadingStrategy: loadingStrategy ?? this.loadingStrategy,
        placeholderText: identical(placeholderText, _sentinel)
            ? this.placeholderText
            : placeholderText as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Binding &&
          ref == other.ref &&
          loadingStrategy == other.loadingStrategy &&
          placeholderText == other.placeholderText;

  @override
  int get hashCode => Object.hash(ref, loadingStrategy, placeholderText);

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'ref': ref.toJson()};
    if (loadingStrategy != LoadingStrategy.typeDefault) {
      json['loadingStrategy'] = loadingStrategy.toJson();
    }
    if (placeholderText != null) json['placeholderText'] = placeholderText;
    return json;
  }

  factory Binding.fromJson(Map<String, dynamic> json) => Binding(
        ref: VariableRef.fromJson(json['ref'] as Map<String, dynamic>),
        loadingStrategy: LoadingStrategy.fromJson(json['loadingStrategy']),
        placeholderText: json['placeholderText'] as String?,
      );

  @override
  String toString() =>
      'Binding($ref, $loadingStrategy${placeholderText != null ? ', "$placeholderText"' : ''})';
}

// ============================================================================
// 布局系统：双模布局（9宫格相对布局 + 绝对布局）
// ============================================================================

/// 尺寸单位。
enum SizeUnit {
  /// 百分比（相对父容器）。
  percent,

  /// 像素（绝对像素值）。
  px;

  /// 序列化为字符串。
  String toJson() => name;

  /// 反序列化，未知值降级为 [px]。
  static SizeUnit fromJson(Object? value) {
    if (value is SizeUnit) return value;
    if (value is String) {
      return SizeUnit.values.firstWhere(
        (e) => e.name == value,
        orElse: () => SizeUnit.px,
      );
    }
    return SizeUnit.px;
  }
}

/// 尺寸规范（宽/高）。
///
/// [minPx] / [maxPx] 仅在 [unit] == [SizeUnit.percent] 时生效，
/// 用于约束百分比换算后的像素值范围。
class SizeSpec {
  final double value;
  final SizeUnit unit;
  final double? minPx;
  final double? maxPx;

  const SizeSpec({
    required this.value,
    this.unit = SizeUnit.px,
    this.minPx,
    this.maxPx,
  });

  SizeSpec copyWith({
    double? value,
    SizeUnit? unit,
    Object? minPx = _sentinel,
    Object? maxPx = _sentinel,
  }) =>
      SizeSpec(
        value: value ?? this.value,
        unit: unit ?? this.unit,
        minPx: identical(minPx, _sentinel) ? this.minPx : minPx as double?,
        maxPx: identical(maxPx, _sentinel) ? this.maxPx : maxPx as double?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SizeSpec &&
          value == other.value &&
          unit == other.unit &&
          minPx == other.minPx &&
          maxPx == other.maxPx;

  @override
  int get hashCode => Object.hash(value, unit, minPx, maxPx);

  Map<String, dynamic> toJson() => {
        'value': value,
        'unit': unit.toJson(),
        if (minPx != null) 'minPx': minPx,
        if (maxPx != null) 'maxPx': maxPx,
      };

  factory SizeSpec.fromJson(Map<String, dynamic> json) => SizeSpec(
        value: (json['value'] as num).toDouble(),
        unit: SizeUnit.fromJson(json['unit']),
        minPx: (json['minPx'] as num?)?.toDouble(),
        maxPx: (json['maxPx'] as num?)?.toDouble(),
      );

  @override
  String toString() =>
      'SizeSpec($value$unit${minPx != null ? ', min=$minPx' : ''}${maxPx != null ? ', max=$maxPx' : ''})';
}

/// 边距值（单方向）。
class EdgeValue {
  final double value;
  final SizeUnit unit;

  const EdgeValue({
    required this.value,
    this.unit = SizeUnit.px,
  });

  EdgeValue copyWith({
    double? value,
    SizeUnit? unit,
  }) =>
      EdgeValue(
        value: value ?? this.value,
        unit: unit ?? this.unit,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeValue && value == other.value && unit == other.unit;

  @override
  int get hashCode => Object.hash(value, unit);

  Map<String, dynamic> toJson() => {
        'value': value,
        'unit': unit.toJson(),
      };

  factory EdgeValue.fromJson(Map<String, dynamic> json) => EdgeValue(
        value: (json['value'] as num).toDouble(),
        unit: SizeUnit.fromJson(json['unit']),
      );

  @override
  String toString() => 'EdgeValue($value$unit)';
}

/// 外间距（4 方向独立）。
class MarginSpec {
  final EdgeValue top, bottom, left, right;

  const MarginSpec({
    this.top = const EdgeValue(value: 0),
    this.bottom = const EdgeValue(value: 0),
    this.left = const EdgeValue(value: 0),
    this.right = const EdgeValue(value: 0),
  });

  MarginSpec copyWith({
    EdgeValue? top,
    EdgeValue? bottom,
    EdgeValue? left,
    EdgeValue? right,
  }) =>
      MarginSpec(
        top: top ?? this.top,
        bottom: bottom ?? this.bottom,
        left: left ?? this.left,
        right: right ?? this.right,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarginSpec &&
          top == other.top &&
          bottom == other.bottom &&
          left == other.left &&
          right == other.right;

  @override
  int get hashCode => Object.hash(top, bottom, left, right);

  Map<String, dynamic> toJson() => {
        'top': top.toJson(),
        'bottom': bottom.toJson(),
        'left': left.toJson(),
        'right': right.toJson(),
      };

  factory MarginSpec.fromJson(Map<String, dynamic> json) => MarginSpec(
        top: EdgeValue.fromJson(json['top'] as Map<String, dynamic>),
        bottom: EdgeValue.fromJson(json['bottom'] as Map<String, dynamic>),
        left: EdgeValue.fromJson(json['left'] as Map<String, dynamic>),
        right: EdgeValue.fromJson(json['right'] as Map<String, dynamic>),
      );

  @override
  String toString() =>
      'MarginSpec(t=$top, b=$bottom, l=$left, r=$right)';
}

/// 坐标点（绝对布局用，单个 x 或 y 坐标）。
class PositionSpec {
  final double value;
  final SizeUnit unit;

  const PositionSpec({
    required this.value,
    this.unit = SizeUnit.percent,
  });

  PositionSpec copyWith({
    double? value,
    SizeUnit? unit,
  }) =>
      PositionSpec(
        value: value ?? this.value,
        unit: unit ?? this.unit,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionSpec && value == other.value && unit == other.unit;

  @override
  int get hashCode => Object.hash(value, unit);

  Map<String, dynamic> toJson() => {
        'value': value,
        'unit': unit.toJson(),
      };

  factory PositionSpec.fromJson(Map<String, dynamic> json) => PositionSpec(
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] == null
            ? SizeUnit.percent
            : SizeUnit.fromJson(json['unit']),
      );

  @override
  String toString() => 'PositionSpec($value$unit)';
}

/// 布局模式。
enum LayoutMode {
  /// 9 宫格相对布局。
  relative,

  /// 绝对布局（x/y 坐标）。
  absolute;

  String toJson() => name;

  static LayoutMode fromJson(Object? value) {
    if (value is LayoutMode) return value;
    if (value is String) {
      return LayoutMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => LayoutMode.relative,
      );
    }
    return LayoutMode.relative;
  }
}

/// 9 宫格位置（1-9）。
///
/// ```
/// 1=左上  2=上中  3=右上
/// 4=左中  5=中心  6=右中
/// 7=左下  8=下中  9=右下
/// ```
class GridCell {
  /// 宫格编号（1-9）。
  final int cell;

  const GridCell(this.cell)
      : assert(cell >= 1 && cell <= 9, 'cell 必须在 1-9 范围内');

  // ---- 便捷构造 ----
  const GridCell.topLeft() : cell = 1;
  const GridCell.topCenter() : cell = 2;
  const GridCell.topRight() : cell = 3;
  const GridCell.centerLeft() : cell = 4;
  const GridCell.center() : cell = 5;
  const GridCell.centerRight() : cell = 6;
  const GridCell.bottomLeft() : cell = 7;
  const GridCell.bottomCenter() : cell = 8;
  const GridCell.bottomRight() : cell = 9;

  GridCell copyWith({int? cell}) => GridCell(cell ?? this.cell);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GridCell && cell == other.cell;

  @override
  int get hashCode => cell;

  Map<String, dynamic> toJson() => {'cell': cell};

  factory GridCell.fromJson(Map<String, dynamic> json) =>
      GridCell((json['cell'] as num).toInt());

  @override
  String toString() => 'GridCell($cell)';
}

/// 布局配置。
///
/// 双模布局：
/// - [mode] == [LayoutMode.relative]：使用 [cell] 定位。[cell] 决定对齐与排列
///   方式（列=对齐：左/中/右；行=排列方向：上→下 / 水平 / 下→上），无"距边距离"
///   概念，组件按 children 列表顺序在所属 cell 内堆叠。
/// - [mode] == [LayoutMode.absolute]：使用 [x] / [y] 坐标定位。
///
/// [width] / [height] 在两种模式下都必填。[margin] 为 4 方向外间距。
class LayoutConfig {
  final LayoutMode mode;
  final GridCell? cell;
  final PositionSpec? x;
  final PositionSpec? y;
  final SizeSpec width;
  final SizeSpec height;
  final MarginSpec margin;

  const LayoutConfig({
    this.mode = LayoutMode.relative,
    this.cell,
    this.x,
    this.y,
    required this.width,
    required this.height,
    this.margin = const MarginSpec(),
  });

  LayoutConfig copyWith({
    LayoutMode? mode,
    Object? cell = _sentinel,
    Object? x = _sentinel,
    Object? y = _sentinel,
    SizeSpec? width,
    SizeSpec? height,
    MarginSpec? margin,
  }) =>
      LayoutConfig(
        mode: mode ?? this.mode,
        cell: identical(cell, _sentinel) ? this.cell : cell as GridCell?,
        x: identical(x, _sentinel) ? this.x : x as PositionSpec?,
        y: identical(y, _sentinel) ? this.y : y as PositionSpec?,
        width: width ?? this.width,
        height: height ?? this.height,
        margin: margin ?? this.margin,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutConfig &&
          mode == other.mode &&
          cell == other.cell &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          margin == other.margin;

  @override
  int get hashCode =>
      Object.hash(mode, cell, x, y, width, height, margin);

  Map<String, dynamic> toJson() => {
        'mode': mode.toJson(),
        if (cell != null) 'cell': cell!.toJson(),
        if (x != null) 'x': x!.toJson(),
        if (y != null) 'y': y!.toJson(),
        'width': width.toJson(),
        'height': height.toJson(),
        'margin': margin.toJson(),
      };

  factory LayoutConfig.fromJson(Map<String, dynamic> json) => LayoutConfig(
        mode: LayoutMode.fromJson(json['mode']),
        cell: json['cell'] == null
            ? null
            : GridCell.fromJson(json['cell'] as Map<String, dynamic>),
        x: json['x'] == null
            ? null
            : PositionSpec.fromJson(json['x'] as Map<String, dynamic>),
        y: json['y'] == null
            ? null
            : PositionSpec.fromJson(json['y'] as Map<String, dynamic>),
        width: SizeSpec.fromJson(json['width'] as Map<String, dynamic>),
        height: SizeSpec.fromJson(json['height'] as Map<String, dynamic>),
        margin: json['margin'] == null
            ? const MarginSpec()
            : MarginSpec.fromJson(json['margin'] as Map<String, dynamic>),
      );

  @override
  String toString() => 'LayoutConfig($mode, cell=$cell, '
      '${x != null ? 'x=$x' : ''}${y != null ? ', y=$y' : ''}, '
      '$width×$height, margin=$margin)';
}

// ============================================================================
// 动画系统
// ============================================================================

/// 动画触发类型。
enum AnimationTriggerType {
  /// 入场动画（节点首次渲染时播放）。
  entrance,

  /// 出场动画（节点被移除时播放）。
  exit,

  /// 事件触发动画（由用户事件触发）。
  triggered;

  String toJson() => name;

  static AnimationTriggerType fromJson(Object? value) {
    if (value is AnimationTriggerType) return value;
    if (value is String) {
      return AnimationTriggerType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AnimationTriggerType.entrance,
      );
    }
    return AnimationTriggerType.entrance;
  }
}

/// 预设动画名。
enum AnimationPreset {
  fade,
  slide,
  scale,
  bounce,
  rotate,
  elastic;

  String toJson() => name;

  static AnimationPreset fromJson(Object? value) {
    if (value is AnimationPreset) return value;
    if (value is String) {
      return AnimationPreset.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AnimationPreset.fade,
      );
    }
    return AnimationPreset.fade;
  }
}

/// 缓动曲线类型。
enum EasingType {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  bounce,
  elastic;

  String toJson() => name;

  static EasingType fromJson(Object? value) {
    if (value is EasingType) return value;
    if (value is String) {
      return EasingType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => EasingType.linear,
      );
    }
    return EasingType.linear;
  }
}

/// 关键帧属性（某一时刻的变换状态）。
///
/// 所有字段均为可选，未设置的字段表示该属性在该关键帧不变化。
class KeyframeProperties {
  final double? x;
  final double? y;
  final double? opacity;
  final double? scale;
  final double? rotation;

  const KeyframeProperties({
    this.x,
    this.y,
    this.opacity,
    this.scale,
    this.rotation,
  });

  KeyframeProperties copyWith({
    Object? x = _sentinel,
    Object? y = _sentinel,
    Object? opacity = _sentinel,
    Object? scale = _sentinel,
    Object? rotation = _sentinel,
  }) =>
      KeyframeProperties(
        x: identical(x, _sentinel) ? this.x : x as double?,
        y: identical(y, _sentinel) ? this.y : y as double?,
        opacity:
            identical(opacity, _sentinel) ? this.opacity : opacity as double?,
        scale: identical(scale, _sentinel) ? this.scale : scale as double?,
        rotation: identical(rotation, _sentinel)
            ? this.rotation
            : rotation as double?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyframeProperties &&
          x == other.x &&
          y == other.y &&
          opacity == other.opacity &&
          scale == other.scale &&
          rotation == other.rotation;

  @override
  int get hashCode => Object.hash(x, y, opacity, scale, rotation);

  Map<String, dynamic> toJson() => {
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (opacity != null) 'opacity': opacity,
        if (scale != null) 'scale': scale,
        if (rotation != null) 'rotation': rotation,
      };

  factory KeyframeProperties.fromJson(Map<String, dynamic> json) =>
      KeyframeProperties(
        x: (json['x'] as num?)?.toDouble(),
        y: (json['y'] as num?)?.toDouble(),
        opacity: (json['opacity'] as num?)?.toDouble(),
        scale: (json['scale'] as num?)?.toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble(),
      );

  @override
  String toString() =>
      'KeyframeProperties(x=$x, y=$y, opacity=$opacity, scale=$scale, rotation=$rotation)';
}

/// 关键帧（动画时间轴上的一个点）。
///
/// [time] 为 0-1 的归一化时间点；[easing] 为到下一帧的缓动曲线。
class Keyframe {
  final double time;
  final KeyframeProperties properties;
  final EasingType easing;

  const Keyframe({
    required this.time,
    required this.properties,
    this.easing = EasingType.linear,
  });

  Keyframe copyWith({
    double? time,
    KeyframeProperties? properties,
    EasingType? easing,
  }) =>
      Keyframe(
        time: time ?? this.time,
        properties: properties ?? this.properties,
        easing: easing ?? this.easing,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Keyframe &&
          time == other.time &&
          properties == other.properties &&
          easing == other.easing;

  @override
  int get hashCode => Object.hash(time, properties, easing);

  Map<String, dynamic> toJson() => {
        'time': time,
        'properties': properties.toJson(),
        'easing': easing.toJson(),
      };

  factory Keyframe.fromJson(Map<String, dynamic> json) => Keyframe(
        time: (json['time'] as num).toDouble(),
        properties: KeyframeProperties.fromJson(
            json['properties'] as Map<String, dynamic>),
        easing: EasingType.fromJson(json['easing']),
      );

  @override
  String toString() => 'Keyframe(t=$time, $properties, $easing)';
}

/// 动画规范（预设动画或关键帧动画，二选一）。
///
/// - [preset] 非空时使用预设动画（[keyframes] 应为空）。
/// - [keyframes] 非空时使用关键帧动画（[preset] 应为空）。
/// - [duration] / [delay] 单位为毫秒。
/// - [easing] 仅在预设动画时使用；关键帧动画的缓动由各 [Keyframe.easing] 决定。
/// - [params] 为预设动画参数（如 slide 的方向）。
class AnimationSpec {
  final AnimationPreset? preset;
  final List<Keyframe> keyframes;
  final double duration;
  final double delay;
  final EasingType easing;
  final Map<String, dynamic> params;

  const AnimationSpec({
    this.preset,
    this.keyframes = const [],
    this.duration = 300,
    this.delay = 0,
    this.easing = EasingType.easeInOut,
    this.params = const {},
  });

  AnimationSpec copyWith({
    Object? preset = _sentinel,
    List<Keyframe>? keyframes,
    double? duration,
    double? delay,
    EasingType? easing,
    Map<String, dynamic>? params,
  }) =>
      AnimationSpec(
        preset: identical(preset, _sentinel)
            ? this.preset
            : preset as AnimationPreset?,
        keyframes: keyframes ?? this.keyframes,
        duration: duration ?? this.duration,
        delay: delay ?? this.delay,
        easing: easing ?? this.easing,
        params: params ?? this.params,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimationSpec &&
          preset == other.preset &&
          _uiDeepEq.equals(keyframes, other.keyframes) &&
          duration == other.duration &&
          delay == other.delay &&
          easing == other.easing &&
          _uiDeepEq.equals(params, other.params);

  @override
  int get hashCode =>
      Object.hash(preset, Object.hashAll(keyframes), duration, delay, easing);

  Map<String, dynamic> toJson() => {
        if (preset != null) 'preset': preset!.toJson(),
        if (keyframes.isNotEmpty)
          'keyframes': keyframes.map((e) => e.toJson()).toList(),
        'duration': duration,
        'delay': delay,
        'easing': easing.toJson(),
        if (params.isNotEmpty) 'params': params,
      };

  factory AnimationSpec.fromJson(Map<String, dynamic> json) => AnimationSpec(
        preset: json['preset'] == null
            ? null
            : AnimationPreset.fromJson(json['preset']),
        keyframes: (json['keyframes'] as List<dynamic>?)
                ?.map((e) => Keyframe.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        duration: (json['duration'] as num?)?.toDouble() ?? 300,
        delay: (json['delay'] as num?)?.toDouble() ?? 0,
        easing: EasingType.fromJson(json['easing']),
        params: (json['params'] as Map<String, dynamic>?) ?? const {},
      );

  @override
  String toString() =>
      'AnimationSpec(preset=$preset, ${keyframes.length} keyframes, '
      '${duration}ms, delay=${delay}ms, $easing)';
}

/// 触发动画（事件 → 动画绑定）。
///
/// 将一个 UI 事件（如 onTap）绑定到一个 [AnimationSpec]，事件触发时播放动画。
class TriggeredAnimation {
  final String event;
  final AnimationSpec animation;

  const TriggeredAnimation({
    required this.event,
    required this.animation,
  });

  TriggeredAnimation copyWith({
    String? event,
    AnimationSpec? animation,
  }) =>
      TriggeredAnimation(
        event: event ?? this.event,
        animation: animation ?? this.animation,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TriggeredAnimation &&
          event == other.event &&
          animation == other.animation;

  @override
  int get hashCode => Object.hash(event, animation);

  Map<String, dynamic> toJson() => {
        'event': event,
        'animation': animation.toJson(),
      };

  factory TriggeredAnimation.fromJson(Map<String, dynamic> json) =>
      TriggeredAnimation(
        event: json['event'] as String,
        animation: AnimationSpec.fromJson(
            json['animation'] as Map<String, dynamic>),
      );

  @override
  String toString() => 'TriggeredAnimation($event -> $animation)';
}

/// 动画配置（一个节点的全部动画声明）。
///
/// - [entrance]：入场动画（节点首次渲染时自动播放）。
/// - [exit]：出场动画（节点被移除时播放）。
/// - [triggered]：事件触发动画列表（由 UI 事件驱动）。
class AnimationsConfig {
  final AnimationSpec? entrance;
  final AnimationSpec? exit;
  final List<TriggeredAnimation> triggered;

  const AnimationsConfig({
    this.entrance,
    this.exit,
    this.triggered = const [],
  });

  AnimationsConfig copyWith({
    Object? entrance = _sentinel,
    Object? exit = _sentinel,
    List<TriggeredAnimation>? triggered,
  }) =>
      AnimationsConfig(
        entrance: identical(entrance, _sentinel)
            ? this.entrance
            : entrance as AnimationSpec?,
        exit: identical(exit, _sentinel) ? this.exit : exit as AnimationSpec?,
        triggered: triggered ?? this.triggered,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimationsConfig &&
          entrance == other.entrance &&
          exit == other.exit &&
          _uiDeepEq.equals(triggered, other.triggered);

  @override
  int get hashCode =>
      Object.hash(entrance, exit, Object.hashAll(triggered));

  Map<String, dynamic> toJson() => {
        if (entrance != null) 'entrance': entrance!.toJson(),
        if (exit != null) 'exit': exit!.toJson(),
        if (triggered.isNotEmpty)
          'triggered': triggered.map((e) => e.toJson()).toList(),
      };

  factory AnimationsConfig.fromJson(Map<String, dynamic> json) =>
      AnimationsConfig(
        entrance: json['entrance'] == null
            ? null
            : AnimationSpec.fromJson(json['entrance'] as Map<String, dynamic>),
        exit: json['exit'] == null
            ? null
            : AnimationSpec.fromJson(json['exit'] as Map<String, dynamic>),
        triggered: (json['triggered'] as List<dynamic>?)
                ?.map((e) =>
                    TriggeredAnimation.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() =>
      'AnimationsConfig(entrance=$entrance, exit=$exit, '
      '${triggered.length} triggered)';
}

/// UI 树节点（UI 段的核心组成单元）。
///
/// 通过 [children] 形成无限嵌套的 UI 树；[props] 保存静态属性，
/// [bindings] 保存动态绑定（属性名 -> [Binding]）。
///
/// [pageId] 标记此节点（及其子树）所属的页面；当本节点为 Page 节点
/// （[type] == `page`）时，[pageId] 为空，节点本身即页面。
///
/// 双模布局由 [layout] 配置（9 宫格相对布局 / 绝对布局）；
/// [style] 保存组件特有样式（与 [props] 的静态属性区分，专用于视觉样式）；
/// [animations] 配置入场/出场/触发动画；[triggers] 映射事件名到函数 id。
class UiNode {
  /// 唯一标识。
  final String id;

  /// UI 类型标识（如 'page' / 'Text' / 'Column' / 'ElevatedButton'）。
  ///
  /// `page` 表示本节点是 Page 节点（特殊 UiNode，承载页面级 props 与触发）。
  final String type;

  /// 所属页面 id（标记此节点所属页面；Page 节点本身为空）。
  final String? pageId;

  /// 静态属性（组件特有参数；Page 节点存 name/route/isHome 等页面属性）。
  final Map<String, dynamic> props;

  /// 子节点列表。
  final List<UiNode> children;

  /// 属性绑定（属性名 -> 绑定）。
  final Map<String, Binding> bindings;

  /// 布局配置（双模布局：9 宫格相对 / 绝对）。
  ///
  /// 布局强制开启：新组件由 [UiMutator] 统一注入默认相对布局
  /// （2 号宫格 + 宽度 100%）。null 仅作为历史数据兼容，渲染/编辑器
  /// 会以默认相对布局为回退起点。
  final LayoutConfig? layout;

  /// 组件特有样式（视觉样式属性，与 [props] 的功能参数区分）。
  final Map<String, dynamic> style;

  /// 动画配置（入场 / 出场 / 触发动画）。
  final AnimationsConfig? animations;

  /// 事件名 → 函数 id 映射（如 `onTap` -> `func-uuid`）。
  ///
  /// Page 节点此处存生命周期触发：`onLoad` / `onDispose` / `onResume` / `onPause`。
  final Map<String, String> triggers;

  const UiNode({
    required this.id,
    required this.type,
    this.pageId,
    this.props = const {},
    this.children = const [],
    this.bindings = const {},
    this.layout,
    this.style = const {},
    this.animations,
    this.triggers = const {},
  });

  UiNode copyWith({
    String? id,
    String? type,
    Object? pageId = _sentinel,
    Map<String, dynamic>? props,
    List<UiNode>? children,
    Map<String, Binding>? bindings,
    Object? layout = _sentinel,
    Map<String, dynamic>? style,
    Object? animations = _sentinel,
    Map<String, String>? triggers,
  }) =>
      UiNode(
        id: id ?? this.id,
        type: type ?? this.type,
        pageId: identical(pageId, _sentinel)
            ? this.pageId
            : pageId as String?,
        props: props ?? this.props,
        children: children ?? this.children,
        bindings: bindings ?? this.bindings,
        layout: identical(layout, _sentinel)
            ? this.layout
            : layout as LayoutConfig?,
        style: style ?? this.style,
        animations: identical(animations, _sentinel)
            ? this.animations
            : animations as AnimationsConfig?,
        triggers: triggers ?? this.triggers,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UiNode &&
          id == other.id &&
          type == other.type &&
          pageId == other.pageId &&
          _uiDeepEq.equals(props, other.props) &&
          _uiDeepEq.equals(children, other.children) &&
          _uiDeepEq.equals(bindings, other.bindings) &&
          layout == other.layout &&
          _uiDeepEq.equals(style, other.style) &&
          animations == other.animations &&
          _uiDeepEq.equals(triggers, other.triggers);

  @override
  int get hashCode => Object.hash(
        id,
        type,
        pageId,
        children,
        bindings,
        layout,
        style,
        animations,
        triggers,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        if (pageId != null) 'pageId': pageId,
        if (props.isNotEmpty) 'props': props,
        if (children.isNotEmpty)
          'children': children.map((e) => e.toJson()).toList(),
        if (bindings.isNotEmpty)
          'bindings': bindings
              .map((key, value) => MapEntry(key, value.toJson())),
        if (layout != null) 'layout': layout!.toJson(),
        if (style.isNotEmpty) 'style': style,
        if (animations != null) 'animations': animations!.toJson(),
        if (triggers.isNotEmpty) 'triggers': triggers,
      };

  factory UiNode.fromJson(Map<String, dynamic> json) => UiNode(
        id: json['id'] as String,
        type: json['type'] as String,
        pageId: json['pageId'] as String?,
        props: (json['props'] as Map<String, dynamic>?) ?? const {},
        children: (json['children'] as List<dynamic>?)
                ?.map((e) => UiNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        bindings: (json['bindings'] as Map<String, dynamic>?)
                ?.map((key, value) => MapEntry(
                      key,
                      Binding.fromJson(value as Map<String, dynamic>),
                    )) ??
            const {},
        layout: json['layout'] == null
            ? null
            : LayoutConfig.fromJson(json['layout'] as Map<String, dynamic>),
        style: (json['style'] as Map<String, dynamic>?) ?? const {},
        animations: json['animations'] == null
            ? null
            : AnimationsConfig.fromJson(
                json['animations'] as Map<String, dynamic>),
        triggers: (json['triggers'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ??
            const {},
      );

  @override
  String toString() => 'UiNode($type#$id)';
}

const Object _sentinel = Object();
