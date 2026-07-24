import '../../data/models/function_def.dart';

/// UI 事件触发函数的入参注入器（T24）。
///
/// 当 UI 组件事件（onTap/onChanged/onToggle 等）触发函数时，本类按事件类型
/// 与函数声明的 [FunctionDef.inputs] 构建入参 map，注入到 [NodeInterpreter.runFunction]。
///
/// 注入规则（按函数声明的 input 名匹配）：
/// - `event`：所有事件均注入 `event = {type, timestamp, componentId}`；
/// - `value`：onChanged/onSubmitted/onToggle/onChangeEnd 注入当前值；
/// - `index`：onTabChange/onItemTap 注入索引；
/// - `item`：onItemTap 注入列表项。
///
/// 未匹配的 input 使用其 defaultValue（由 [NodeInterpreter] 兜底）。
class EventInputInjector {
  EventInputInjector._();

  /// 为 UI 事件触发构建入参 map。
  ///
  /// [function]：被触发的函数（读取其 inputs 声明决定注入哪些参数）。
  /// [eventName]：事件名（onTap/onChanged/onToggle/onTabChange/onItemTap 等）。
  /// [componentId]：触发事件的组件 id（注入到 event map）。
  /// [payload]：事件载荷（onChanged 的 value / onTabChange 的 index / onItemTap 的 item+index）。
  static Map<String, dynamic> buildInputs({
    required FunctionDef function,
    required String eventName,
    required String componentId,
    EventPayload payload = const EventPayload(),
  }) {
    final inputs = <String, dynamic>{};
    final eventMap = <String, dynamic>{
      'type': eventName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'componentId': componentId,
    };
    final hasValue = payload.value != _noValue;
    final hasIndex = payload.index != _noValue;
    final hasItem = payload.item != _noValue;

    for (final param in function.inputs) {
      switch (param.name) {
        case 'event':
          inputs['event'] = eventMap;
          break;
        case 'value':
          if (hasValue) inputs['value'] = payload.value;
          break;
        case 'index':
          if (hasIndex) inputs['index'] = payload.index;
          break;
        case 'item':
          if (hasItem) inputs['item'] = payload.item;
          break;
        default:
          // 未声明的参数：不注入，由 NodeInterpreter 用 defaultValue 兜底。
          break;
      }
    }
    return inputs;
  }
}

/// 事件载荷（携带事件发生时的运行时数据）。
class EventPayload {
  /// 当前值（onChanged/onSubmitted/onToggle/onChangeEnd）。
  final Object? value;

  /// 索引（onTabChange/onItemTap）。
  final Object? index;

  /// 列表项（onItemTap）。
  final Object? item;

  const EventPayload({
    this.value = _noValue,
    this.index = _noValue,
    this.item = _noValue,
  });

  /// 构造 onChanged 载荷。
  const EventPayload.value(Object? value)
      : value = value,
        index = _noValue,
        item = _noValue;

  /// 构造 onTabChange 载荷。
  const EventPayload.index(Object? index)
      : value = _noValue,
        index = index,
        item = _noValue;

  /// 构造 onItemTap 载荷。
  const EventPayload.item({required Object? item, required Object? index})
      : value = _noValue,
        index = index,
        item = item;
}

/// 哨兵值：区分"未提供"与 null（合法的 null 值）。
const Object _noValue = Object();
