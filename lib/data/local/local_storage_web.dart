import 'local_storage.dart';
import 'web_local_storage.dart';

/// Web 平台实现。
///
/// 使用 [SharedPreferencesLocalStorage]（基于 SharedPreferences / localStorage），
/// 因为 sqflite 与 path_provider 不支持 Web 平台。
LocalStorage createLocalStorageImpl() => SharedPreferencesLocalStorage();
