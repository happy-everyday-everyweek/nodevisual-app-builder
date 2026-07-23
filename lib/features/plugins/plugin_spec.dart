import '../../data/models/port.dart';

/// 插件配置字段类型。
///
/// [secret] 表示敏感信息（如 API Key），需经安全存储（flutter_secure_storage）
/// 持久化，UI 上以 obscureText 输入，且不会写入项目 JSON。
enum ConfigFieldType {
  /// 普通文本。
  text,

  /// 敏感文本（API Key 等），安全存储 + obscureText。
  secret,

  /// 数值。
  number,

  /// 布尔开关。
  bool;
}

/// 插件配置字段规格。
///
/// 描述插件运行所需的配置项（如 API Key、baseUrl），用于在节点编辑页
/// 渲染配置面板（[PluginConfigSheet]）并经 [PluginConfigStorage] 持久化。
class ConfigField {
  /// 配置键名（对应 config map 的 key）。
  final String key;

  /// 中文展示名。
  final String label;

  /// 字段类型。
  final ConfigFieldType type;

  /// 是否必填。
  final bool required;

  /// 默认值（缺省时按 [type] 推导）。
  final Object? defaultValue;

  const ConfigField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.defaultValue,
  });
}

/// 插件输入端口规格。
class PluginInput {
  /// 输入名（对应 inputs map 的 key）。
  final String name;

  /// 输入数据类型。
  final PortType type;

  /// 是否必填。
  final bool required;

  /// 中文描述。
  final String description;

  const PluginInput({
    required this.name,
    required this.type,
    this.required = true,
    this.description = '',
  });
}

/// 插件输出端口规格。
class PluginOutput {
  /// 输出名（对应 outputs map 的 key）。
  final String name;

  /// 输出数据类型。
  final PortType type;

  /// 中文描述。
  final String description;

  const PluginOutput({
    required this.name,
    required this.type,
    this.description = '',
  });
}

/// 插件规格（不可变）。
///
/// 集中描述一个插件的元数据、输入 / 输出端口与配置 schema，
/// 作为节点编辑页渲染、配置存储、执行调用的统一来源。
class PluginSpec {
  /// 插件唯一标识（如 `llm_openai`）。
  final String id;

  /// 中文展示名。
  final String displayName;

  /// 中文描述。
  final String description;

  /// 输入端口规格列表。
  final List<PluginInput> inputs;

  /// 输出端口规格列表。
  final List<PluginOutput> outputs;

  /// 配置字段规格列表。
  final List<ConfigField> configSchema;

  const PluginSpec({
    required this.id,
    required this.displayName,
    this.description = '',
    this.inputs = const [],
    this.outputs = const [],
    this.configSchema = const [],
  });
}

/// 流式插件事件类型。
enum PluginEventType {
  /// 增量数据（如逐 token）。
  partial,

  /// 流结束（携带最终完整结果）。
  done,

  /// 错误。
  error;
}

/// 流式插件事件。
class PluginEvent {
  /// 事件类型。
  final PluginEventType type;

  /// 事件数据（partial 为增量片段，done 为最终结果 map，error 为错误信息）。
  final Object? data;

  const PluginEvent({required this.type, this.data});

  /// 便捷构造：增量片段。
  const PluginEvent.partial(Object? data)
      : type = PluginEventType.partial,
        data = data;

  /// 便捷构造：完成（最终结果）。
  const PluginEvent.done(Map<String, dynamic> data)
      : type = PluginEventType.done,
        data = data;

  /// 便捷构造：错误。
  const PluginEvent.error(Object? data)
      : type = PluginEventType.error,
        data = data;
}

/// 插件执行器抽象类。
///
/// 接收插件规格、输入 map 与配置 map，返回输出 map。
/// 实现方负责实际的 HTTP / 本地调用与错误处理。
abstract class PluginExecutor {
  /// 执行插件。
  ///
  /// [spec] 为插件规格（提供输入 / 输出声明）；[inputs] 为运行时输入值；
  /// [config] 为持久化的配置（含 API Key 等）。
  ///
  /// 返回的 map 键应与 [PluginSpec.outputs] 的 name 对齐。
  /// 非 200 / 网络错误 / 解析失败时应抛出带可读信息的异常。
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  );
}

/// 流式插件执行器抽象类（可选，支持流式输出）。
///
/// 用于 LLM 等逐 token 输出场景。未实现流式的插件可不实现本接口，
/// 调用方回退到 [PluginExecutor.execute]。
abstract class StreamPluginExecutor {
  /// 以流式执行插件。
  ///
  /// 依次 emit：
  /// - [PluginEventType.partial]：增量片段（如逐 token 文本）；
  /// - [PluginEventType.done]：最终完整结果 map（含 content / usage_tokens）；
  /// - [PluginEventType.error]：错误（之后流结束）。
  Stream<PluginEvent> executeStream(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  );
}
