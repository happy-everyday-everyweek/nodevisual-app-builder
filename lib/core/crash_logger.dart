/// 崩溃日志写入接口。
///
/// 通过条件导入在 IO 平台实现文件写入，在 Web 平台为空实现。
Future<void> writeCrashLog(String type, Object error, StackTrace? stack);
