import 'package:collection/collection.dart';

const DeepCollectionEquality _dbDeepEq = DeepCollectionEquality();

/// 数据库表列定义（"数据库段"的 IR schema 元素）。
///
/// 注意：类名为 [Column]，与 Flutter 的 `Column` widget 同名。
/// 本模型位于 data 层，不引入 Flutter widgets，故无冲突；
/// 同时引用本类与 Flutter widgets 的文件需使用 `as` / `show` 消歧。
class Column {
  /// 列名。
  final String name;

  /// 列类型（v1 为字符串字面量，如 'TEXT' / 'INTEGER' / 'REAL'）。
  final String type;

  /// 是否为主键。
  final bool primaryKey;

  /// 是否允许为空。
  final bool nullable;

  const Column({
    required this.name,
    required this.type,
    this.primaryKey = false,
    this.nullable = true,
  });

  Column copyWith({
    String? name,
    String? type,
    bool? primaryKey,
    bool? nullable,
  }) =>
      Column(
        name: name ?? this.name,
        type: type ?? this.type,
        primaryKey: primaryKey ?? this.primaryKey,
        nullable: nullable ?? this.nullable,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Column &&
          name == other.name &&
          type == other.type &&
          primaryKey == other.primaryKey &&
          nullable == other.nullable;

  @override
  int get hashCode => Object.hash(name, type, primaryKey, nullable);

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        if (primaryKey) 'primaryKey': true,
        if (!nullable) 'nullable': false,
      };

  factory Column.fromJson(Map<String, dynamic> json) => Column(
        name: json['name'] as String,
        type: json['type'] as String,
        primaryKey: (json['primaryKey'] as bool?) ?? false,
        nullable: (json['nullable'] as bool?) ?? true,
      );

  @override
  String toString() => 'Column($name $type${primaryKey ? ' PK' : ''})';
}

/// 数据库表定义。
class DbTable {
  /// 表名。
  final String name;

  /// 列定义列表。
  final List<Column> columns;

  const DbTable({
    required this.name,
    this.columns = const [],
  });

  DbTable copyWith({
    String? name,
    List<Column>? columns,
  }) =>
      DbTable(
        name: name ?? this.name,
        columns: columns ?? this.columns,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbTable &&
          name == other.name &&
          _dbDeepEq.equals(columns, other.columns);

  @override
  int get hashCode => Object.hash(name, columns);

  Map<String, dynamic> toJson() => {
        'name': name,
        'columns': columns.map((c) => c.toJson()).toList(),
      };

  factory DbTable.fromJson(Map<String, dynamic> json) => DbTable(
        name: json['name'] as String,
        columns: (json['columns'] as List<dynamic>?)
                ?.map((e) => Column.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() => 'DbTable($name, ${columns.length} cols)';
}
