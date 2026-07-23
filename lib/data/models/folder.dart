import 'package:collection/collection.dart';

const DeepCollectionEquality _folderDeepEq = DeepCollectionEquality();

/// 文件夹节点，通过 [parentId] 形成无限嵌套的目录树。
///
/// 文件夹用于组织函数（[FunctionDef]），不承载执行逻辑。
/// 顶层文件夹的 [parentId] 为 null。
class Folder {
  /// 唯一标识。
  final String id;

  /// 显示名称。
  final String name;

  /// 父文件夹 id；顶层为 null。
  final String? parentId;

  /// 子文件夹 id 列表（便于快速遍历，可由全量列表推导）。
  final List<String> childrenIds;

  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.childrenIds = const [],
  });

  /// 是否为顶层文件夹。
  bool get isRoot => parentId == null;

  Folder copyWith({
    String? id,
    String? name,
    String? parentId,
    List<String>? childrenIds,
  }) =>
      Folder(
        id: id ?? this.id,
        name: name ?? this.name,
        parentId: parentId ?? this.parentId,
        childrenIds: childrenIds ?? this.childrenIds,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Folder &&
          id == other.id &&
          name == other.name &&
          parentId == other.parentId &&
          _folderDeepEq.equals(childrenIds, other.childrenIds);

  @override
  int get hashCode => Object.hash(id, name, parentId, childrenIds);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (parentId != null) 'parentId': parentId,
        if (childrenIds.isNotEmpty) 'childrenIds': childrenIds,
      };

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String?,
        childrenIds: (json['childrenIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );

  @override
  String toString() => 'Folder($name${parentId != null ? ' <- $parentId' : ''})';
}
