/// JS 运行时条件导出。
///
/// - IO 平台（Android/iOS/Desktop）：使用 flutter_js 提供的 QuickJS /
///   JavaScriptCore 引擎隔离执行 JS。
/// - Web 平台：使用浏览器原生 eval（通过 Function 构造器在局部作用域执行）。
export 'js_runtime_stub.dart'
    if (dart.library.io) 'js_runtime_io.dart'
    if (dart.library.html) 'js_runtime_web.dart'
    if (dart.library.js_interop) 'js_runtime_web.dart';
