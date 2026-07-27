import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/ui_tree.dart';
import '../../component_registry_v2.dart';
import 'keyframe_editor.dart';
import 'preset_editor.dart';

/// 动画配置面板（Phase 5.7）。
///
/// 包含三个可折叠区域：
/// 1. **入场动画**：[PresetAnimationEditor] 或 [KeyframeAnimationEditor]。
/// 2. **出场动画**：同上。
/// 3. **触发动画列表**：每项 = 事件选择 + 动画编辑器，支持添加 / 删除。
///
/// [events] 提供可用事件列表（来自组件 [ComponentDef.events]），
/// 用于触发动画的事件下拉选项。
class AnimationPanel extends ConsumerStatefulWidget {
  const AnimationPanel({
    super.key,
    required this.config,
    required this.onChanged,
    this.events = const [],
  });

  final AnimationsConfig? config;
  final ValueChanged<AnimationsConfig?> onChanged;
  final List<EventSpec> events;

  @override
  ConsumerState<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends ConsumerState<AnimationPanel> {
  bool _entranceExpanded = false;
  bool _exitExpanded = false;
  bool _triggeredExpanded = false;

  AnimationsConfig get _current =>
      widget.config ?? const AnimationsConfig();

  void _emit(AnimationsConfig next) => widget.onChanged(next);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: '入场动画',
          icon: Icons.login,
          expanded: _entranceExpanded,
          onToggle: () => setState(() => _entranceExpanded = !_entranceExpanded),
          configured: widget.config?.entrance != null,
          child: _SpecSlot(
            spec: widget.config?.entrance,
            label: '入场动画',
            events: widget.events,
            onChanged: (spec) {
              _emit(_current.copyWith(entrance: spec));
            },
            onClear: () {
              _emit(_current.copyWith(entrance: null));
            },
          ),
        ),
        const SizedBox(height: 6),
        _Section(
          title: '出场动画',
          icon: Icons.logout,
          expanded: _exitExpanded,
          onToggle: () => setState(() => _exitExpanded = !_exitExpanded),
          configured: widget.config?.exit != null,
          child: _SpecSlot(
            spec: widget.config?.exit,
            label: '出场动画',
            events: widget.events,
            onChanged: (spec) {
              _emit(_current.copyWith(exit: spec));
            },
            onClear: () {
              _emit(_current.copyWith(exit: null));
            },
          ),
        ),
        const SizedBox(height: 6),
        _Section(
          title: '触发动画',
          icon: Icons.flash_on,
          expanded: _triggeredExpanded,
          onToggle: () =>
              setState(() => _triggeredExpanded = !_triggeredExpanded),
          configured: (widget.config?.triggered ?? const []).isNotEmpty,
          child: _TriggeredSlot(
            config: widget.config,
            events: widget.events,
            onChanged: _emit,
          ),
        ),
      ],
    );
  }
}

/// 折叠区域。
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.configured,
    required this.child,
  });

  final String title;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final bool configured;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (configured)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '已配置',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.chevron_right,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// 单个 [AnimationSpec] 槽位：预设 / 关键帧切换 + 编辑器。
class _SpecSlot extends StatefulWidget {
  const _SpecSlot({
    required this.spec,
    required this.label,
    required this.events,
    required this.onChanged,
    required this.onClear,
  });

  final AnimationSpec? spec;
  final String label;
  final List<EventSpec> events;
  final ValueChanged<AnimationSpec> onChanged;
  final VoidCallback onClear;

  @override
  State<_SpecSlot> createState() => _SpecSlotState();
}

class _SpecSlotState extends State<_SpecSlot> {
  /// 编辑模式：true = 预设，false = 关键帧。
  bool _presetMode = true;

  @override
  void initState() {
    super.initState();
    _syncMode(widget.spec);
  }

  @override
  void didUpdateWidget(covariant _SpecSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) _syncMode(widget.spec);
  }

  void _syncMode(AnimationSpec? spec) {
    if (spec == null) {
      _presetMode = true;
      return;
    }
    // 已有 keyframes 时切到关键帧模式；已有 preset 时切到预设模式。
    if (spec.keyframes.isNotEmpty && spec.preset == null) {
      _presetMode = false;
    } else if (spec.preset != null) {
      _presetMode = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 模式切换
        Row(
          children: [
            _ModeChip(
              label: '预设',
              selected: _presetMode,
              onTap: () {
                if (!_presetMode) {
                  setState(() => _presetMode = true);
                  // 切到预设时若无 preset，初始化 fade。
                  final s = widget.spec;
                  if (s == null || s.preset == null) {
                    widget.onChanged(const AnimationSpec(
                      preset: AnimationPreset.fade,
                      duration: 300,
                    ));
                  }
                }
              },
            ),
            const SizedBox(width: 4),
            _ModeChip(
              label: '关键帧',
              selected: !_presetMode,
              onTap: () {
                if (_presetMode) {
                  setState(() => _presetMode = false);
                  // 切到关键帧时若无 keyframes，初始化默认两端帧。
                  final s = widget.spec;
                  if (s == null || s.keyframes.isEmpty) {
                    widget.onChanged(const AnimationSpec(
                      keyframes: [
                        Keyframe(
                          time: 0.0,
                          properties: KeyframeProperties(
                              opacity: 0.0, scale: 0.5),
                          easing: EasingType.easeOut,
                        ),
                        Keyframe(
                          time: 1.0,
                          properties: KeyframeProperties(
                              opacity: 1.0, scale: 1.0),
                        ),
                      ],
                      duration: 600,
                    ));
                  }
                }
              },
            ),
            const Spacer(),
            if (widget.spec != null)
              InkWell(
                onTap: widget.onClear,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close,
                      size: 14, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_presetMode)
          PresetAnimationEditor(
            spec: widget.spec,
            onChanged: widget.onChanged,
            label: widget.label,
          )
        else
          KeyframeAnimationEditor(
            spec: widget.spec,
            onChanged: widget.onChanged,
            label: widget.label,
          ),
      ],
    );
  }
}

