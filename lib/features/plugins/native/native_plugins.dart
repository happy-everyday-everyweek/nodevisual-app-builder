import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:share_plus/share_plus.dart' as share_plus;

import '../../../data/models/port.dart';
import '../plugin_spec.dart';

/// 剪贴板插件规格。
///
/// id: `native_clipboard`；输入 operation(text: copy|paste) / text(string, copy 时必填)；
/// 输出 text(string, paste 时的剪贴板内容或 copy 回显)；无配置。
const PluginSpec clipboardPluginSpec = PluginSpec(
  id: 'native_clipboard',
  displayName: '剪贴板',
  description: '读写系统剪贴板（copy 写入 / paste 读取）。',
  inputs: [
    PluginInput(
      name: 'operation',
      type: PortType.string,
      required: true,
      description: '操作：copy（写入）或 paste（读取）',
    ),
    PluginInput(
      name: 'text',
      type: PortType.string,
      required: false,
      description: '要写入的文本（operation=copy 时必填）',
    ),
  ],
  outputs: [
    PluginOutput(
      name: 'text',
      type: PortType.string,
      description: 'paste 时的剪贴板内容；copy 时回显写入的文本',
    ),
  ],
);

/// 剪贴板执行器。
class ClipboardExecutor implements PluginExecutor {
  const ClipboardExecutor();

  @override
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async {
    final op = inputs['operation']?.toString().toLowerCase() ?? 'copy';
    if (op == 'paste') {
      final data = await Clipboard.getData('text/plain');
      return {'text': data?.text ?? ''};
    }
    // copy
    final text = inputs['text']?.toString() ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    return {'text': text};
  }
}

/// 触感反馈插件规格。
///
/// id: `native_haptic`；输入 type(text: light|medium|heavy|selection)；
/// 输出 ok(bool)；无配置。
const PluginSpec hapticPluginSpec = PluginSpec(
  id: 'native_haptic',
  displayName: '触感反馈',
  description: '触发系统触感反馈（轻/中/重/选择）。',
  inputs: [
    PluginInput(
      name: 'type',
      type: PortType.string,
      required: false,
      description: '反馈类型：light / medium / heavy / selection，默认 light',
    ),
  ],
  outputs: [
    PluginOutput(
      name: 'ok',
      type: PortType.bool,
      description: '是否已触发',
    ),
  ],
);

/// 触感反馈执行器。
class HapticExecutor implements PluginExecutor {
  const HapticExecutor();

  @override
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async {
    final type = inputs['type']?.toString().toLowerCase() ?? 'light';
    switch (type) {
      case 'medium':
        await HapticFeedback.mediumImpact();
      case 'heavy':
        await HapticFeedback.heavyImpact();
      case 'selection':
        await HapticFeedback.selectionClick();
      case 'light':
      default:
        await HapticFeedback.lightImpact();
    }
    return {'ok': true};
  }
}

/// 分享插件规格。
///
/// id: `native_share`；输入 text(string) / subject(string, 可选，邮件主题等)；
/// 输出 ok(bool)；无配置。
const PluginSpec sharePluginSpec = PluginSpec(
  id: 'native_share',
  displayName: '分享',
  description: '调用系统分享面板分享文本。',
  inputs: [
    PluginInput(
      name: 'text',
      type: PortType.string,
      required: true,
      description: '要分享的文本内容',
    ),
    PluginInput(
      name: 'subject',
      type: PortType.string,
      required: false,
      description: '主题（如邮件主题，部分平台生效）',
    ),
  ],
  outputs: [
    PluginOutput(
      name: 'ok',
      type: PortType.bool,
      description: '是否已唤起分享面板',
    ),
  ],
);

/// 分享执行器。
class ShareExecutor implements PluginExecutor {
  const ShareExecutor();

  @override
  Future<Map<String, dynamic>> execute(
    PluginSpec spec,
    Map<String, dynamic> inputs,
    Map<String, dynamic> config,
  ) async {
    final text = inputs['text']?.toString() ?? '';
    final subject = inputs['subject']?.toString();
    await share_plus.Share.share(text, subject: subject);
    return {'ok': true};
  }
}
