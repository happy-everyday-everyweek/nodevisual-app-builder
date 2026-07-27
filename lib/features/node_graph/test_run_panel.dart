import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/function_def.dart';
import '../../data/models/port.dart';
import '../../data/models/project.dart';
import '../compiler/interpreter/database_executor.dart';
import '../compiler/interpreter/node_interpreter.dart';
import '../plugins/plugin_config_storage.dart';
import '../plugins/plugin_registry.dart';
import '../project/project_providers.dart';
import 'graph_providers.dart';
import 'test_run_state.dart';

/// 函数编辑器测试运行面板。
///
/// 提供：
/// - 按函数签名设置入参
/// - 选择测试环境（Android / Windows / Web / 自定义）
/// - 启动测试运行并高亮当前执行节点
/// - 展示运行结果与执行日志
class TestRunPanel extends ConsumerStatefulWidget {
  const TestRunPanel({super.key});

  @override
  ConsumerState<TestRunPanel> createState() => _TestRunPanelState();
}

class _TestRunPanelState extends ConsumerState<TestRunPanel> {
  final Map<String, TextEditingController> _inputControllers = {};

  @override
  void dispose() {
    for (final c in _inputControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fn = ref.watch(graphMutatorProvider);
    final testRun = ref.watch(testRunProvider);
    final theme = Theme.of(context);

    if (fn == null) {
      return const SizedBox.shrink();
    }

    // 同步入参控制器与函数签名。
    _syncControllers(fn);

    final env = testRun.environment;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme, fn),
              const SizedBox(height: 12),
              _buildInputsSection(theme, fn),
              const SizedBox(height: 12),
              _buildEnvironmentSection(theme, env),
              const SizedBox(height: 12),
              _buildRunButton(theme, fn, testRun),
              if (testRun.isRunning || testRun.result != null) ...[
                const SizedBox(height: 12),
                _buildResultSection(theme, testRun, fn),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, FunctionDef fn) {
    return Row(
      children: [
        Icon(Icons.play_circle_outline, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '测试运行 — ${fn.name}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          tooltip: '关闭',
        ),
      ],
    );
  }

  Widget _buildInputsSection(ThemeData theme, FunctionDef fn) {
    final inputs = fn.inputs;
    if (inputs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '该函数无入参',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '入参',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final param in inputs) ...[
            _buildInputField(theme, param),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildInputField(ThemeData theme, dynamic param) {
    final controller = _inputControllers[param.name];
    if (controller == null) return const SizedBox.shrink();
    final label = '${param.name}${param.description != null && param.description!.isNotEmpty ? ' · ${param.description}' : ''}';
    final hint = _defaultValueHint(param.type);
    return TextField(
      controller: controller,
      keyboardType: _keyboardTypeFor(param.type),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        final value = _parseInputValue(v, param.type);
        ref.read(testRunProvider.notifier).setInput(param.name, value);
      },
    );
  }

  Widget _buildEnvironmentSection(
    ThemeData theme,
    TestEnvironment? current,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '运行环境',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showCustomEnvironmentDialog(theme, current),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('自定义'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final env in builtinTestEnvironments)
                ChoiceChip(
                  label: Text(env.name),
                  selected: current?.id == env.id,
                  onSelected: (_) {
                    ref.read(testRunProvider.notifier).selectEnvironment(env);
                  },
                ),
            ],
          ),
          if (current != null) ...[
            const SizedBox(height: 8),
            Text(
              '${current.screenWidth.toInt()}×${current.screenHeight.toInt()} · '
              'DPR ${current.devicePixelRatio} · ${_platformLabel(current.platform)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRunButton(
    ThemeData theme,
    FunctionDef fn,
    TestRunState testRun,
  ) {
    return FilledButton.icon(
      onPressed: testRun.isRunning ? null : () => _runTest(fn),
      icon: testRun.isRunning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow),
      label: Text(testRun.isRunning ? '运行中…' : '开始测试运行'),
    );
  }

  Widget _buildResultSection(
    ThemeData theme,
    TestRunState testRun,
    FunctionDef fn,
  ) {
    final result = testRun.result;
    final currentId = testRun.currentNodeId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentId != null) ...[
            Text(
              '当前节点',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            _CurrentNodeTile(nodeId: currentId, fn: fn),
            const SizedBox(height: 12),
          ],
          if (result != null) ...[
            Text(
              '运行结果',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (result.error != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  result.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              )
            else
              Text(
                '输出：${_formatOutputs(result.outputs)}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            Text(
              '耗时 ${result.durationMs} ms · 经过 ${result.logs.length} 个节点',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  void _syncControllers(FunctionDef fn) {
    final inputs = fn.inputs;
    final desired = <String, TextEditingController>{};
    final stateInputs = ref.read(testRunProvider).inputs;
    for (final param in inputs) {
      final existing = _inputControllers[param.name];
      if (existing != null) {
        desired[param.name] = existing;
      } else {
        final initial = _valueToString(stateInputs[param.name] ?? param.defaultValue);
        desired[param.name] = TextEditingController(text: initial);
      }
    }
    // 移除已不存在入参的控制器。
    for (final entry in _inputControllers.entries) {
      if (!desired.containsKey(entry.key)) {
        entry.value.dispose();
      }
    }
    _inputControllers
      ..clear()
      ..addAll(desired);
  }

  Future<void> _runTest(FunctionDef fn) async {
    final notifier = ref.read(testRunProvider.notifier);
    notifier.startRun();

    final project = ref.read(currentProjectProvider);
    if (project == null) {
      notifier.finishRun(const TestRunResult(error: '未打开项目'));
      return;
    }

    final inputs = Map<String, dynamic>.from(ref.read(testRunProvider).inputs);
    final env = ref.read(testRunProvider).environment ?? builtinTestEnvironments.first;
    final logs = <TestRunLog>[];
    final stopwatch = Stopwatch()..start();

    // 注入环境变量到 inputs（节点可通过 #env.xxx 引用，见 RuntimeScope）。
    inputs['__env'] = env.toRuntimeMap();

    DatabaseExecutor? dbExecutor;
    try {
      dbExecutor = createDatabaseExecutor();
    } catch (_) {
      // Web 平台可能不支持，继续以 null 运行。
      dbExecutor = null;
    }

    final interpreter = NodeInterpreter(
      project: project,
      pluginRegistry: ref.read(pluginRegistryProvider),
      dbExecutor: dbExecutor,
      pluginConfigStorage: ref.read(pluginConfigStorageProvider),
      onNodeEnter: (nodeId) {
        final node = fn.nodes.where((n) => n.id == nodeId).firstOrNull;
        logs.add(TestRunLog(
          nodeId: nodeId,
          nodeKind: node?.kind ?? 'unknown',
          timestamp: DateTime.now(),
        ));
        notifier.setCurrentNode(nodeId);
      },
    );

    try {
      final result = await interpreter.runFunction(fn, inputs);
      stopwatch.stop();
      notifier.finishRun(TestRunResult(
        outputs: result.outputs,
        error: result.error,
        logs: logs,
        durationMs: stopwatch.elapsedMilliseconds,
      ));
    } catch (e) {
      stopwatch.stop();
      notifier.finishRun(TestRunResult(
        error: '测试运行异常: $e',
        logs: logs,
        durationMs: stopwatch.elapsedMilliseconds,
      ));
    }
  }

  void _showCustomEnvironmentDialog(ThemeData theme, TestEnvironment? base) {
    final baseEnv = base ?? builtinTestEnvironments.first;
    final nameController = TextEditingController(text: baseEnv.name);
    final widthController = TextEditingController(text: baseEnv.screenWidth.toString());
    final heightController = TextEditingController(text: baseEnv.screenHeight.toString());
    final dprController = TextEditingController(text: baseEnv.devicePixelRatio.toString());
    final uaController = TextEditingController(text: baseEnv.userAgent ?? '');
    var platform = baseEnv.platform;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义测试环境'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '环境名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '宽度',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: heightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '高度',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: dprController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '设备像素比',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<TargetPlatform>(
                value: platform,
                decoration: const InputDecoration(
                  labelText: '平台',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: TargetPlatform.android, child: Text('Android')),
                  DropdownMenuItem(value: TargetPlatform.windows, child: Text('Windows')),
                  DropdownMenuItem(value: TargetPlatform.linux, child: Text('Web')),
                ],
                onChanged: (v) {
                  if (v != null) platform = v;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: uaController,
                decoration: const InputDecoration(
                  labelText: 'User-Agent（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final custom = TestEnvironment(
                id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                name: nameController.text.trim().isEmpty ? '自定义环境' : nameController.text.trim(),
                platform: platform,
                screenWidth: double.tryParse(widthController.text) ?? baseEnv.screenWidth,
                screenHeight: double.tryParse(heightController.text) ?? baseEnv.screenHeight,
                devicePixelRatio: double.tryParse(dprController.text) ?? baseEnv.devicePixelRatio,
                userAgent: uaController.text.trim().isEmpty ? null : uaController.text.trim(),
                extra: {},
              );
              ref.read(testRunProvider.notifier).setCustomEnvironment(custom);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _defaultValueHint(PortType type) {
    return switch (type) {
      PortType.number => '输入数字',
      PortType.boolean => 'true / false',
      PortType.string => '输入文本',
      PortType.list => 'JSON 数组',
      PortType.map => 'JSON 对象',
      PortType.any => '任意值',
    };
  }

  TextInputType _keyboardTypeFor(PortType type) {
    return switch (type) {
      PortType.number => TextInputType.number,
      _ => TextInputType.text,
    };
  }

  Object? _parseInputValue(String text, PortType type) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return switch (type) {
      PortType.number => num.tryParse(trimmed),
      PortType.boolean => trimmed.toLowerCase() == 'true',
      _ => trimmed,
    };
  }

  String _valueToString(Object? value) {
    if (value == null) return '';
    return value.toString();
  }

  String _platformLabel(TargetPlatform p) {
    return switch (p) {
      TargetPlatform.android => 'Android',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux || TargetPlatform.macOS => 'Web',
      _ => '其他',
    };
  }

  String _formatOutputs(Map<String, dynamic> outputs) {
    if (outputs.isEmpty) return '（无输出）';
    return outputs.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}

class _CurrentNodeTile extends StatelessWidget {
  const _CurrentNodeTile({required this.nodeId, required this.fn});

  final String nodeId;
  final FunctionDef fn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = fn.nodes.where((n) => n.id == nodeId).firstOrNull;
    final name = node?.params['name']?.toString() ?? node?.kind ?? '未知节点';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.adjust, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
