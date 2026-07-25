import 'dart:async';
import 'dart:convert';

import 'package:dart_openai/dart_openai.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/port.dart';
import '../plugin_spec.dart';

/// OpenAI Chat Completions 插件规格。
///
/// id: `llm_openai`；输入 messages(list) / model(text) / temperature(number)；
/// 输出 content(string) / usage_tokens(number)；配置 apiKey(secret) +
/// baseUrl(text，默认 https://api.openai.com)。
const PluginSpec openAiPluginSpec = PluginSpec(
  id: 'llm_openai',
  displayName: 'OpenAI LLM',
  description: '调用 OpenAI Chat Completions 接口生成文本，支持流式输出。',
  inputs: [
    PluginInput(
      name: 'messages',
      type: PortType.list,
      required: true,
      description: '消息列表，形如 [{"role":"user","content":"你好"}]',
    ),
    PluginInput(
      name: 'model',
      type: PortType.string,
      required: true,
      description: '模型名，如 gpt-4o-mini',
    ),
    PluginInput(
      name: 'temperature',
      type: PortType.number,
      required: false,
      description: '采样温度，0~2，默认 0.7',
    ),
  ],
  outputs: [
    PluginOutput(name: 'content', type: PortType.string, description: '生成的文本'),
    PluginOutput(name: 'usage_tokens', type: PortType.number, description: '总 token 数'),
  ],
  configSchema: [
    ConfigField(
      key: 'apiKey',
      label: 'API Key',
      type: ConfigFieldType.secret,
      required: true,
    ),
    ConfigField(
      key: 'baseUrl',
      label: 'Base URL',
      type: ConfigFieldType.text,
      required: false,
      defaultValue: 'https://api.openai.com',
    ),
  ],
);

/// 全局调用串行锁。
///
/// dart_openai 的 apiKey / baseUrl 为全局静态字段（[OpenAI.apiKey] /
/// [OpenAI.baseUrl]），与本插件"每次 execute 按 config 注入"的 per-call 模型
/// 不匹配。通过此锁将所有 SDK 调用串行化，确保每次调用期间全局配置不被
/// 并发调用覆盖。序列化会牺牲一定并发度，但节点编辑器场景下 OpenAI 调用
/// 频率低，可接受。
Future<void> _openAiSdkLock = Future<void>.value();

/// 在串行锁保护下执行 action。
Future<T> _withSdkLock<T>(Future<T> Function() action) {
  final prev = _openAiSdkLock;
  final completer = Completer<void>();
  _openAiSdkLock = completer.future;
  return prev.then((_) => action()).whenComplete(completer.complete);
}

/// OpenAI 执行器（基于 dart_openai 官方 SDK）。
///
/// 同时实现 [PluginExecutor] 与 [StreamPluginExecutor]：
/// - [execute]：调用 [OpenAI.instance.chat.create]，解析 choices[0].message.content
///   与 usage.total_tokens。
/// - [executeStream]：调用 [OpenAI.instance.chat.createStream]，逐 token emit
///   partial，流结束 emit done。
///
/// 因 SDK 使用全局静态 apiKey/baseUrl，所有调用经 [_withSdkLock] 串行化，
/// 每次调用前注入 config。非 200 抛 [RequestFailedException] 转 StateError。
///
/// 注意：SDK 流式模式不返回 usage（[OpenAIStreamChatCompletionModel] 无 usage
/// 字段），故流式输出 usage_tokens 恒为 0。
class OpenAiExecutor implements PluginExecutor, StreamPluginExecutor {
  OpenAiExecutor({http.Client? client}) : _client = client;

  /// 可选 HTTP 客户端（测试注入用）；为 null 时 SDK 使用默认客户端。
  final http.Client? _client;

