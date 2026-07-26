import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/project/project_providers.dart';

/// 悬浮胶囊状 Top 栏。
///
/// 用于 [EditorShellScreen] 顶部，提供「函数 / 数据库 / UI / 发布」四段切换。
///
/// 视觉特征：
/// - 圆角胶囊（BorderRadius.circular(28)）；
/// - 半透明背景 + 背景模糊（glassmorphism），主题自适应；
/// - 柔和投影（black 8% / blur 12 / offset (0,2)），让胶囊"浮"在内容之上；
/// - **单个滑动指示器**：选中态高亮块在四段之间**滑动**（而非各自淡入淡出），
///   切换时黑框从原位置平滑移动到新位置，过渡自然流畅；
/// - 高度约 56，按钮触控区充足，移动端友好。
///
/// 通过 [SafeArea] 适配状态栏，使用 [Stack]+[Positioned] 悬浮（不挤压内容区）。
class CapsuleTopBar extends ConsumerWidget {
  const CapsuleTopBar({super.key});

  /// 四段定义（顺序即视觉顺序）。
  static const _segments = <_SegmentDef>[
    _SegmentDef(EditorSegment.functions, '函数', Icons.functions),
    _SegmentDef(EditorSegment.database, '数据库', Icons.storage_outlined),
    _SegmentDef(EditorSegment.ui, 'UI', Icons.widgets_outlined),
    _SegmentDef(EditorSegment.publish, '发布', Icons.public),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = ref.watch(currentSegmentProvider);
    final selectedIndex = _segments.indexWhere((s) => s.segment == current);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cs.outlineVariant, width: 0.75),
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
                    color: cs.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  // 用 LayoutBuilder 取实际可用宽度，按段数均分，
                  // 滑动指示器据此定位。
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final segmentWidth =
                          constraints.maxWidth / _segments.length;
                      return Stack(
                        children: [
                          // 滑动指示器：单个高亮块，AnimatedPositioned 平滑移动。
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            left: selectedIndex * segmentWidth,
                            top: 0,
                            bottom: 0,
                            width: segmentWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                          // 四个段按钮（透明背景，仅承载文字与点击）。
                          Row(
                            children: [
                              for (var i = 0; i < _segments.length; i++)
                                Expanded(
                                  child: _SegmentButton(
                                    def: _segments[i],
                                    selected: i == selectedIndex,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
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

class _SegmentDef {
  const _SegmentDef(this.segment, this.label, this.icon);

  final EditorSegment segment;
  final String label;
  final IconData icon;
}

/// 胶囊内单个段切换按钮（透明背景，高亮由滑动指示器提供）。
class _SegmentButton extends ConsumerWidget {
  const _SegmentButton({required this.def, required this.selected});

  final _SegmentDef def;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(currentSegmentProvider.notifier).state = def.segment;
        },
        borderRadius: BorderRadius.circular(24),
        child: Center(
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
                  def.icon,
                  size: 18,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                def.label,
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
