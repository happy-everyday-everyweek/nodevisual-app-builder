import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 函数段占位视图。
///
/// Task 2 阶段为占位：居中标题 + 一个有状态计数器 + 输入框，
/// 用于证明切换到其他段再回来时 state 不丢失（由 [IndexedStack] 保活）。
/// 后续 Task 将替换为真实函数节点图编辑器。
class FunctionsSegmentView extends ConsumerStatefulWidget {
  const FunctionsSegmentView({super.key});

  @override
  ConsumerState<FunctionsSegmentView> createState() =>
      _FunctionsSegmentViewState();
}

class _FunctionsSegmentViewState extends ConsumerState<FunctionsSegmentView> {
  int _counter = 0;
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.functions, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('函数段', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '（占位 · 后续接入节点图编辑器）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Text('计数器：$_counter', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.outlined(
                  onPressed: () => setState(() => _counter--),
                  icon: const Icon(Icons.remove),
                  tooltip: '减一',
                ),
                const SizedBox(width: 16),
                IconButton.filled(
                  onPressed: () => setState(() => _counter++),
                  icon: const Icon(Icons.add),
                  tooltip: '加一',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '切换到其他段再回来，计数不会丢失',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: '输入文字（切换不丢失）',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
