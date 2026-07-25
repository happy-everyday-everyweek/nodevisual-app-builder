import 'package:flutter_js/flutter_js.dart';

import 'js_runtime_stub.dart';

/// 包装 flutter_js 的 JsEvalResult，使其符合 [JsRuntimeResult] 接口。
class _FlutterJsRuntimeResult implements JsRuntimeResult {
  _FlutterJsRuntimeResult(this._result);

  final JsEvalResult _result;

  @override
  Object? get rawResult => _result.rawResult;
}

/// IO 平台 JS 运行时实现（基于 flutter_js / QuickJS / JavaScriptCore）。
class _FlutterJsRuntime implements JsRuntime {
  final JavascriptRuntime _runtime = getJavascriptRuntime();

  @override
  JsRuntimeResult evaluate(String code) {
    return _FlutterJsRuntimeResult(_runtime.evaluate(code));
  }

  @override
  void dispose() => _runtime.dispose();
}

/// 创建 IO 平台 JS 运行时实例。
JsRuntime createJsRuntime() => _FlutterJsRuntime();
