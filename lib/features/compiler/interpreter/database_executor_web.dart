import '../../../data/models/db_schema.dart';
import 'database_executor.dart';

/// Web 平台的 [DatabaseExecutor] 实现（暂不支持）。
///
/// Web 平台不支持 [sqflite]，所有方法抛 [UnsupportedError]。
/// 后续可通过 sql.js（SQLite wasm）或 IndexedDB 提供运行时数据库支持。
class UnsupportedDatabaseExecutor implements DatabaseExecutor {
  UnsupportedDatabaseExecutor({String? dbName});

  static const String _unsupportedMessage =
      'Web 平台暂不支持运行时数据库（sqflite 不可用）';

  @override
  Future<void> ensureSchema(List<DbTable> tables) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<DbQueryResult> query(
    String table, {
    String? filter,
    int? limit,
    String? orderBy,
  }) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<num?> queryAggregate(
    String table, {
    required String func,
    String? column,
    String? filter,
  }) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<DbBatchInsertResult> insertBatch(
    String table,
    List<Map<String, Object?>> rows,
  ) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<DbInsertResult> insert(
    String table,
    Map<String, Object?> data,
  ) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<int> update(
    String table,
    String filter,
    Map<String, Object?> data,
  ) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<int> delete(String table, String filter) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<bool> createTable(String name, List<Column> columns) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<bool> alterTable(
    String table, {
    required String action,
    required String columnName,
    String? newType,
  }) async =>
      throw UnsupportedError(_unsupportedMessage);

  @override
  Future<void> close() async {}
}

/// Web 平台实现入口（供 [database_executor.dart] 条件导入）。
DatabaseExecutor createDatabaseExecutorImpl({String? dbName}) =>
    UnsupportedDatabaseExecutor(dbName: dbName);
