import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UI 段占位视图。
///
/// Task 2 阶段为占位：居中标题 + 输入框，证明切换段时 state 保留。
/// 后续 Task 将替换为可视化 UI 编辑器。
class UiEditorSegmentView extends ConsumerStatefulWidget {
  const UiEditorSegmentView({super.key});

  @override
  ConsumerState<UiEditorSegmentView> createState() =>
      _UiEditorSegmentViewState();
}

class _UiEditorSegmentViewState extends ConsumerState<UiEditorSegmentView> {
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
            Icon(Icons.widgets_outlined, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('UI 段', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '（占位 · 后续接入可视化 UI 编辑器）',
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
