import 'dart:convert';

import '../../data/models/port.dart';
import '../plugins/plugin_spec.dart';
import 'ui_component_def.dart';

/// 插件清单（插件源仓库根目录 `plugin.json`）。
///
/// 完整描述一个市场插件的元数据、输入/输出端口、配置 schema 与
/// 执行器定义。安装时从插件仓库下载此文件并持久化，
/// 运行时由 [HttpPluginExecutor] 解释执行（HTTP 类型）或
/// 从内置 native 执行器注册表查找（native 类型），或由
/// [FunctionPluginExecutor] 解释嵌入的函数 IR（function 类型）。
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

  /// HTTP 执行器定义（仅 [executorType] == 'http' 时有效）。
  final HttpExecutorDef executor;

  /// 执行器类型：'http'（默认，HTTP 模板执行器）、'native'（内置原生执行器）、
  /// 'function'（函数执行器）或 'ui_component'（UI 组件插件）。
  ///
  /// - 'http'：使用 [HttpPluginExecutor] 按 [executor] 模板渲染请求。
  /// - 'native'：从内置原生执行器注册表（id → executor 实例）查找，
  ///   用于 OpenAI / Anthropic 等需要原生 SDK 的插件。native 类型插件
  ///   仍以 manifest 形式发布到市场，但执行逻辑在客户端二进制内。
  /// - 'function'：用户通过函数编辑器将一个函数发布为插件。函数 IR
  ///   （[FunctionDef] 的 JSON）嵌入在 [functionDef] 字段中，
  ///   运行时由 [FunctionPluginExecutor] 解释执行。函数插件相比项目
  ///   内函数有限制：禁用项目变量、数据库、UI 控制、定时器/外部触发器
  ///   等依赖项目上下文的节点。
  /// - 'ui_component'：UI 组件插件，向 UI 编辑器注册一个新组件类型。
  ///   组件元数据 / 属性 / 事件 / 渲染函数 IR 嵌入在 [uiComponent] 字段中。
  ///   不参与节点编辑页的插件调用（无 PluginExecutor），仅扩展 UI 编辑器。
  ///
  /// 默认 'http' 以兼容旧 manifest（无此字段时按 HTTP 处理）。
  final String executorType;

  /// 函数执行器定义（仅 [executorType] == 'function' 时有效）。
  ///
  /// 携带嵌入的 [FunctionDef] JSON（包含节点图、控制流边、函数变量、
  /// 入参/出参签名等）。运行时 [FunctionPluginExecutor] 通过
  /// `FunctionDef.fromJson` 还原函数 IR 并用 [NodeInterpreter] 执行。
  ///
  /// 对于非 function 类型插件，此字段为 null。
  final FunctionExecutorDef? functionDef;

  /// UI 组件定义（仅 [executorType] == 'ui_component' 时有效）。
  ///
  /// 描述插件向 UI 编辑器注册的组件类型：元数据（type / 显示名 / 分类 /
  /// 图标 / 是否可容纳子节点）、属性 schema、触发事件列表、渲染函数 IR。
  /// 安装时由 [InstalledPluginsNotifier._registerOne] 转交
  /// [ComponentRegistry] 注册；UI 编辑器从注册表读取该组件以扩展
  /// 组件面板、属性面板、画布渲染。
  ///
  /// 对于非 ui_component 类型插件，此字段为 null。
  final UiComponentDef? uiComponent;

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
    this.executorType = 'http',
    this.functionDef,
    this.uiComponent,
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
      executorType: (json['executorType'] as String?) ?? 'http',
      functionDef: (json['functionDef'] as Map<String, dynamic>?) != null
          ? FunctionExecutorDef.fromJson(
              json['functionDef'] as Map<String, dynamic>)
          : null,
      uiComponent: (json['uiComponent'] as Map<String, dynamic>?) != null
          ? UiComponentDef.fromJson(
              json['uiComponent'] as Map<String, dynamic>)
          : null,
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
        'executorType': executorType,
        if (functionDef != null) 'functionDef': functionDef!.toJson(),
        if (uiComponent != null) 'uiComponent': uiComponent!.toJson(),
        'sourceRepoUrl': sourceRepoUrl,
        'installedAt': installedAt,
      };

  /// 是否为 native 执行器类型。
  bool get isNativeExecutor => executorType == 'native';

  /// 是否为 function 执行器类型（用户发布的函数插件）。
  bool get isFunctionExecutor => executorType == 'function';

  /// 是否为 UI 组件插件类型（向 UI 编辑器注册新组件）。
  bool get isUiComponent => executorType == 'ui_component';

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

/// 函数执行器定义。
///
/// 携带用户通过函数编辑器发布的函数 IR（[FunctionDef] 的 JSON 快照）。
/// 仅当 [PluginManifest.executorType] == 'function' 时使用。
///
/// 运行时 [FunctionPluginExecutor] 通过 `FunctionDef.fromJson(function)`
/// 还原函数定义，构造一个最小化的 [Project]（仅含该函数），再用
/// [NodeInterpreter] 解释执行。
class FunctionExecutorDef {
  /// 函数 IR 快照（[FunctionDef.toJson] 的输出）。
  ///
  /// 包含函数的节点图、控制流边、函数变量、入参/出参签名等完整信息。
  /// 不含项目级数据（项目变量、数据库、UI 树等），因为函数插件
  /// 禁用这些依赖项目上下文的节点。
  final Map<String, dynamic> function;

  const FunctionExecutorDef({required this.function});

  factory FunctionExecutorDef.fromJson(Map<String, dynamic> json) {
    return FunctionExecutorDef(
      function: (json['function'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {'function': function};
}
