/// 函数触发方式（函数触发模型）。
///
/// 函数通过 [FunctionEntry] 声明其入口，v1 支持五类触发：
enum EntryKind {
  /// UI 事件触发（如按钮点击）。
  uiEvent,

  /// 页面生命周期事件触发（onLoad/onDispose/onResume/onPause）。
  pageEvent,

  /// 定时器触发。
  timer,

  /// 外部触发（如推送、深度链接）。
  external,

  /// 被其他函数显式调用。
  funcCall;

  /// 序列化为字符串。
  String toJson() => name;

  /// 反序列化，未知值降级为 [uiEvent]。
  static EntryKind fromJson(Object? value) {
    if (value is EntryKind) return value;
    if (value is String) {
      return EntryKind.values.firstWhere(
        (e) => e.name == value,
        orElse: () => EntryKind.uiEvent,
      );
    }
    return EntryKind.uiEvent;
  }
}

/// 页面生命周期事件名（仅 [EntryKind.pageEvent] 使用）。
class PageEventName {
  /// 页面加载（进入页面，DOM 挂载完成后触发）。
  static const String onLoad = 'onLoad';

  /// 页面卸载（离开页面，DOM 销毁前触发）。
  static const String onDispose = 'onDispose';

  /// 页面恢复（从后台切回前台 / 从下层路由返回）。
  static const String onResume = 'onResume';

  /// 页面暂停（切到后台 / 进入下层路由）。
  static const String onPause = 'onPause';

  /// 所有合法页面事件名（用于校验）。
  static const List<String> all = [
    onLoad,
    onDispose,
    onResume,
    onPause,
  ];

  /// 判断 [name] 是否为合法的页面事件名。
  static bool isValid(String? name) =>
      name != null && all.contains(name);

  /// 私有构造，禁止实例化。
  PageEventName._();
}

/// 函数入口定义。
///
/// 描述一个函数"如何被触发"。被 [FunctionDef.entry] 引用。
/// - [kind] == [EntryKind.uiEvent]：[ref] 指向 UI 元素 id。
/// - [kind] == [EntryKind.pageEvent]：[ref] 形如 `<pageId>:<event>`，
///   event ∈ [PageEventName.all]（onLoad/onDispose/onResume/onPause）。
/// - [kind] == [EntryKind.timer]：[ref] 指向定时器配置 id 或表达式。
/// - [kind] == [EntryKind.external]：[ref] 指向外部事件标识。
/// - [kind] == [EntryKind.funcCall]：[ref] 为空（由调用方决定）。
class FunctionEntry {
  /// 触发类型。
  final EntryKind kind;

  /// 触发引用（语义随 [kind] 变化）。
  final String? ref;

  const FunctionEntry({
    required this.kind,
    this.ref,
  });

  FunctionEntry copyWith({EntryKind? kind, String? ref}) => FunctionEntry(
        kind: kind ?? this.kind,
        ref: ref ?? this.ref,
      );

  /// 便捷构造：页面事件入口。
  ///
  /// [pageId] 为页面 id，[event] 应 ∈ [PageEventName.all]。
  factory FunctionEntry.pageEvent({
    required String pageId,
    required String event,
  }) {
    return FunctionEntry(
      kind: EntryKind.pageEvent,
      ref: '$pageId:$event',
    );
  }

  /// 当 [kind] == [EntryKind.pageEvent] 时，解析 ref 得到 pageId。
  /// 其他 kind 或格式不合法时返回 null。
  String? get pageId {
    if (kind != EntryKind.pageEvent || ref == null) return null;
    final idx = ref!.indexOf(':');
    if (idx <= 0) return null;
    return ref!.substring(0, idx);
  }

  /// 当 [kind] == [EntryKind.pageEvent] 时，解析 ref 得到 event。
  /// 其他 kind 或格式不合法时返回 null。
  String? get pageEvent {
    if (kind != EntryKind.pageEvent || ref == null) return null;
    final idx = ref!.indexOf(':');
    if (idx < 0 || idx == ref!.length - 1) return null;
    final event = ref!.substring(idx + 1);
    return PageEventName.isValid(event) ? event : null;
  }

  /// 判断此入口是否匹配指定的页面事件。
  bool matchesPageEvent(String pageId, String event) {
    return kind == EntryKind.pageEvent &&
        ref != null &&
        ref == '$pageId:$event';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionEntry && kind == other.kind && ref == other.ref;

  @override
  int get hashCode => Object.hash(kind, ref);

  Map<String, dynamic> toJson() => {
        'kind': kind.toJson(),
        if (ref != null) 'ref': ref,
      };

  factory FunctionEntry.fromJson(Map<String, dynamic> json) => FunctionEntry(
        kind: EntryKind.fromJson(json['kind']),
        ref: json['ref'] as String?,
      );

  @override
  String toString() => 'FunctionEntry($kind${ref != null ? ': $ref' : ''})';
}
