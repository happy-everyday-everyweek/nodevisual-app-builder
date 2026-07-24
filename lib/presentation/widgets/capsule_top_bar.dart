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
/// - 无阴影（极简风，使用描边替代）；
/// - 当前选中段填充主色高亮，未选中段透明；
/// - 切换动画：300ms easeOutCubic（正向）/ easeInCubic（反向）；
/// - 高度约 56，按钮触控区充足，移动端友好。
///
/// 通过 [SafeArea] 适配状态栏，使用 [Stack]+[Positioned] 悬浮（不挤压内容区）。
class CapsuleTopBar extends ConsumerWidget {
  const CapsuleTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = ref.watch(currentSegmentProvider);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cs.outlineVariant, width: 0.75),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.85),
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
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(currentSegmentProvider.notifier).state = segment;
        },
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          reverseDuration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? cs.onPrimary
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
