import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/energy_store.dart';
import '../data/focus_controller.dart';
import '../data/haptics.dart';
import '../data/mock_data.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import 'petal_burst.dart';
import 'timeline_rail.dart';

/// Sketch-style task card: main task on top, subtasks below, timer
/// chip beside (bottom-right). Tapping the time opens the full timer.
///
/// [widget.task.subtasks]/[widget.task.focusMinutes] come from
/// `GET /api/tasks?include=subtasks,focus`; when absent the card
/// renders exactly like before (search results, mock mode).
///
/// Tap areas are *siblings*, never nested: [widget.onToggle] covers the text
/// regions, [widget.onOpen] is the chevron. (Nested tap detectors both fire in
/// Flutter, so a chevron inside a toggle area would toggle AND open.)
class TaskCard extends StatefulWidget {
  final Task task;
  final VoidCallback? onToggle;
  final VoidCallback? onOpen;
  final void Function(Subtask sub, bool done)? onToggleSub;
  final VoidCallback? onTimerTap;

  /// Long-press opens the quick reschedule/delete menu. Owned by the
  /// hosting list (it has the repository + context); null disables it.
  final VoidCallback? onLongPress;

  /// Shared-element tag for the timer chip → [FocusTimerScreen] flight.
  /// Null disables the Hero (search rows, chipless cards). When set, the
  /// pushing screen must pass the identical tag to the timer screen —
  /// tags embed a per-screen prefix (`home-focus-…`) so the same task
  /// rendered on two kept-alive tabs can never collide.
  final String? heroTag;

  const TaskCard(
      {super.key,
      required this.task,
      this.onToggle,
      this.onOpen,
      this.onToggleSub,
      this.onTimerTap,
      this.onLongPress,
      this.heroTag});

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  /// Subtask accordion: tasks with more than 2 subtasks render a compact
  /// progress badge until tapped. Keeps list cards short; detail drill-in
  /// stays one tap away via the title/chevron.
  bool _subsExpanded = false;

  /// Main card body / title tap -> open the task detail. Completion has
  /// its own dedicated ring so the two targets never compete.
  void _openTask() => widget.onOpen?.call();

