import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/models/port.dart';
import '../plugin_spec.dart';

/// Anthropic Messages 插件规格。
///
/// id: `llm_anthropic`；输入 messages(list) / model(text) / maxTokens(number)；
/// 输出 content(string) / usage_tokens(number)；配置 apiKey(secret) +
/// baseUrl(text，默认 https://api.anthropic.com)。
const PluginSpec anthropicPluginSpec = PluginSpec(
  id: 'llm_anthropic',
  displayName: 'Anthropic LLM',
  description: '调用 Anthropic Messages 接口生成文本，支持流式输出。',
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
      description: '模型名，如 claude-3-5-sonnet-20240612',
    ),
    PluginInput(
      name: 'maxTokens',
      type: PortType.number,
      required: true,
      description: '最大输出 token 数',
    ),
  ],
  outputs: [
    PluginOutput(name: 'content', type: PortType.string, description: '生成的文本'),
    PluginOutput(name: 'usage_tokens', type: PortType.number, description: '输入+输出 token 数'),
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
      defaultValue: 'https://api.anthropic.com',
    ),
  ],
);

/// Anthropic 执行器（同时实现 [PluginExecutor] 与 [StreamPluginExecutor]）。
///
/// - [execute]：POST {baseUrl}/v1/messages，header x-api-key +
///   anthropic-version: 2023-06-01，解析 content[0].text 与
///   usage.input_tokens + usage.output_tokens。
/// - [executeStream]：stream 流式 SSE，解析 content_block_delta 事件的
///   delta.text 逐 token emit partial，message_delta 携带 usage。
/// - 非 200 抛异常带状态码与 body。
class AnthropicExecutor implements PluginExecutor, StreamPluginExecutor {
  AnthropicExecutor({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _anthropicVersion = '2023-06-01';

  String _baseUrl(Map<String, dynamic> config) {
    // baseUrl 取配置或默认值；去除末尾斜杠。
    final raw = config['baseUrl']?.toString().trim();
    if (raw == null || raw.isEmpty) return 'https://api.anthropic.com';
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

  @override
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async {
    final apiKey = _apiKey(config);
    if (apiKey.isEmpty) {
      throw StateError('Anthropic 插件未配置 API Key');
    }
    final base = _baseUrl(config);
    final messages = _normalizeMessages(inputs['messages']);
    final model = inputs['model']?.toString() ?? 'claude-3-5-sonnet-20240612';
    final maxTokens = inputs['maxTokens'] is num
        ? (inputs['maxTokens'] as num).toInt()
        : 1024;

    final uri = Uri.parse('$base/v1/messages');
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
    });

    final response = await _client.post(
      uri,
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': _anthropicVersion,
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Anthropic 请求失败：${response.statusCode} ${response.reasonPhrase ?? ""}\n${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final contentBlocks = json['content'];
    String content = '';
    if (contentBlocks is List) {
      for (final block in contentBlocks) {
        if (block is Map<String, dynamic> && block['type'] == 'text') {
          content += block['text']?.toString() ?? '';
        }
      }
    }
    final usage = json['usage'];
    int tokens = 0;
    if (usage is Map<String, dynamic>) {
      final inputTokens = usage['input_tokens'];
      final outputTokens = usage['output_tokens'];
      if (inputTokens is num) tokens += inputTokens.toInt();
      if (outputTokens is num) tokens += outputTokens.toInt();
    }
    return {
      'content': content,
      'usage_tokens': tokens,
    };
  }

  @override
  Stream<PluginEvent> executeStream(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async* {
    final apiKey = _apiKey(config);
    if (apiKey.isEmpty) {
      yield const PluginEvent.error('Anthropic 插件未配置 API Key');
      return;
    }
    final base = _baseUrl(config);
    final messages = _normalizeMessages(inputs['messages']);
    final model = inputs['model']?.toString() ?? 'claude-3-5-sonnet-20240612';
    final maxTokens = inputs['maxTokens'] is num
        ? (inputs['maxTokens'] as num).toInt()
        : 1024;

    final uri = Uri.parse('$base/v1/messages');
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'stream': true,
    });

    final request = http.Request('POST', uri)
      ..headers['x-api-key'] = apiKey
      ..headers['anthropic-version'] = _anthropicVersion
      ..headers['Content-Type'] = 'application/json'
      ..body = body;

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      yield PluginEvent.error('Anthropic 网络错误：$e');
      return;
    }

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      yield PluginEvent.error(
        'Anthropic 请求失败：${response.statusCode}\n$errorBody',
      );
      return;
    }

    final buffer = StringBuffer();
    int inputTokens = 0;
    int outputTokens = 0;

    // Anthropic SSE：`event: <type>` 与 `data: <json>` 成对出现。
    // 关注 content_block_delta（delta.text）与 message_delta（usage）。
    final lineStream =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());

    String? currentEvent;
    try {
      await for (final line in lineStream) {
        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
          continue;
        }
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        try {
          final chunk = jsonDecode(payload) as Map<String, dynamic>;
          final eventType = currentEvent ?? chunk['type']?.toString();
          if (eventType == 'content_block_delta') {
            final delta = chunk['delta'];
            if (delta is Map<String, dynamic> &&
                delta['type'] == 'text_delta') {
              final piece = delta['text'];
              if (piece is String && piece.isNotEmpty) {
                buffer.write(piece);
                yield PluginEvent.partial(piece);
              }
            }
          } else if (eventType == 'message_delta') {
            final usage = chunk['usage'];
            if (usage is Map<String, dynamic>) {
              final ot = usage['output_tokens'];
              if (ot is num) outputTokens = ot.toInt();
            }
          } else if (eventType == 'message_start') {
            final message = chunk['message'];
            if (message is Map<String, dynamic>) {
              final usage = message['usage'];
              if (usage is Map<String, dynamic>) {
                final it = usage['input_tokens'];
                if (it is num) inputTokens = it.toInt();
              }
            }
          }
        } catch (_) {
          // 跳过无法解析的 chunk。
        }
        currentEvent = null;
      }
    } catch (e) {
      yield PluginEvent.error('Anthropic 流解析错误：$e');
      return;
    }

    yield PluginEvent.done({
      'content': buffer.toString(),
      'usage_tokens': inputTokens + outputTokens,
    });
  }
}
