import 'package:collection/collection.dart';

import 'db_schema.dart';
import 'folder.dart';
import 'function_def.dart';
import 'page.dart';
import 'project_variable.dart';
import 'ui_tree.dart';

const DeepCollectionEquality _projDeepEq = DeepCollectionEquality();

/// 项目元数据。
class ProjectMeta {
  /// 唯一标识。
  final String id;

  /// 项目名。
  final String name;

  /// 描述。
  final String? description;

  /// 创建时间（ISO8601 字符串）。
  final String createdAt;

  /// 最近更新时间（ISO8601 字符串）。
  final String updatedAt;

  /// IR schema 版本（用于迁移）。
  final String version;

  const ProjectMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.version = '1',
  });

  ProjectMeta copyWith({
    String? id,
    String? name,
    String? createdAt,
    String? updatedAt,
    String? description,
    String? version,
  }) =>
      ProjectMeta(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        description: description ?? this.description,
        version: version ?? this.version,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectMeta &&
          id == other.id &&
          name == other.name &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          description == other.description &&
          version == other.version;

  @override
  int get hashCode =>
      Object.hash(id, name, createdAt, updatedAt, description, version);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'version': version,
        if (description != null) 'description': description,
      };

  factory ProjectMeta.fromJson(Map<String, dynamic> json) => ProjectMeta(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: json['createdAt'] as String,
        updatedAt: json['updatedAt'] as String,
        description: json['description'] as String?,
        version: (json['version'] as String?) ?? '1',
      );

  @override
  String toString() => 'ProjectMeta($name#$id)';
}

/// 项目根 IR 容器，聚合所有段（segment）。
///
/// 一个 [Project] 由以下段组成：
/// - [projectVars]：项目变量（`#` 作用域的项目变量来源）。
/// - [functions]：函数段（函数定义，含节点图与函数变量）。
/// - [folders]：文件夹树（组织函数，支持无限嵌套）。
/// - [db]：数据库段（表结构定义）。
/// - [pages]：页面段（命名 UI 根，承载页面级触发与页面作用域函数变量）。
/// - [ui]：UI 段（顶层 UI 节点树根，每个根可挂载到一个 [Page]）。
///
/// 双平面模型贯穿 [functions]：控制流由 [FunctionDef.controlEdges]
/// 表达，数据由节点 `#` 引用（[VariableRef]）在节点编辑页内拼装。
class Project {
  /// 项目元数据。
  final ProjectMeta meta;

  /// 项目级变量。
  final List<ProjectVariable> projectVars;

  /// 函数定义列表。
  final List<FunctionDef> functions;

  /// 文件夹列表（构成无限嵌套目录树）。
  final List<Folder> folders;

  /// 数据库表定义列表（数据库段）。
  final List<DbTable> db;

  /// 页面列表（页面段，命名 UI 根）。
  final List<Page> pages;

  /// 顶层 UI 节点列表（UI 段根节点集合，每个根可关联到一个 [Page]）。
  final List<UiNode> ui;

  const Project({
    required this.meta,
    this.projectVars = const [],
    this.functions = const [],
    this.folders = const [],
    this.db = const [],
    this.pages = const [],
    this.ui = const [],
  });

  Project copyWith({
    ProjectMeta? meta,
    List<ProjectVariable>? projectVars,
    List<FunctionDef>? functions,
    List<Folder>? folders,
    List<DbTable>? db,
    List<Page>? pages,
    List<UiNode>? ui,
  }) =>
      Project(
        meta: meta ?? this.meta,
        projectVars: projectVars ?? this.projectVars,
        functions: functions ?? this.functions,
        folders: folders ?? this.folders,
        db: db ?? this.db,
        pages: pages ?? this.pages,
        ui: ui ?? this.ui,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project &&
          meta == other.meta &&
          _projDeepEq.equals(projectVars, other.projectVars) &&
          _projDeepEq.equals(functions, other.functions) &&
          _projDeepEq.equals(folders, other.folders) &&
          _projDeepEq.equals(db, other.db) &&
          _projDeepEq.equals(pages, other.pages) &&
          _projDeepEq.equals(ui, other.ui);

  @override
  int get hashCode => Object.hash(
        meta,
        Object.hashAll(projectVars),
        Object.hashAll(functions),
        Object.hashAll(folders),
        Object.hashAll(db),
        Object.hashAll(pages),
        Object.hashAll(ui),
      );

  Map<String, dynamic> toJson() => {
        'meta': meta.toJson(),
        'projectVars': projectVars.map((e) => e.toJson()).toList(),
        'functions': functions.map((e) => e.toJson()).toList(),
        'folders': folders.map((e) => e.toJson()).toList(),
        'db': db.map((e) => e.toJson()).toList(),
        'pages': pages.map((e) => e.toJson()).toList(),
        'ui': ui.map((e) => e.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        meta: ProjectMeta.fromJson(json['meta'] as Map<String, dynamic>),
        projectVars: (json['projectVars'] as List<dynamic>?)
                ?.map((e) =>
                    ProjectVariable.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        functions: (json['functions'] as List<dynamic>?)
                ?.map((e) => FunctionDef.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        folders: (json['folders'] as List<dynamic>?)
                ?.map((e) => Folder.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        db: (json['db'] as List<dynamic>?)
                ?.map((e) => DbTable.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        pages: (json['pages'] as List<dynamic>?)
                ?.map((e) => Page.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        ui: (json['ui'] as List<dynamic>?)
                ?.map((e) => UiNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() => 'Project(${meta.name})';
}
