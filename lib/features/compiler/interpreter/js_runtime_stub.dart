/// JS 运行时执行结果。
abstract class JsRuntimeResult {
  Object? get rawResult;
}

/// JS 运行时抽象（由平台相关实现提供）。
abstract class JsRuntime {
  /// 执行 JS 代码并返回结果。
  JsRuntimeResult evaluate(String code);

  /// 释放运行时资源。
  void dispose();
}

/// 获取 JS 运行时实例。
JsRuntime createJsRuntime() => throw UnsupportedError(
      '当前平台不支持 JS 运行时（请在 io 或 web 平台使用）',
    );
