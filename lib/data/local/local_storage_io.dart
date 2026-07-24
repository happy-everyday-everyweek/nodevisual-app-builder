import 'local_storage.dart';

/// IO 平台实现（Android / iOS / Windows / macOS / Linux）。
///
/// 使用 [SqliteLocalStorage]（基于 sqflite + path_provider）。
LocalStorage createLocalStorageImpl() => SqliteLocalStorage();
