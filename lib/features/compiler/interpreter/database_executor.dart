import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../data/models/db_schema.dart';

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

  const DbBatchInsertResult({required this.insertedIds, required this.affected});
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
/// 用 [sqflite] 执行项目数据库 SQL（表来自 [Project.db] 的 schema）。
/// v1 简化：用项目 [DbTable] schema 在运行时数据库（与项目元数据索引库
/// `nodevisual.db` 隔离，名为 `nodevisual_runtime.db`）执行 CRUD 与 DDL。
///
/// [ensureSchema] 按 schema 创建表（`CREATE TABLE IF NOT EXISTS`，幂等），
/// 由 [NodeInterpreter] 在首次执行 db_* 节点前调用一次。
class DatabaseExecutor {
  DatabaseExecutor({String? dbName})
      : _dbName = dbName ?? 'nodevisual_runtime.db';

  /// 运行时数据库文件名。
  final String _dbName;

  Database? _db;
  bool _schemaEnsured = false;

  /// 打开数据库句柄（惰性初始化）。
  Future<Database> _database() async {
    if (_db != null) return _db!;
    final docsDir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(p.join(docsDir.path, _dbName));
    return _db!;
  }

  /// 按项目 schema 创建表（`IF NOT EXISTS`，幂等）。
  ///
  /// 仅在首次调用时实际执行 DDL，后续调用直接返回（[ensureSchema] 幂等）。
  Future<void> ensureSchema(List<DbTable> tables) async {
    if (_schemaEnsured) return;
    final db = await _database();
    for (final table in tables) {
      await db.execute(_buildCreateTableSql(table));
    }
    _schemaEnsured = true;
  }

  /// 构建 `CREATE TABLE IF NOT EXISTS` SQL。
  String _buildCreateTableSql(DbTable table) {
    final cols = <String>[];
    for (final c in table.columns) {
      final buf = StringBuffer('${c.name} ${c.type}');
      if (c.primaryKey) buf.write(' PRIMARY KEY');
      if (!c.nullable) buf.write(' NOT NULL');
      cols.add(buf.toString());
    }
    return 'CREATE TABLE IF NOT EXISTS ${table.name} (${cols.join(', ')})';
  }

  /// SELECT 查询。
  ///
  /// [filter] 为 WHERE 子句字符串（不含 `WHERE` 关键字），可空。
  /// [limit] 为限制行数，可空。
  /// [orderBy] 为 ORDER BY 子句字符串（不含 `ORDER BY` 关键字），可空。
  Future<DbQueryResult> query(
    String table, {
    String? filter,
    int? limit,
    String? orderBy,
  }) async {
    final db = await _database();
    final where = filter != null && filter.isNotEmpty ? filter : null;
    final rows = await db.query(
      table,
      where: where,
      limit: limit,
      orderBy: orderBy,
    );
    return DbQueryResult(rows: rows, count: rows.length);
  }

  /// 聚合查询：执行 `SELECT func(column) FROM table WHERE filter`。
  ///
  /// [func] 支持 `count` / `sum` / `avg` / `min` / `max`。
  /// [column] 对 count 可空（`COUNT(*)`），其余必填。
  /// 返回聚合结果（count 永远返回 int，其余可能为 null 当表空时）。
  Future<num?> queryAggregate(
    String table, {
    required String func,
    String? column,
    String? filter,
  }) async {
    final db = await _database();
    final f = func.toLowerCase();
    final col = (column == null || column.isEmpty) ? '*' : column;
    final where = filter != null && filter.isNotEmpty ? filter : null;
    final rows = await db.rawQuery(
      'SELECT $f($col) AS v FROM $table${where != null ? ' WHERE $where' : ''}',
    );
    if (rows.isEmpty) return f == 'count' ? 0 : null;
    final v = rows.first['v'];
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  /// 批量插入多行。
  ///
  /// [rows] 为待插入的行列表。返回插入的 id 列表与受影响总行数。
  Future<DbBatchInsertResult> insertBatch(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    final db = await _database();
    final ids = <int>[];
    for (final row in rows) {
      final id = await db.insert(table, row);
      ids.add(id);
    }
    return DbBatchInsertResult(insertedIds: ids, affected: ids.length);
  }

  /// INSERT 一行。
  Future<DbInsertResult> insert(
    String table,
    Map<String, Object?> data,
  ) async {
    final db = await _database();
    final id = await db.insert(table, data);
    return DbInsertResult(insertedId: id, affected: id > 0 ? 1 : 0);
  }

  /// UPDATE，返回受影响行数。
  Future<int> update(
    String table,
    String filter,
    Map<String, Object?> data,
  ) async {
    final db = await _database();
    return db.update(table, data, where: filter);
  }

  /// DELETE，返回受影响行数。
  Future<int> delete(String table, String filter) async {
    final db = await _database();
    return db.delete(table, where: filter);
  }

  /// 建表 DDL。
  Future<bool> createTable(String name, List<Column> columns) async {
    final db = await _database();
    final table = DbTable(name: name, columns: columns);
    await db.execute(_buildCreateTableSql(table));
    return true;
  }

  /// 改表 DDL（v1 支持 add / rename，drop 受 SQLite 限制不支持）。
  Future<bool> alterTable(
    String table, {
    required String action,
    required String columnName,
    String? newType,
  }) async {
    final db = await _database();
    switch (action) {
      case 'add':
        if (newType == null || newType.isEmpty) {
          throw ArgumentError('alter add 操作需要 newType');
        }
        await db.execute('ALTER TABLE $table ADD COLUMN $columnName $newType');
        return true;
      case 'rename':
        if (newType == null || newType.isEmpty) {
          throw ArgumentError('alter rename 操作需要新列名（newType 字段）');
        }
        await db.execute(
          'ALTER TABLE $table RENAME COLUMN $columnName TO $newType',
        );
        return true;
      case 'drop':
        // SQLite 3.35+ 支持 DROP COLUMN，但 sqflite 不保证版本，v1 不支持。
        throw UnsupportedError('SQLite 不支持 DROP COLUMN，请重建表');
      default:
        throw ArgumentError('未知的 alter 操作: $action');
    }
  }

  /// 关闭数据库句柄。
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _schemaEnsured = false;
  }
}