  /// Free-form subtask toggle — no confirm dialog and no lock-in.
  /// Completed -> a petal flourish + double-pulse (the [PetalBurst]
  /// wrapping the row owns those) plus a 3s UNDO snackbar. UNDO calls the
  /// parent handler directly so it never stacks a second snackbar.
  void _toggleSubWithUndo(BuildContext context, Subtask s) {
    final handler = widget.onToggleSub;
    if (handler == null) return;
    final next = !s.done;
    handler(s, next);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(next ? 'Subtask done 🌸' : 'Subtask reopened'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => handler(s, !next),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final overdue = widget.task.dueAt != null &&
        widget.task.dueAt!.isBefore(DateTime.now()) &&
        widget.task.status != 'done';
    final subs = widget.task.subtasks;
    return GestureDetector(
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: SakuraTheme.flatCardDecoration(),
      // Tap targets are siblings, never nested: the title block below owns
      // [widget.onOpen]; the ring, subtasks and timer chip own theirs. (A
      // card-wide GestureDetector would share the arena with the subtask
      // detectors inside it.)
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SakuraColors.tagBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.task.tag.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.tagText,
                    ),
                  ),
                ),
                if (widget.task.priority != 'none') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.task.priority == 'high'
                          ? SakuraColors.primary.withValues(alpha: 0.15)
                          : SakuraColors.tagBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.task.priority.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: widget.task.priority == 'high'
                            ? SakuraColors.primary
                            : SakuraColors.inkSoft,
                      ),
                    ),
                  ),
                ],
                if (widget.task.recurring != 'none') ...[
                  const SizedBox(width: 6),
                  Icon(LucideIcons.repeat, size: 12, color: SakuraColors.inkSoft),
                ],
                ListenableBuilder(
                  listenable: EnergyStore.instance,
                  builder: (context, _) {
                    final level =
                        EnergyStore.instance.levelFor(widget.task.id);
                    if (level == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: SakuraColors.tagBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(energyIcon(level),
                                size: 10,
                                color: SakuraColors.tagText),
                            const SizedBox(width: 3),
                            Text(
                              energyLabel(level).toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: SakuraColors.tagText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                Icon(
                  LucideIcons.messageCircle,
                  size: 14,
                  color: SakuraColors.inkFaint,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.task.comments}',
                  style: TextStyle(
                    fontSize: 12,
                    color: SakuraColors.inkSoft,
                    fontFeatures: const [
                      FontFeature.tabularFigures()
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 13,
                  backgroundColor: SakuraColors.primarySoft,
                  child: Text(
                    widget.task.avatarLabel.characters.first,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompletionRing(
                done: widget.task.status == 'done',
                onTap: widget.onToggle,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  // Title / description block owns "open" — ring, subtasks
                  // and timer chip are siblings with their own detectors.
                  onTap: widget.onOpen == null ? null : _openTask,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: SakuraColors.ink,
                        ),
                      ),
                      if (widget.task.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.task.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: SakuraColors.inkSoft,
                          ),
                        ),
                      ],
                    if (widget.task.dueAt != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (overdue || isDueToday(widget.task))
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: overdue
                                    ? SakuraColors.primary
                                    : SakuraColors.primary
                                        .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                overdue ? 'OVERDUE' : 'DUE TODAY',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: overdue
                                      ? Colors.white
                                      : SakuraColors.primary,
                                ),
                              ),
                            ),
                          Icon(
                            LucideIcons.calendarDays,
                            size: 12,
                            color: overdue
                                ? SakuraColors.primary
                                : SakuraColors.inkFaint,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${overdue ? 'Overdue · ' : 'Due '}${DateFormat('MMM d').format(widget.task.dueAt!.toLocal())}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: overdue
                                  ? SakuraColors.primary
                                  : SakuraColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
              if (widget.onOpen != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onOpen,
                  behavior: HitTestBehavior.opaque,
                  child: Semantics(
                    button: true,
                    label: 'Open task',
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: SakuraColors.inkFaint,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Same created -> done rail the detail screen draws, so a card
          // reads as a live slice of the task's timeline. Hidden when the
          // server sent no created_at (mock/offline rows).
          if (widget.task.createdAt != null) ...[
            const SizedBox(height: 10),
            TimelineRail(
              created: widget.task.createdAt,
              completed: widget.task.completedAt,
              done: widget.task.status == 'done',
            ),
          ],
          if (subs != null && subs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: SakuraColors.cardBorder),
            const SizedBox(height: 6),
            if (subs.length > 2 && !_subsExpanded)
              // Compact accordion badge: progress at a glance, tap to
              // expand the checklist inline. Keeps tall cards short.
              GestureDetector(
                onTap: () => setState(() => _subsExpanded = true),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.listChecks,
                        size: 13,
                        color: SakuraColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '✓ ${subs.where((s) => s.done).length}/${subs.length} subtasks',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SakuraColors.inkSoft,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '[Show]',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: SakuraColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ...subs.map((s) => _subRow(context, s)),
              if (subs.length > 2)
                GestureDetector(
                  onTap: () => setState(() => _subsExpanded = false),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        const Spacer(),
                        Text(
                          '[Hide]',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
          if (widget.task.focusMinutes != null || subs != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (subs != null && subs.isNotEmpty)
                  Text(
                    '${subs.where((s) => s.done).length}/${subs.length} subtasks',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                const Spacer(),
                if (widget.onTimerTap != null)
                  Builder(builder: (context) {
                    final tag = widget.heroTag;
                    if (tag == null) return _timerChip();
                    return Hero(tag: tag, child: _timerChip());
                  }),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }

  /// One checklist row. Extracted so the accordion badge and the
  /// expanded list share it.
  Widget _subRow(BuildContext context, Subtask s) {
    return Semantics(
      button: true,
      label: s.done ? 'Reopen subtask ${s.title}' : 'Complete subtask ${s.title}',
      child: PetalBurst(
        // Free toggle: a finished subtask can be reopened.
        // Burst + double-pulse only fire when checking off.
        burstOnTap: !s.done,
        petalCount: 6,
        onTap: widget.onToggleSub == null
            ? null
            : () => _toggleSubWithUndo(context, s),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: s.done ? SakuraColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color:
                      s.done ? SakuraColors.primary : SakuraColors.inkFaint,
                  width: 1.5,
                ),
              ),
              child: s.done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: s.done ? SakuraColors.inkFaint : SakuraColors.ink,
                  decoration: s.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Timer chip beside the card: total focused time as HH:MM (your
  /// sketch's "05:50"), live orange countdown while a session runs.
  /// Tap → full timer screen.
  Widget _timerChip() {
    return ListenableBuilder(
      // Structural only (session started/finished on some task). The
      // per-second digits below subscribe on their own, so a running
      // timer never rebuilds every card in the list each second.
      listenable: FocusController.instance,
      builder: (context, _) {
        final fc = FocusController.instance;
        final live =
            fc.active && fc.task?.id == widget.task.id;
        final label = live
            ? ValueListenableBuilder<int>(
                valueListenable: fc.tickListenable,
                builder: (context, _, __) =>
                    Text(formatCountdown(fc.remaining),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [
                            FontFeature.tabularFigures()
                          ],
                          color: Color(0xFFFF9800),
                        )),
              )
            : Text(_hhmm(widget.task.focusMinutes ?? 0),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: SakuraColors.primary,
                ));
        return Semantics(
          button: true,
          label: live ? 'Open running focus timer' : 'Start focus timer',
          child: GestureDetector(
            onTap: widget.onTimerTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: live
                    ? const Color(0xFFFF9800).withValues(alpha: 0.12)
                    : SakuraColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: live
                      ? const Color(0xFFFF9800)
                      : SakuraColors.cardBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.timer,
                    size: 13,
                    color: live
                        ? const Color(0xFFFF9800)
                        : SakuraColors.primary,
                  ),
                  const SizedBox(width: 5),
                  label,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _hhmm(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Circular completion toggle: an empty ring grows into a filled primary
/// disc. Kept separate from the card-body tap so "open" and "complete"
/// never fight over the same target. Checking off (not reopening) fires
/// the blossom burst + double-pulse.
class _CompletionRing extends StatelessWidget {
  final bool done;
  final VoidCallback? onTap;

  const _CompletionRing({required this.done, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: done ? 'Reopen task' : 'Mark task done',
      child: PetalBurst(
        burstOnTap: !done,
        onTap: onTap == null
            ? null
            : () {
                AppHaptics.tap();
                onTap!();
              },
        child: AnimatedContainer(
          duration: AppMotion.toggle,
          curve: AppMotion.toggleCurve,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: done ? SakuraColors.primary : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? SakuraColors.primary : SakuraColors.inkFaint,
              width: 2,
            ),
          ),
          child: done
              ? const Icon(Icons.check, size: 15, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
