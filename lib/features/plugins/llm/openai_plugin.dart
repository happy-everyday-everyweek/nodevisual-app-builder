import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/models/port.dart';
import '../plugin_spec.dart';

// 迁移说明（LLM SDK 方向）：
// -----
// 按需求 OpenAI 节点应使用官方 SDK（dart_openai，已在 pubspec.yaml 引入），
// 而非手写 HTTP。当前实现仍保留手写 HTTP，原因：
// 1. dart_openai 的 apiKey/baseUrl 为全局静态字段（OpenAI.apiKey / OpenAI.baseUrl），
//    与本插件"每次 execute 按 config 注入"的 per-call 模型不匹配，
//    直接替换会在并发调用时产生全局状态竞争。
// 2. dart_openai 跨大版本（4.x → 5.x）API 有破坏性变更（消息模型从 String 改为
//    ContentItem 数组），需在引入后按实际版本调整消息构造。
// 3. 流式 SSE 解析在 SDK 中以 Stream<OpenAIStreamChatCompletionModel> 暴露，
//    与现有 PluginEvent 适配需额外胶水代码。
// 迁移路径（建议在能运行 flutter pub get + 集成测试的环境下进行）：
//   - 新增 OpenAiSdkExecutor（implements PluginExecutor, StreamPluginExecutor），
//     在 execute 开头 OpenAI.apiKey = config['apiKey']; OpenAI.baseUrl = base;
//   - 用 OpenAI.instance.chat.create(...) 替换 _client.post(...)
//   - 用 OpenAI.instance.chat.createStream(...) 替换手动 SSE 解析
//   - 在 PluginRegistry.withBuiltins 用 OpenAiSdkExecutor() 替换 OpenAiExecutor()
// Anthropic 暂无官方 Dart SDK，继续使用手写 HTTP。

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

/// OpenAI 执行器（同时实现 [PluginExecutor] 与 [StreamPluginExecutor]）。
///
/// - [execute]：POST {baseUrl}/v1/chat/completions，解析 choices[0].message.content
///   与 usage.total_tokens。
/// - [executeStream]：用 stream:true，SSE 解析 data: 行，逐 token emit partial，
///   流结束 emit done（汇总完整 content + usage）。
/// - 非 200 抛异常带状态码与 body。
class OpenAiExecutor implements PluginExecutor, StreamPluginExecutor {
  OpenAiExecutor({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String _baseUrl(Map<String, dynamic> config) {
    // baseUrl 取配置或默认值；去除末尾斜杠。
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
    final messages = _normalizeMessages(inputs['messages']);
    final model = inputs['model']?.toString() ?? 'gpt-4o-mini';
    final temperature = inputs['temperature'] is num
        ? (inputs['temperature'] as num).toDouble()
        : 0.7;

    final uri = Uri.parse('$base/v1/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
    });

    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw StateError(
        'OpenAI 请求失败：${response.statusCode} ${response.reasonPhrase ?? ""}\n${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'];
    String content = '';
    if (choices is List && choices.isNotEmpty) {
      final message = (choices[0] as Map<String, dynamic>)['message'];
      if (message is Map<String, dynamic>) {
        content = message['content']?.toString() ?? '';
      }
    }
    final usage = json['usage'];
    int tokens = 0;
    if (usage is Map<String, dynamic>) {
      final t = usage['total_tokens'];
      if (t is num) tokens = t.toInt();
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
      yield const PluginEvent.error('OpenAI 插件未配置 API Key');
      return;
    }
    final base = _baseUrl(config);
    final messages = _normalizeMessages(inputs['messages']);
    final model = inputs['model']?.toString() ?? 'gpt-4o-mini';
    final temperature = inputs['temperature'] is num
        ? (inputs['temperature'] as num).toDouble()
        : 0.7;

    final uri = Uri.parse('$base/v1/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'stream': true,
      'stream_options': {'include_usage': true},
    });

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Content-Type'] = 'application/json'
      ..body = body;

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      yield PluginEvent.error('OpenAI 网络错误：$e');
      return;
    }

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      yield PluginEvent.error(
        'OpenAI 请求失败：${response.statusCode}\n$errorBody',
      );
      return;
    }

    final buffer = StringBuffer();
    int totalTokens = 0;

    // SSE 解析：按行读取，匹配 `data: ` 前缀。
    final lineStream =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());

    try {
      await for (final line in lineStream) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;
        try {
          final chunk = jsonDecode(payload) as Map<String, dynamic>;
          final choices = chunk['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = (choices[0] as Map<String, dynamic>)['delta'];
            if (delta is Map<String, dynamic>) {
              final piece = delta['content'];
              if (piece is String && piece.isNotEmpty) {
                buffer.write(piece);
                yield PluginEvent.partial(piece);
              }
            }
          }
          final usage = chunk['usage'];
          if (usage is Map<String, dynamic>) {
            final t = usage['total_tokens'];
            if (t is num) totalTokens = t.toInt();
          }
        } catch (_) {
          // 跳过无法解析的 chunk。
        }
      }
    } catch (e) {
      yield PluginEvent.error('OpenAI 流解析错误：$e');
      return;
    }

    yield PluginEvent.done({
      'content': buffer.toString(),
      'usage_tokens': totalTokens,
    });
  }
}
