import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants.dart';
import '../../../features/database/segment_view.dart';
import '../../../features/functions/segment_view.dart';
import '../../../features/project/project_providers.dart';
import '../../../features/ui_editor/segment_view.dart';
import '../../widgets/capsule_top_bar.dart';

/// 项目编辑器宿主屏幕。
///
/// 接收 [projectId]，打开项目并置入 [currentProjectProvider]；
/// 顶部悬浮 [CapsuleTopBar]，下方用 [IndexedStack] 承载三段内容，
/// 切换段时各段 widget state 保留（IndexedStack 保活所有子 widget）。
class EditorShellScreen extends ConsumerStatefulWidget {
  const EditorShellScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<EditorShellScreen> createState() => _EditorShellScreenState();
}

class _EditorShellScreenState extends ConsumerState<EditorShellScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 在首帧后加载项目，避免在 build 期间触发状态变更。
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProject());
  }

  Future<void> _loadProject() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(projectRepositoryProvider);
      final project = await repo.openProject(widget.projectId);
      if (!mounted) return;
      if (project == null) {
        setState(() {
          _loading = false;
          _error = '项目不存在或已被删除';
        });
        return;
      }
      ref.read(currentProjectProvider.notifier).state = project;
      // 进入编辑器默认回到函数段。
      ref.read(currentSegmentProvider.notifier).state = EditorSegment.functions;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '打开项目失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final segment = ref.watch(currentSegmentProvider);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 12),
              Text(_error!),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('返回主页'),
              ),
            ],
          ),
        ),
      );
    }

    // 三段切换：使用 AnimatedSwitcher 实现淡入淡出 + 轻微位移（原路反向）。
    // IndexedStack 保活所有子 widget state；外层 AnimatedSwitcher 仅做切换过渡。
    final children = const [
      FunctionsSegmentView(),
      DatabaseSegmentView(),
      UiEditorSegmentView(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(segment.index),
                child: IndexedStack(
                  index: segment.index,
                  children: children,
                ),
              ),
            ),
          ),
          // 悬浮胶囊 Top 栏，覆盖于内容之上。
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CapsuleTopBar(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppConstants.buildRoute(widget.projectId)),
        icon: const Icon(Icons.build_outlined),
        label: const Text('编译打包'),
      ),
    );
  }
}