/// 模式切换 chip。
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// 触发动画列表槽位。
class _TriggeredSlot extends ConsumerStatefulWidget {
  const _TriggeredSlot({
    required this.config,
    required this.events,
    required this.onChanged,
  });

  final AnimationsConfig? config;
  final List<EventSpec> events;
  final ValueChanged<AnimationsConfig?> onChanged;

  @override
  ConsumerState<_TriggeredSlot> createState() => _TriggeredSlotState();
}

class _TriggeredSlotState extends ConsumerState<_TriggeredSlot> {
  String? _selectedEventToAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final triggered = widget.config?.triggered ?? const [];
    final availableEvents = widget.events.isEmpty
        ? const <EventSpec>[
            EventSpec(name: 'onTap', label: '点击'),
            EventSpec(name: 'onLongPress', label: '长按'),
            EventSpec(name: 'onDoubleTap', label: '双击'),
          ]
        : widget.events;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (triggered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '尚无触发动画。从下方选择事件并添加。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        for (int i = 0; i < triggered.length; i++)
          _TriggeredItemEditor(
            key: ValueKey('triggered-$i-${triggered[i].event}'),
            item: triggered[i],
            events: availableEvents,
            onChanged: (next) {
              final list = List<TriggeredAnimation>.from(triggered);
              list[i] = next;
              widget.onChanged(
                  (widget.config ?? const AnimationsConfig())
                      .copyWith(triggered: list));
            },
            onDelete: () {
              final list = List<TriggeredAnimation>.from(triggered)
                ..removeAt(i);
              widget.onChanged(
                  (widget.config ?? const AnimationsConfig())
                      .copyWith(triggered: list));
            },
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedEventToAdd,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '选择事件',
                ),
                items: [
                  for (final e in availableEvents)
                    DropdownMenuItem(value: e.name, child: Text(e.label)),
                ],
                onChanged: (v) =>
                    setState(() => _selectedEventToAdd = v),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              icon: const Icon(Icons.add, size: 18),
              tooltip: '添加触发动画',
              onPressed: () {
                final event = _selectedEventToAdd ??
                    (availableEvents.isEmpty
                        ? 'onTap'
                        : availableEvents.first.name);
                if (event.isEmpty) return;
                final cur =
                    widget.config ?? const AnimationsConfig();
                final newList = [
                  ...cur.triggered,
                  TriggeredAnimation(
                    event: event,
                    animation: const AnimationSpec(
                      preset: AnimationPreset.fade,
                      duration: 300,
                    ),
                  ),
                ];
                widget.onChanged(cur.copyWith(triggered: newList));
                setState(() => _selectedEventToAdd = null);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 单个触发动画项编辑器：事件标签 + 动画编辑器 + 删除按钮。
class _TriggeredItemEditor extends ConsumerStatefulWidget {
  const _TriggeredItemEditor({
    super.key,
    required this.item,
    required this.events,
    required this.onChanged,
    required this.onDelete,
  });

  final TriggeredAnimation item;
  final List<EventSpec> events;
  final ValueChanged<TriggeredAnimation> onChanged;
  final VoidCallback onDelete;

  @override
  ConsumerState<_TriggeredItemEditor> createState() =>
      _TriggeredItemEditorState();
}

class _TriggeredItemEditorState extends ConsumerState<_TriggeredItemEditor> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final eventLabel = _labelFor(widget.item.event);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.flash_on, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$eventLabel · ${widget.item.animation.preset?.name ?? "关键帧"} · ${widget.item.animation.duration.round()}ms',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: widget.onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close,
                          size: 14, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.chevron_right,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 事件下拉（可切换为其他事件）
                  DropdownButtonFormField<String>(
                    value: widget.item.event,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: '事件',
                    ),
                    items: [
                      for (final e in widget.events)
                        DropdownMenuItem(
                            value: e.name, child: Text(e.label)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      widget.onChanged(widget.item.copyWith(event: v));
                    },
                  ),
                  const SizedBox(height: 8),
                  PresetAnimationEditor(
                    spec: widget.item.animation,
                    label: '动画',
                    onChanged: (next) =>
                        widget.onChanged(widget.item.copyWith(animation: next)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _labelFor(String eventName) {
    final match = widget.events
        .where((e) => e.name == eventName)
        .toList(growable: false);
    if (match.isEmpty) return eventName;
    return match.first.label;
  }
}
