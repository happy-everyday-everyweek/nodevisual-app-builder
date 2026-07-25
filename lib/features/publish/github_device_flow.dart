import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// GitHub OAuth Device Flow 封装。
///
/// 适用于跨端 Flutter 应用（无后端代理）：客户端用公开的 `clientId`
/// 申请 device_code，引导用户在浏览器中输入 user_code 授权，然后轮询
/// access_token 端点。**不需要 client_secret**，token 不过期（除非用户
/// 撤销授权）。
///
/// 协议参考：https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
///
/// 当前使用 NodeVisual App Builder GitHub App 的 Client ID：
/// `Iv23liG8zQoueA7C8own`（公开值，可硬编码到客户端）。
class GithubDeviceFlow {
  GithubDeviceFlow({String? clientId})
      : clientId = clientId ?? defaultClientId;

  /// NodeVisual App Builder GitHub App 的 Client ID（公开值）。
  ///
  /// GitHub Apps 的 OAuth 模式与 OAuth App 一样使用
  /// `github.com/login/device/code` 端点，client_id 即此值。
  static const String defaultClientId = 'Iv23liG8zQoueA7C8own';

  /// GitHub Apps 的 OAuth 端点（与 OAuth App 共用）。
  static const String _deviceCodeUrl =
      'https://github.com/login/device/code';
  static const String _tokenUrl =
      'https://github.com/login/oauth/access_token';

  final String clientId;

  /// 申请 device code，返回用户需要输入的 user_code、verification_uri、
  /// 以及轮询 token 用的 device_code 和 interval。
  Future<DeviceCodeResponse> requestDeviceCode({
    List<String> scopes = const ['repo', 'workflow'],
  }) async {
    final body = {
      'client_id': clientId,
      'scope': scopes.join(' '),
    };
    final resp = await http.post(
      Uri.parse(_deviceCodeUrl),
      headers: const {
        'Accept': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode != 200) {
      throw GithubDeviceFlowException(
        '请求 device_code 失败：${resp.statusCode} ${resp.body}',
      );
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw GithubDeviceFlowException(
        '请求 device_code 错误：${json['error']} - ${json['error_description'] ?? ''}',
      );
    }
    return DeviceCodeResponse.fromJson(json);
  }

  /// 轮询 access_token 端点。
  ///
  /// - 返回 [TokenResult.pending] 表示用户尚未完成授权，需等待 [interval]
  ///   秒后再次调用。
  /// - 返回 [TokenResult.success] 表示授权成功，包含 access_token。
  /// - 抛 [GithubDeviceFlowException] 表示错误（如 expired_token /
  ///   access_denied / slow_down），调用方应停止轮询。
  Future<TokenResult> pollForToken({
    required String deviceCode,
    required int interval,
  }) async {
    final body = {
      'client_id': clientId,
      'device_code': deviceCode,
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    };
    final resp = await http.post(
      Uri.parse(_tokenUrl),
      headers: const {
        'Accept': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode != 200) {
      throw GithubDeviceFlowException(
        '轮询 token 失败：${resp.statusCode} ${resp.body}',
      );
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final error = json['error'] as String?;
    if (error != null) {
      switch (error) {
        case 'authorization_pending':
          return const TokenResult.pending();
        case 'slow_down':
          // 服务端要求降低频率；调用方应当增大 interval 后继续轮询。
          throw const GithubDeviceFlowException.slowDown();
        case 'expired_token':
          throw const GithubDeviceFlowException(
            'device_code 已过期，请重新发起授权',
          );
        case 'access_denied':
          throw const GithubDeviceFlowException(
            '用户拒绝了授权',
          );
        default:
          throw GithubDeviceFlowException(
            '轮询 token 错误：$error - ${json['error_description'] ?? ''}',
          );
      }
    }
    final token = json['access_token'] as String?;
    if (token == null) {
      throw const GithubDeviceFlowException('响应缺少 access_token 字段');
    }
    return TokenResult.success(token);
  }

  /// 完整的 Device Flow 流程：申请 device_code → 引导用户授权 → 轮询 token。
  ///
  /// [onDeviceCode] 回调在拿到 device_code 后立即触发，UI 应当显示 user_code
  /// 并打开浏览器到 verification_uri。
  /// [shouldStop] 返回 true 时中断轮询（用于 UI 取消）。
  ///
  /// 返回 access_token。抛 [GithubDeviceFlowException] 表示失败。
  Future<String> authenticate({
    required void Function(DeviceCodeResponse) onDeviceCode,
    Future<bool> Function()? shouldStop,
    List<String> scopes = const ['repo', 'workflow'],
  }) async {
    final dc = await requestDeviceCode(scopes: scopes);
    onDeviceCode(dc);

    var interval = dc.interval;
    while (true) {
      if (await shouldStop?.call() ?? false) {
        throw const GithubDeviceFlowException('用户取消授权');
      }
      await Future<void>.delayed(Duration(seconds: interval));
      try {
        final result = await pollForToken(
          deviceCode: dc.deviceCode,
          interval: interval,
        );
        if (result.isPending) continue;
        return result.token!;
      } on GithubDeviceFlowException catch (e) {
        if (e.isSlowDown) {
          // 服务端要求降频，interval +5 秒后继续。
          interval += 5;
          continue;
        }
        rethrow;
      }
    }
  }
}

/// device_code 端点响应。
class DeviceCodeResponse {
  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  /// 轮询 token 用的 device_code（不可展示给用户）。
  final String deviceCode;

  /// 用户在浏览器中输入的 8 位 user_code（如 "WDJB-MJHT"）。
  final String userCode;

  /// 用户授权页 URL（通常为 https://github.com/login/device）。
  final String verificationUri;

  /// device_code 有效期（秒）。
  final int expiresIn;

  /// 轮询间隔（秒）。
  final int interval;

  factory DeviceCodeResponse.fromJson(Map<String, dynamic> json) {
    return DeviceCodeResponse(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: json['verification_uri'] as String,
      expiresIn: (json['expires_in'] as num).toInt(),
      interval: (json['interval'] as num).toInt(),
    );
  }
}

/// 轮询 token 的结果。
class TokenResult {
  const TokenResult._({this.token, this.isPending = false});

  const TokenResult.pending() : this._(isPending: true);

  const TokenResult.success(String token) : this._(token: token);

  final String? token;
  final bool isPending;
}

/// Device Flow 异常。
class GithubDeviceFlowException implements Exception {
  const GithubDeviceFlowException(this.message) : isSlowDown = false;

  /// 服务端要求降频（slow_down 错误）。
  const GithubDeviceFlowException.slowDown()
      : message = '服务端要求降低轮询频率',
        isSlowDown = true;

  final String message;
  final bool isSlowDown;

  @override
  String toString() => 'GithubDeviceFlowException: $message';
}
