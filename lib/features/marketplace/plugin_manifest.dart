import 'dart:convert';

import '../../data/models/port.dart';
import '../plugins/plugin_spec.dart';

/// 插件清单（插件源仓库根目录 `plugin.json`）。
///
/// 完整描述一个市场插件的元数据、输入/输出端口、配置 schema 与
/// HTTP 执行器模板。安装时从插件仓库下载此文件并持久化，
/// 运行时由 [HttpPluginExecutor] 解释执行。
class PluginManifest {
  /// 插件唯一标识。
  final String id;

  /// 中文展示名。
  final String displayName;

  /// 中文描述。
  final String description;

  /// 版本号。
  final String version;

  /// 作者。
  final String author;

  /// 分类。
  final String category;

  /// 输入端口规格。
  final List<ManifestInput> inputs;

  /// 输出端口规格。
  final List<ManifestOutput> outputs;

  /// 配置字段规格。
  final List<ManifestConfigField> configSchema;

  /// HTTP 执行器定义。
  final HttpExecutorDef executor;

  /// 安装来源仓库 URL。
  final String sourceRepoUrl;

  /// 安装时间（ISO8601）。
  final String installedAt;

  const PluginManifest({
    required this.id,
    required this.displayName,
    required this.description,
    required this.version,
    required this.author,
    required this.category,
    required this.inputs,
    required this.outputs,
    required this.configSchema,
    required this.executor,
    required this.sourceRepoUrl,
    required this.installedAt,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      description: (json['description'] as String?) ?? '',
      version: (json['version'] as String?) ?? '1.0.0',
      author: (json['author'] as String?) ?? 'unknown',
      category: (json['category'] as String?) ?? 'general',
      inputs: (json['inputs'] as List?)
              ?.map((e) => ManifestInput.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      outputs: (json['outputs'] as List?)
              ?.map((e) => ManifestOutput.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      configSchema: (json['configSchema'] as List?)
              ?.map((e) => ManifestConfigField.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      executor: HttpExecutorDef.fromJson(
        (json['executor'] as Map<String, dynamic>?) ?? const {},
      ),
      sourceRepoUrl: (json['sourceRepoUrl'] as String?) ?? '',
      installedAt: (json['installedAt'] as String?) ?? '',
    );
  }

  static PluginManifest parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return PluginManifest.fromJson(decoded);
    }
    throw FormatException('plugin.json 格式错误');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'description': description,
        'version': version,
        'author': author,
        'category': category,
        'inputs': inputs.map((e) => e.toJson()).toList(),
        'outputs': outputs.map((e) => e.toJson()).toList(),
        'configSchema': configSchema.map((e) => e.toJson()).toList(),
        'executor': executor.toJson(),
        'sourceRepoUrl': sourceRepoUrl,
        'installedAt': installedAt,
      };

  /// 转为 [PluginSpec]，用于注册到 [PluginRegistry]。
  PluginSpec toPluginSpec() {
    return PluginSpec(
      id: id,
      displayName: displayName,
      description: description,
      inputs: inputs
          .map((e) => PluginInput(
                name: e.name,
                type: e.type,
                required: e.required,
                description: e.description,
              ))
          .toList(),
      outputs: outputs
          .map((e) => PluginOutput(
                name: e.name,
                type: e.type,
                description: e.description,
              ))
          .toList(),
      configSchema: configSchema
          .map((e) => ConfigField(
                key: e.key,
                label: e.label,
                type: e.fieldType,
                required: e.required,
                defaultValue: e.defaultValue,
              ))
          .toList(),
    );
  }
}

/// 清单中的输入端口定义。
class ManifestInput {
  final String name;
  final PortType type;
  final bool required;
  final String description;

  const ManifestInput({
    required this.name,
    required this.type,
    this.required = true,
    this.description = '',
  });

  factory ManifestInput.fromJson(Map<String, dynamic> json) {
    return ManifestInput(
      name: json['name'] as String,
      type: PortType.fromJson(json['type'] ?? 'any'),
      required: (json['required'] as bool?) ?? true,
      description: (json['description'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.toJson(),
        'required': required,
        'description': description,
      };
}

/// 清单中的输出端口定义。
class ManifestOutput {
  final String name;
  final PortType type;
  final String description;

  const ManifestOutput({
    required this.name,
    required this.type,
    this.description = '',
  });

  factory ManifestOutput.fromJson(Map<String, dynamic> json) {
    return ManifestOutput(
      name: json['name'] as String,
      type: PortType.fromJson(json['type'] ?? 'any'),
      description: (json['description'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.toJson(),
        'description': description,
      };
}

/// 清单中的配置字段定义。
class ManifestConfigField {
  final String key;
  final String label;
  final ConfigFieldType fieldType;
  final bool required;
  final Object? defaultValue;

  const ManifestConfigField({
    required this.key,
    required this.label,
    required this.fieldType,
    this.required = false,
    this.defaultValue,
  });

  factory ManifestConfigField.fromJson(Map<String, dynamic> json) {
    return ManifestConfigField(
      key: json['key'] as String,
      label: (json['label'] as String?) ?? json['key'] as String,
      fieldType: ConfigFieldType.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? 'text'),
        orElse: () => ConfigFieldType.text,
      ),
      required: (json['required'] as bool?) ?? false,
      defaultValue: json['defaultValue'],
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': fieldType.name,
        'required': required,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };
}

/// HTTP 执行器定义。
///
/// 描述如何将输入与配置映射为 HTTP 请求，以及如何从响应中提取输出。
/// 模板变量使用 `{{inputs.xxx}}` / `{{config.xxx}}` 语法。
class HttpExecutorDef {
  /// HTTP 方法（GET / POST / PUT / DELETE）。
  final String method;

  /// URL 模板（含 {{inputs.xxx}} / {{config.xxx}} 占位符）。
  final String url;

  /// 请求头模板（值可为模板字符串）。
  final Map<String, String> headers;

  /// 请求体模板（JSON 字符串，含占位符），GET 请求可空。
  final String? body;

  /// 响应映射：输出名 → JSONPath（如 `$.data.temperature`）。
  final Map<String, String> responseMapping;

  /// 超时（毫秒）。
  final int timeoutMs;

  const HttpExecutorDef({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.responseMapping = const {},
    this.timeoutMs = 30000,
  });

  factory HttpExecutorDef.fromJson(Map<String, dynamic> json) {
    return HttpExecutorDef(
      method: (json['method'] as String?) ?? 'GET',
      url: (json['url'] as String?) ?? '',
      headers: (json['headers'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
      body: json['body'] as String?,
      responseMapping: (json['responseMapping'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
      timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 30000,
    );
  }

  Map<String, dynamic> toJson() => {
        'method': method,
        'url': url,
        'headers': headers,
        if (body != null) 'body': body,
        'responseMapping': responseMapping,
        'timeoutMs': timeoutMs,
      };
}
