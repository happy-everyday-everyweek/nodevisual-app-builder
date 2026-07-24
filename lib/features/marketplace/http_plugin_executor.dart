import 'dart:convert';

import 'package:http/http.dart' as http;

import '../plugins/plugin_spec.dart';
import 'plugin_manifest.dart';

/// HTTP 插件执行器。
///
/// 根据 [PluginManifest] 中的 [HttpExecutorDef] 模板构造 HTTP 请求，
/// 执行后从响应 JSON 中按 `responseMapping` 提取输出。
///
/// 模板变量语法：`{{inputs.xxx}}` / `{{config.xxx}}`。
class HttpPluginExecutor implements PluginExecutor {
  HttpPluginExecutor(this.manifest);

  /// 插件清单（含 HTTP 执行器定义）。
  final PluginManifest manifest;

  /// 模板变量正则：`{{inputs.xxx}}` 或 `{{config.xxx}}`。
  static final _templateRegex = RegExp(r'\{\{(inputs|config)\.([a-zA-Z_]\w*)\}\}');

  @override
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async {
    final exec = manifest.executor;

    // 1. 渲染各部件（URL 走 URL 编码；headers / body 走原始字符串，
    //    body 中字符串值需做 JSON 转义以防破坏外层 JSON 结构）。
    final renderedUrl = _renderTemplate(exec.url, inputs, config, _EncodeMode.url);
    final renderedHeaders = <String, String>{};
    for (final entry in exec.headers.entries) {
      renderedHeaders[entry.key] =
          _renderTemplate(entry.value, inputs, config, _EncodeMode.raw);
    }
    String? renderedBody;
    if (exec.body != null && exec.body!.isNotEmpty) {
      renderedBody = _renderTemplate(exec.body!, inputs, config, _EncodeMode.json);
    }

    // 4. 构造请求
    final uri = Uri.parse(renderedUrl);
    http.Request? request;
    http.Response? response;

    try {
      request = http.Request(exec.method.toUpperCase(), uri);
      renderedHeaders.forEach((k, v) => request!.headers[k] = v);
      if (renderedBody != null) {
        request.headers['Content-Type'] ??= 'application/json';
        request.body = renderedBody;
      }

      final streamedResponse = await request.send().timeout(
        Duration(milliseconds: exec.timeoutMs),
      );
      response = await http.Response.fromStream(streamedResponse);
    } catch (e) {
      throw Exception('插件 HTTP 请求失败: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '插件 HTTP 请求返回 ${response.statusCode}: '
        '${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
      );
    }

    // 5. 解析响应并提取输出
    final Map<String, dynamic> outputs = {};
    if (exec.responseMapping.isEmpty) {
      // 无映射时，尝试返回原始 JSON 作为 result 输出
      try {
        final decoded = jsonDecode(response.body);
        outputs['result'] = decoded;
      } catch (_) {
        outputs['result'] = response.body;
      }
    } else {
      dynamic responseData;
      try {
        responseData = jsonDecode(response.body);
      } catch (_) {
        responseData = response.body;
      }
      for (final entry in exec.responseMapping.entries) {
        final outputName = entry.key;
        final jsonPath = entry.value;
        outputs[outputName] = _extractByJsonPath(responseData, jsonPath);
      }
    }

    return outputs;
  }

  /// 模板变量替换的编码策略。
  ///
  /// - [url]：对替换值做 URL 编码（百分号编码），适合放在 URL 路径 / 查询段。
  /// - [raw]：直接替换为原始字符串，不做编码（适合 headers）。
  /// - [json]：对字符串值做 JSON 字符串转义（适合嵌入 JSON body）。
  enum _EncodeMode { url, raw, json }

  /// 渲染模板字符串，按 [mode] 决定替换值的编码方式。
  String _renderTemplate(
    String template,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
    _EncodeMode mode,
  ) {
    return template.replaceAllMapped(_templateRegex, (match) {
      final scope = match.group(1)!; // inputs / config
      final key = match.group(2)!;
      final value = scope == 'inputs' ? inputs[key] : config[key];
      if (value == null) return '';
      return _encodeValue(value, mode);
    });
  }

  /// 按编码模式对值进行转换。
  String _encodeValue(Object value, _EncodeMode mode) {
    switch (mode) {
      case _EncodeMode.url:
        return Uri.encodeComponent(value.toString());
      case _EncodeMode.raw:
        return value.toString();
      case _EncodeMode.json:
        // 字符串值做 JSON 字符串转义（保留外层 JSON 结构完整性）；
        // 数字 / 布尔 / null 等非字符串原样输出，便于嵌入 JSON。
        if (value is String) {
          return jsonEncode(value);
        }
        return value.toString();
    }
  }

  /// 按 JSONPath 简化语法（`$.key.subkey` / `$.key[0]`）提取值。
  ///
  /// 支持点号路径与数组索引。不支持完整的 JSONPath 过滤器语法。
  static dynamic _extractByJsonPath(dynamic data, String path) {
    if (path.isEmpty) return data;
    // 去掉开头的 $.
    var p = path.startsWith(r'$.') ? path.substring(2) : path;
    p = p.startsWith('\$') ? p.substring(1) : p;
    if (p.startsWith('.')) p = p.substring(1);

    if (p.isEmpty) return data;

    // 分割路径段（支持 a.b[0].c 形式）
    final segments = <_PathSegment>[];
    final tokenRegex = RegExp(r'([a-zA-Z_]\w*)|\[(\d+)\]');
    for (final m in tokenRegex.allMatches(p)) {
      if (m.group(1) != null) {
        segments.add(_PathSegment.key(m.group(1)!));
      } else if (m.group(2) != null) {
        segments.add(_PathSegment.index(int.parse(m.group(2)!)));
      }
    }

    var current = data;
    for (final seg in segments) {
      if (current == null) return null;
      if (seg.isKey) {
        if (current is Map<String, dynamic>) {
          current = current[seg.key];
        } else if (current is Map) {
          current = current[seg.key];
        } else {
          return null;
        }
      } else {
        if (current is List && seg.index! < current.length) {
          current = current[seg.index!];
        } else {
          return null;
        }
      }
    }
    return current;
  }
}

/// 路径段（键或数组索引）。
class _PathSegment {
  final String? _key;
  final int? index;

  _PathSegment.key(String key) : _key = key, index = null;
  _PathSegment.index(this.index) : _key = null;

  bool get isKey => _key != null;
  String get key => _key!;
}