  String _baseUrl(Map<String, dynamic> config) {
    final raw = config['baseUrl']?.toString().trim();
    if (raw == null || raw.isEmpty) return 'https://api.openai.com';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _apiKey(Map<String, dynamic> config) =>
      config['apiKey']?.toString() ?? '';

  /// 将单个元素转为 Map<String, dynamic>。
  Map<String, dynamic> _toMessageMap(Object? e) {
    if (e is Map<String, dynamic>) return e;
    if (e is Map) return Map<String, dynamic>.from(e);
    return <String, dynamic>{};
  }

  /// 规范化 messages：接受 List 或 JSON 字符串。
  List<Map<String, dynamic>> _normalizeMessages(Object? raw) {
    if (raw is List) {
      return raw.map(_toMessageMap).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map(_toMessageMap).toList();
        }
      } catch (_) {
        // 字符串但非 JSON：视为单条 user 消息。
        return [
          {'role': 'user', 'content': raw},
        ];
      }
    }
    return const [];
  }

  /// 将消息 Map 列表转为 SDK 消息模型列表。
  List<OpenAIChatCompletionChoiceMessageModel> _toSdkMessages(
    List<Map<String, dynamic>> messages,
  ) {
    return messages.map((m) {
      final roleStr = m['role']?.toString() ?? 'user';
      final role = OpenAIChatMessageRole.values.firstWhere(
        (r) => r.name == roleStr,
        orElse: () => OpenAIChatMessageRole.user,
      );
      final contentStr = m['content']?.toString() ?? '';
      return OpenAIChatCompletionChoiceMessageModel(
        role: role,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(contentStr),
        ],
      );
    }).toList();
  }

  /// 从非流式响应中提取文本内容。
  String _extractContent(OpenAIChatCompletionModel result) {
    if (result.choices.isEmpty) return '';
    final content = result.choices.first.message.content;
    if (content == null) return '';
    return content
        .where((c) => c.text != null)
        .map((c) => c.text!)
        .join();
  }

  /// 从流式事件中提取增量文本。
  String _extractDeltaContent(OpenAIStreamChatCompletionModel event) {
    if (event.choices.isEmpty) return '';
    final content = event.choices.first.delta.content;
    if (content == null) return '';
    return content
        .where((c) => c?.text != null)
        .map((c) => c!.text!)
        .join();
  }

  @override
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async {
    final apiKey = _apiKey(config);
    if (apiKey.isEmpty) {
      throw StateError('OpenAI 插件未配置 API Key');
    }
    final base = _baseUrl(config);
    final messages = _toSdkMessages(_normalizeMessages(inputs['messages']));
    final model = inputs['model']?.toString() ?? 'gpt-4o-mini';
    final temperature = inputs['temperature'] is num
        ? (inputs['temperature'] as num).toDouble()
        : 0.7;

    return _withSdkLock(() async {
      OpenAI.apiKey = apiKey;
      OpenAI.baseUrl = base;
      OpenAI.showLogs = false;
      try {
        final result = await OpenAI.instance.chat.create(
          model: model,
          messages: messages,
          temperature: temperature,
          client: _client,
        );
        return {
          'content': _extractContent(result),
          'usage_tokens': result.usage.totalTokens,
        };
      } on RequestFailedException catch (e) {
        throw StateError(
          'OpenAI 请求失败：${e.statusCode} ${e.message}',
        );
      }
    });
  }

  @override
  Stream<PluginEvent> executeStream(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async* {
    final apiKey = _apiKey(config);
    if (apiKey.isEmpty) {
      yield const PluginEvent.error('OpenAI 插件未配置 API Key');
      return;
    }
    final base = _baseUrl(config);
    final messages = _toSdkMessages(_normalizeMessages(inputs['messages']));
    final model = inputs['model']?.toString() ?? 'gpt-4o-mini';
    final temperature = inputs['temperature'] is num
        ? (inputs['temperature'] as num).toDouble()
        : 0.7;

    // 在锁保护下注入配置并消费整个流，逐 token 转发为 PluginEvent。
    // SDK 流式模式不返回 usage，故 usage_tokens 恒为 0。
    final buffer = StringBuffer();
    yield* _withSdkLockStream(() async* {
      OpenAI.apiKey = apiKey;
      OpenAI.baseUrl = base;
      OpenAI.showLogs = false;
      Stream<OpenAIStreamChatCompletionModel> stream;
      try {
        stream = OpenAI.instance.chat.createStream(
          model: model,
          messages: messages,
          temperature: temperature,
          client: _client,
        );
      } on RequestFailedException catch (e) {
        yield PluginEvent.error('OpenAI 请求失败：${e.statusCode} ${e.message}');
        return;
      }

      try {
        await for (final event in stream) {
          final piece = _extractDeltaContent(event);
          if (piece.isNotEmpty) {
            buffer.write(piece);
            yield PluginEvent.partial(piece);
          }
        }
      } catch (e) {
        yield PluginEvent.error('OpenAI 流解析错误：$e');
        return;
      }
      yield PluginEvent.done({
        'content': buffer.toString(),
        'usage_tokens': 0,
      });
    });
  }
}

/// 在串行锁保护下消费一个 async generator 流（流期间持锁）。
Stream<T> _withSdkLockStream<T>(Stream<T> Function() streamFactory) {
  final controller = StreamController<T>();
  _withSdkLock(() async {
    try {
      await for (final event in streamFactory()) {
        controller.add(event);
      }
      await controller.close();
    } catch (e, st) {
      controller.addError(e, st);
      await controller.close();
    }
  });
  return controller.stream;
}
