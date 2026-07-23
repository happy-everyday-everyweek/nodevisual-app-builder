/// 函数触发方式（函数触发模型）。
///
/// 函数通过 [FunctionEntry] 声明其入口，v1 支持四类触发：
enum EntryKind {
  /// UI 事件触发（如按钮点击）。
  uiEvent,

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

/// 函数入口定义。
///
/// 描述一个函数"如何被触发"。被 [FunctionDef.entry] 引用。
/// - [kind] == [EntryKind.uiEvent]：[ref] 指向 UI 元素 id。
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
