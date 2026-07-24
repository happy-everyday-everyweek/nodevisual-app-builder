import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../data/models/db_schema.dart';
import 'database_executor.dart';

/// 基于 [sqflite] 的 [DatabaseExecutor] 实现（非 Web 平台）。
class SqfliteDatabaseExecutor implements DatabaseExecutor {
  SqfliteDatabaseExecutor({String? dbName})
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

  @override
  Future<void> ensureSchema(List<DbTable> tables) async {
    if (_schemaEnsured) return;
    final db = await _database();
    for (final table in tables) {
      await db.execute(_buildCreateTableSql(table));
    }
    _schemaEnsured = true;
  }

  @override
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

  @override
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

  @override
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

  @override
  Future<DbInsertResult> insert(
    String table,
    Map<String, Object?> data,
  ) async {
    final db = await _database();
    final id = await db.insert(table, data);
    return DbInsertResult(insertedId: id, affected: id > 0 ? 1 : 0);
  }

  @override
  Future<int> update(
    String table,
    String filter,
    Map<String, Object?> data,
  ) async {
    final db = await _database();
    return db.update(table, data, where: filter);
  }

  @override
  Future<int> delete(String table, String filter) async {
    final db = await _database();
    return db.delete(table, where: filter);
  }

  @override
  Future<bool> createTable(String name, List<Column> columns) async {
    final db = await _database();
    final table = DbTable(name: name, columns: columns);
    await db.execute(_buildCreateTableSql(table));
    return true;
  }

  @override
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

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _schemaEnsured = false;
  }
}

/// IO 平台实现入口（供 [database_executor.dart] 条件导入）。
DatabaseExecutor createDatabaseExecutorImpl({String? dbName}) =>
    SqfliteDatabaseExecutor(dbName: dbName);
