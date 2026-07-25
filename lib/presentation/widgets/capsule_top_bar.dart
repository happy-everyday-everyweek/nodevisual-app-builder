import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/project/project_providers.dart';

/// 悬浮胶囊状 Top 栏。
///
/// 用于 [EditorShellScreen] 顶部，提供「函数 / 数据库 / UI / 发布」四段切换。
///
/// 视觉特征（与函数编辑器下方 `_buildCapsuleToolbar` 一致，形成"上下呼应"的
/// 悬浮层次感）：
/// - 圆角胶囊（BorderRadius.circular(28)）；
/// - 半透明背景 + 背景模糊（glassmorphism），主题自适应；
/// - **柔和投影**（black 8% / blur 12 / offset (0,2)），让胶囊"浮"在内容之上；
/// - 当前选中段填充主色高亮，未选中段透明；
/// - 切换动画：
///   - 选中态颜色与文字粗细：260ms easeOutCubic（正向）/ easeInCubic（反向）；
///   - 图标轻微缩放反馈（selected → 1.05，unselected → 1.0），用 [TweenAnimationBuilder]
///     实现哪去哪回的自然过渡；
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
              // 与下方胶囊工具栏一致的柔和投影，形成"上下呼应"的悬浮层次感。
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    // 与下方胶囊一致（0.95），略提高不透明度让阴影更"实"。
                    color: cs.surface.withValues(alpha: 0.95),
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
                      _SegmentButton(
                        segment: EditorSegment.publish,
                        label: '发布',
                        icon: Icons.public,
                        selected: current == EditorSegment.publish,
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
///
/// 切换动画"哪去哪回"：
/// - 选中态：填充主色，文字 w600，图标放大到 1.06；
/// - 未选中态：透明，文字 w500，图标 1.0；
/// - 过渡曲线：easeOutCubic（选中正向）/ easeInCubic（取消反向），
///   形成自然"按下去回弹"的手感。
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
          // 选中时正向 easeOutCubic（向外扩张），取消时反向 easeInCubic（向内收回），
          // 形成"哪去哪回"的自然过渡。
          curve: selected ? Curves.easeOutCubic : Curves.easeInCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标缩放反馈：选中时轻微放大，强化"被选中"的视觉重量。
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: selected ? 1.0 : 1.06,
                  end: selected ? 1.06 : 1.0,
                ),
                duration: const Duration(milliseconds: 220),
                curve: selected ? Curves.easeOutCubic : Curves.easeInCubic,
                builder: (ctx, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? cs.onPrimary
                      : cs.onSurfaceVariant,
                ),
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
