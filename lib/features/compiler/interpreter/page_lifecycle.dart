import '../../data/models/entry.dart';
import '../../data/models/function_def.dart';
import '../../data/models/project.dart';
import 'node_interpreter.dart';
import 'runtime_scope.dart';

/// 页面生命周期管理器（T23）。
///
/// 在运行时进入/离开页面时触发对应的页面事件函数：
/// - [onPageEnter]：执行该页面下所有 `onLoad` 函数（按声明序），把 outputs
///   缓存到页面作用域（[RuntimeScope.pageFuncOutputs]），供 UI 组件 `#` 引用。
///   函数执行失败记录 error 状态但不阻塞后续函数。
/// - [onPageLeave]：执行该页面下所有 `onDispose` 函数（按声明序），不缓存 outputs
///   （页面已销毁），并清空页面作用域缓存。
///
/// 时间线规则：
/// - 函数执行前 [PageFuncEntry.state] = running，UI 引用返回加载态占位；
/// - 执行成功后 state = done，UI 引用返回缓存值；
/// - 执行失败 state = error，UI 引用返回加载态占位（不影响渲染）。
class PageLifecycleManager {
  PageLifecycleManager({
    required this.interpreter,
    required this.project,
    required this.scope,
  });

  final NodeInterpreter interpreter;
  final Project project;
  final RuntimeScope scope;

  /// 进入页面：执行 onLoad 函数并缓存 outputs。
  ///
  /// 按 [Project.functions] 声明序执行所有匹配的 onLoad 函数。
  /// 每个函数独立执行（异常不影响后续），outputs 缓存到 [scope]。
  Future<void> onPageEnter(String pageId) async {
    final onLoadFns = _findPageEventFunctions(pageId, PageEventName.onLoad);
    for (final fn in onLoadFns) {
      await _runPageFuncAndCache(fn);
    }
  }

  /// 离开页面：执行 onDispose 函数（不缓存），然后清空页面作用域。
  Future<void> onPageLeave(String pageId) async {
    final onDisposeFns =
        _findPageEventFunctions(pageId, PageEventName.onDispose);
    for (final fn in onDisposeFns) {
      // onDispose 函数的返回值不缓存（页面已销毁）。
      try {
        await interpreter.runFunction(fn, const {});
      } catch (_) {
        // 卸载函数失败不阻塞后续，也不影响页面销毁。
      }
    }
    // 清空页面作用域缓存（页面已销毁，outputs 不再可见）。
    scope.clearPageFuncOutputs();
  }

  /// 恢复页面（从后台切回）：执行 onResume 函数。
  Future<void> onPageResume(String pageId) async {
    final fns = _findPageEventFunctions(pageId, PageEventName.onResume);
    for (final fn in fns) {
      await _runPageFuncAndCache(fn);
    }
  }

  /// 暂停页面（切到后台）：执行 onPause 函数。
  Future<void> onPagePause(String pageId) async {
    final fns = _findPageEventFunctions(pageId, PageEventName.onPause);
    for (final fn in fns) {
      try {
        await interpreter.runFunction(fn, const {});
      } catch (_) {
        // 暂停函数失败不阻塞。
      }
    }
  }

  /// 查找页面下指定事件的函数（按 [Project.functions] 声明序）。
  List<FunctionDef> _findPageEventFunctions(String pageId, String event) {
    return project.functions.where((f) {
      final entry = f.entry;
      return entry != null && entry.matchesPageEvent(pageId, event);
    }).toList(growable: false);
  }

  /// 执行页面函数并缓存 outputs 到 [scope]。
  ///
  /// 状态机：
  /// - 执行前设 running（UI 引用返回加载态）；
  /// - 成功后设 done + outputs（UI 引用返回缓存值）；
  /// - 失败设 error（UI 引用返回加载态）。
  Future<void> _runPageFuncAndCache(FunctionDef fn) async {
    // 标记 running（时间线：UI 引用此时返回加载态占位）。
    scope.setPageFuncEntry(
        fn.id, const PageFuncEntry(state: PageFuncState.running));
    try {
      final result = await interpreter.runFunction(fn, const {});
      if (result.error != null) {
        scope.setPageFuncEntry(fn.id,
            PageFuncEntry(state: PageFuncState.error, error: result.error));
      } else {
        scope.setPageFuncEntry(fn.id,
            PageFuncEntry(outputs: result.outputs, state: PageFuncState.done));
      }
    } catch (e) {
      scope.setPageFuncEntry(fn.id,
          PageFuncEntry(state: PageFuncState.error, error: '$e'));
    }
  }
}
