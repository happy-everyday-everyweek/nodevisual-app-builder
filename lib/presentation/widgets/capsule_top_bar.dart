import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/project/project_providers.dart';

/// 悬浮胶囊状 Top 栏。
///
/// 用于 [EditorShellScreen] 顶部，提供「函数 / 数据库 / UI」三段切换。
/// 视觉特征：
/// - 圆角胶囊（BorderRadius.circular(28)）；
/// - 半透明背景 + 背景模糊（glassmorphism），主题自适应；
/// - Material 阴影，悬浮于内容之上；
/// - 当前选中段填充主色高亮，未选中段透明；
/// - 高度约 56，按钮触控区充足，移动端友好。
///
/// 通过 [SafeArea] 适配状态栏，使用 [Stack]+[Positioned] 悬浮（不挤压内容区）。
class CapsuleTopBar extends ConsumerWidget {
  const CapsuleTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(currentSegmentProvider);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(
          child: DecoratedBox(
            // 外层负责阴影。
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SegmentButton(
                        segment: EditorSegment.functions,
                        label: '函数',
                        icon: Icons.functions,
                        selected: current == EditorSegment.functions,
                      ),
                      _SegmentButton(
                        segment: EditorSegment.database,
                        label: '数据库',
                        icon: Icons.storage_outlined,
                        selected: current == EditorSegment.database,
                      ),
                      _SegmentButton(
                        segment: EditorSegment.ui,
                        label: 'UI',
                        icon: Icons.widgets_outlined,
                        selected: current == EditorSegment.ui,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 胶囊内单个段切换按钮。
class _SegmentButton extends ConsumerWidget {
  const _SegmentButton({
    required this.segment,
    required this.label,
    required this.icon,
    required this.selected,
  });

  final EditorSegment segment;
  final String label;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(currentSegmentProvider.notifier).state = segment;
        },
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
