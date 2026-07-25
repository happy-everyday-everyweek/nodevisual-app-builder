import 'dart:js_util' as js_util;

import 'js_runtime_stub.dart';

/// Web 平台 JS 运行时结果（简单包装）。
class _WebJsRuntimeResult implements JsRuntimeResult {
  _WebJsRuntimeResult(this.rawResult);

  @override
  final Object? rawResult;
}

/// Web 平台 JS 运行时实现。
///
/// v1 使用浏览器原生 `eval` 执行 JS 代码。代码通过 `inputs` 全局变量访问输入，
/// eval 返回最后一条表达式的求值结果。
class _WebJsRuntime implements JsRuntime {
  @override
  JsRuntimeResult evaluate(String code) {
    final result = js_util.callMethod(js_util.globalThis, 'eval', [code]);
    return _WebJsRuntimeResult(result);
  }

  @override
  void dispose() {
    // Web 平台无显式资源需要释放。
  }
}

/// 创建 Web 平台 JS 运行时实例。
JsRuntime createJsRuntime() => _WebJsRuntime();
