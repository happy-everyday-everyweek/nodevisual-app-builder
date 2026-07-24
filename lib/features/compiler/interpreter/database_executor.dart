import '../../../data/models/db_schema.dart';
import 'database_executor_io.dart'
    if (dart.library.html) 'database_executor_web.dart';

/// 数据库查询结果。
class DbQueryResult {
  /// 查询返回的行列表（每行为列名 -> 值的 Map）。
  final List<Map<String, Object?>> rows;

  /// 行数。
  final int count;

  const DbQueryResult({required this.rows, required this.count});
}

/// 数据库批量插入结果。
class DbBatchInsertResult {
  /// 各行插入后的主键 id 列表。
  final List<int> insertedIds;

  /// 受影响总行数。
  final int affected;

  const DbBatchInsertResult(
      {required this.insertedIds, required this.affected});
}

/// 数据库插入结果。
class DbInsertResult {
  /// 新插入行的主键 id（自增列）。
  final int insertedId;

  /// 受影响行数（插入通常为 1）。
  final int affected;

  const DbInsertResult({required this.insertedId, required this.affected});
}

/// 项目运行时数据库执行器。
///
/// 用以执行项目数据库 SQL（表来自 [Project.db] 的 schema）。
/// v1 简化：用项目 [DbTable] schema 在运行时数据库（与项目元数据索引库
/// `nodevisual.db` 隔离，名为 `nodevisual_runtime.db`）执行 CRUD 与 DDL。
///
/// [ensureSchema] 按 schema 创建表（`CREATE TABLE IF NOT EXISTS`，幂等），
/// 由 [NodeInterpreter] 在首次执行 db_* 节点前调用一次。
///
/// 平台实现：
/// - 非 Web：基于 [sqflite]（见 [database_executor_io.dart]）。
/// - Web：暂不支持，方法抛 [UnsupportedError]（见 [database_executor_web.dart]）。
abstract class DatabaseExecutor {
  Future<void> ensureSchema(List<DbTable> tables);

  Future<DbQueryResult> query(
    String table, {
    String? filter,
    int? limit,
    String? orderBy,
  });

  Future<num?> queryAggregate(
    String table, {
    required String func,
    String? column,
    String? filter,
  });

  Future<DbBatchInsertResult> insertBatch(
    String table,
    List<Map<String, Object?>> rows,
  );

  Future<DbInsertResult> insert(
    String table,
    Map<String, Object?> data,
  );

  Future<int> update(
    String table,
    String filter,
    Map<String, Object?> data,
  );

  Future<int> delete(String table, String filter);

  Future<bool> createTable(String name, List<Column> columns);

  Future<bool> alterTable(
    String table, {
    required String action,
    required String columnName,
    String? newType,
  });

  Future<void> close();
}

/// 创建 [DatabaseExecutor] 实例（平台相关）。
DatabaseExecutor createDatabaseExecutor({String? dbName}) =>
    createDatabaseExecutorImpl(dbName: dbName);
