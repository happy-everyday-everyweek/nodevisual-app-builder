import 'local_storage.dart';
import 'local_storage_io.dart' if (dart.library.html) 'local_storage_web.dart';

/// 平台相关的 [LocalStorage] 工厂。
///
/// - 非 Web 平台：返回 [SqliteLocalStorage]（基于 sqflite + path_provider）。
/// - Web 平台：返回 [SharedPreferencesLocalStorage]（基于 SharedPreferences）。
LocalStorage createLocalStorage() => createLocalStorageImpl();
