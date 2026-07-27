import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/function_def.dart';
import '../../../../data/models/page.dart';
import '../../../../data/models/ui_tree.dart';
import '../../../functions/function_providers.dart';
import '../../component_registry_v2.dart';
import '../../ui_editor_providers.dart';

/// 触发段编辑器（Phase 4 v2）。
///
/// 根据选中组件的 [ComponentDef.events] 列表动态渲染事件列表，
/// 每个事件旁有函数选择下拉：
/// - 选择已有函数 → `setTrigger(componentId, event, funcId)`
/// - "新建函数" → 弹出命名对话框，调用 `createFunction` 后绑定
///
/// Page 节点不使用本段（页面生命周期事件在 [_PageLifecycleSection] 中渲染）。
class TriggersSection extends ConsumerWidget {
  const TriggersSection({super.key, required this.node});

  final UiNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final project = ref.watch(uiMutatorProvider);
    if (project == null) {
      return const SizedBox.shrink();
    }

    final def = ComponentRegistry.byType(node.type);
    final events = def?.events ?? const <EventSpec>[];

    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '该组件无可绑定事件',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ev in events)
          _TriggerRow(
            key: ValueKey('${node.id}:${ev.name}'),
            node: node,
            event: ev,
          ),
      ],
    );
  }
}

/// 单个触发事件行：事件标签 + 函数下拉 + 新建按钮。
class _TriggerRow extends ConsumerWidget {
  const _TriggerRow({
    super.key,
    required this.node,
    required this.event,
  });

  final UiNode node;
  final EventSpec event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final project = ref.watch(uiMutatorProvider);
    if (project == null) return const SizedBox.shrink();

    final mutator = ref.read(uiMutatorProvider.notifier);
    final currentFuncId = mutator.getTriggerFunctionId(node.id, event.name);
    final functions = project.functions;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(event.label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: functions.any((f) => f.id == currentFuncId)
                  ? currentFuncId
                  : null,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              hint: const Text('未绑定'),
              items: [
                for (final f in functions)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) => mutator.setTrigger(node.id, event.name, v),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: '新建函数并绑定',
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => _createFunction(context, ref),
          ),
        ],
      ),
    );
  }

  /// 弹出命名对话框 → 创建函数 → 绑定到本事件。
  Future<void> _createFunction(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(
          text: '${event.label}处理',
        );
        return AlertDialog(
          title: const Text('新建函数'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '函数名',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;

    final funcId = ref
        .read(projectMutatorProvider.notifier)
        .createFunction(name.trim());
    ref.read(uiMutatorProvider.notifier).setTrigger(node.id, event.name, funcId);
  }
}

/// 页面生命周期事件段（Page 节点专用）。
///
/// 列出 [PageLifecycleEvent.all]（onLoad/onDispose/onResume/onPause），
/// 每项绑定到函数（通过 `setPageEventFunction`）。
class PageLifecycleSection extends ConsumerWidget {
  const PageLifecycleSection({super.key, required this.page});

  final UiNode page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final project = ref.watch(uiMutatorProvider);
    if (project == null) return const SizedBox.shrink();

    final functions = project.functions;
    final mutator = ref.read(uiMutatorProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in PageLifecycleEvent.all)
          _LifecycleRow(
            key: ValueKey('${page.id}:$event'),
            pageId: page.id,
            event: event,
            functions: functions,
            currentFuncId: mutator.getPageEventFunctionId(page.id, event),
            onChanged: (funcId) =>
                mutator.setPageEventFunction(page.id, event, funcId),
          ),
      ],
    );
  }
}

/// 单个生命周期事件行。
class _LifecycleRow extends ConsumerWidget {
  const _LifecycleRow({
    super.key,
    required this.pageId,
    required this.event,
    required this.functions,
    required this.currentFuncId,
    required this.onChanged,
  });

  final String pageId;
  final String event;
  final List<FunctionDef> functions;
  final String? currentFuncId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(_label(event), style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: functions.any((f) => f.id == currentFuncId)
                  ? currentFuncId
                  : null,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              hint: const Text('未绑定'),
              items: [
                for (final f in functions)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text(f.name),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: '新建函数并绑定',
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => _createFunction(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _createFunction(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller =
            TextEditingController(text: '${_label(event)}处理');
        return AlertDialog(
          title: const Text('新建函数'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '函数名',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;

    final funcId = ref
        .read(projectMutatorProvider.notifier)
        .createFunction(name.trim());
    ref
        .read(uiMutatorProvider.notifier)
        .setPageEventFunction(pageId, event, funcId);
  }

  String _label(String event) {
    switch (event) {
      case PageLifecycleEvent.onLoad:
        return '加载';
      case PageLifecycleEvent.onDispose:
        return '销毁';
      case PageLifecycleEvent.onResume:
        return '恢复';
      case PageLifecycleEvent.onPause:
        return '暂停';
      default:
        return event;
    }
  }
}
