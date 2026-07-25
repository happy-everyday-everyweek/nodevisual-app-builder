import 'js_runtime_stub.dart';

/// Web 平台 JS 运行时结果（简单包装）。
class _WebJsRuntimeResult implements JsRuntimeResult {
  _WebJsRuntimeResult(this.rawResult);

  @override
  final Object? rawResult;
}

/// Web 平台 JS 运行时实现。
///
/// v1 使用浏览器原生 `eval` 执行 JS 代码（运行在 isolating 的函数作用域内，
/// 通过 Function 构造器避免污染全局）。这足以支持 `code_run` 节点在 Web
/// 预览/运行时执行简单 JS 逻辑。
class _WebJsRuntime implements JsRuntime {
  @override
  JsRuntimeResult evaluate(String code) {
    // 使用 Function 构造器在局部作用域执行代码，避免污染 window。
    // 代码可通过 `inputs` 访问传入的 inputs 全局变量。
    final fn = Function(code);
    final result = fn();
    return _WebJsRuntimeResult(result);
  }

  @override
  void dispose() {
    // Web 平台无显式资源需要释放。
  }
}

/// 创建 Web 平台 JS 运行时实例。
JsRuntime createJsRuntime() => _WebJsRuntime();
