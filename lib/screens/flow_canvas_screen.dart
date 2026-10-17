import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/focus_controller.dart';
import '../data/mock_data.dart';
import '../data/task_repository.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/motion.dart';
import '../widgets/petal_rain.dart';
import 'focus_timer_screen.dart';
import 'task_detail_screen.dart';

/// Task chain (your sketch): ONE box per task — task header on top,
/// subtask rows below it inside the same box (each with its own timer
/// circle), total-time bar at the bottom. Tapping any time opens the
/// full timer screen.
///
/// Data: `GET /api/tasks?include=subtasks,focus` (one round trip).
/// Automation engine untouched; rules still fire from the Flows tab.
class FlowCanvasScreen extends StatefulWidget {
  const FlowCanvasScreen({super.key});

  @override
  State<FlowCanvasScreen> createState() => _FlowCanvasScreenState();
}

class _FlowCanvasScreenState extends State<FlowCanvasScreen> {
  final _api = BloomApi();
  final _boardScroll = ScrollController();

  /// Card width + gutter everywhere on the desktop board: pager
  /// step and fits-on-screen check share it by construction.
  static const double _cardStep = 300 + 22;
  List<Task> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _boardScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tasks = await _api.fetchTasks(withDetails: true);
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load chains.')),
      );
    }
  }

  Future<void> _toggleSub(Subtask s, bool done) async {
    // Repository: optimistic + queued offline. Mirror the change into
    // this screen's local list so it stays correct without a refetch.
    await TaskRepository.instance.setSubtaskDone(s.id, done);
    if (!mounted) return;
    setState(() {
      _tasks = _tasks.map((t) {
        final subs = t.subtasks;
        if (subs == null) return t;
        final i = subs.indexWhere((x) => x.id == s.id);
        if (i == -1) return t;
        final updated = [...subs];
        updated[i] = subs[i].copyWith(done: done);
        return t.copyWith(subtasks: updated);
      }).toList();
    });
  }

  void _openTask(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(builder: (_) => TaskDetailScreen(task: t)))
        .then((_) => _load());
  }

  void _openTimer(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(builder: (_) => FocusTimerScreen(task: t)))
        .then((_) => _load()); // focused minutes may have grown
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      appBar: AppBar(
        backgroundColor: SakuraColors.background,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SakuraColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: SakuraColors.cardBorder),
            ),
            child: Tooltip(
              message: 'Back',
              child: Icon(LucideIcons.arrowLeft,
                  size: 18, color: SakuraColors.ink),
            ),
          ),
        ),
        title: Text(
          'Task flow',
          style: TextStyle(
              fontWeight: FontWeight.w800, color: SakuraColors.ink),
        ),
      ),
      body: PetalRain(
        petalCount: 12,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _tasks.isEmpty
                ? Center(
                    child: Text('No tasks yet — add one first.',
                        style: TextStyle(
                            color: SakuraColors.inkSoft)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Narrow (mobile): boxes stack top → bottom.
                      // Wide (desktop): boxes sit side by side.
                      final vertical =
                          constraints.maxWidth < 700;
                      if (!vertical) {
                        return _horizontalBoard();
                      }
                      return RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              20, 8, 20, 32),
                          itemCount: _tasks.length,
                          itemBuilder: (ctx, i) => Entrance(
                            key: ValueKey('flow-entrance-${_tasks[i].id}'),
                            onceKey: 'flow-${_tasks[i].id}',
                            delayMs: (i * 60).clamp(0, 300),
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 22),
                              child: _taskCard(_tasks[i]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  /// Desktop board: boxes scroll sideways, paged one card at a
  /// time with the edge arrows (card 300 + 22 gutter per step).
  /// Arrows hide at their edge — and entirely when every card fits.
  Widget _horizontalBoard() {
    // Fixed card geometry doubles as the pager step and the
    // fits-on-screen check, so both stay in sync by construction.
    return LayoutBuilder(
      builder: (context, c) {
        final fits = _tasks.length * _cardStep - 22 <= c.maxWidth;
        return AnimatedBuilder(
          animation: _boardScroll,
          builder: (context, _) {
            final ready = _boardScroll.hasClients;
            final pos = ready ? _boardScroll.offset : 0.0;
            final max =
                ready ? _boardScroll.position.maxScrollExtent : 1.0;
            final showLeft = ready && pos > 1;
            final showRight = !fits && (!ready || pos < max - 1);
            return Stack(
              children: [
                SingleChildScrollView(
                  controller: _boardScroll,
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _tasks.length; i++) ...[
                        if (i > 0) const SizedBox(width: 22),
                        Entrance(
                          key: ValueKey('flow-entrance-${_tasks[i].id}'),
                          onceKey: 'flow-${_tasks[i].id}',
                          delayMs: (i * 60).clamp(0, 300),
                          child: _taskCard(_tasks[i],
                              width: 300, capSubs: true),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showLeft)
                  Positioned(
                    left: 6,
                    // Fixed offset into the card band (not board center):
                    // centered in the whole board height the buttons sit
                    // in empty space and visually disappear.
                    top: 128,
                    child: _pageArrow(true),
                  ),
                if (showRight)
                  Positioned(
                    right: 6,
                    top: 128,
                    child: _pageArrow(false),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// One edge pager: previous / next card. No-op while the board
  /// hasn't laid out yet or already sits at that edge.
  Widget _pageArrow(bool back) {
    return GestureDetector(
      onTap: () => _pageBoard(back ? -1 : 1),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SakuraColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: SakuraColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          back ? Icons.chevron_left : Icons.chevron_right,
          size: 26,
          color: SakuraColors.primary,
        ),
      ),
    );
  }

  void _pageBoard(int dir) {
    if (!_boardScroll.hasClients) return;
    final target = (_boardScroll.offset + dir * _cardStep)
        .clamp(0.0, _boardScroll.position.maxScrollExtent);
    // Slow in-out glide: reads smoother than a quick out-cubic snap.
    _boardScroll.animateTo(
      target,
      duration: AppMotion.glide,
      curve: AppMotion.glideCurve,
    );
  }

  /// One box: crimson task header, subtask rows inside, black timer
  /// bar at the bottom. Desktop caps long stacks with inner scroll.
  Widget _taskCard(Task t, {double? width, bool capSubs = false}) {
    final subs = t.subtasks ?? [];
    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < subs.length; i++) ...[
          if (i > 0)
            Container(height: 1, color: SakuraColors.cardBorder),
          _subRow(t, subs[i]),
        ],
      ],
    );
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: SakuraColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SakuraColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: SakuraColors.primary.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(t),
          if (subs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 2),
              child: capSubs
                  ? ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxHeight: 300),
                      child:
                          SingleChildScrollView(child: rows),
                    )
                  : rows,
            ),
          _timerFooter(t),
        ],
      ),
    );
  }

  Widget _header(Task t) {
    return GestureDetector(
      onTap: () => _openTask(t),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SakuraColors.primary,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(LucideIcons.listChecks,
                  size: 19, color: SakuraColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TASK • ${t.tag.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _subRow(Task t, Subtask s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleSub(s, !s.done),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color:
                    s.done ? SakuraColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: s.done
                      ? SakuraColors.primary
                      : SakuraColors.inkFaint,
                  width: 1.5,
                ),
              ),
              child: s.done
                  ? const Icon(Icons.check,
                      size: 13, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _toggleSub(s, !s.done),
              behavior: HitTestBehavior.opaque,
              child: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: s.done
                      ? SakuraColors.inkFaint
                      : SakuraColors.ink,
                  decoration:
                      s.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _openTimer(t),
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              label: 'Start focus timer',
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: SakuraColors.primary, width: 1.5),
                ),
                child: Icon(LucideIcons.timer,
                    size: 13, color: SakuraColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Black total-time bar: HH:MM focused (your "05:50"), live orange
  /// countdown while a session runs. Tap → full timer screen.
  Widget _timerFooter(Task t) {
    return ListenableBuilder(
      listenable: FocusController.instance,
      builder: (context, _) {
        final fc = FocusController.instance;
        final live = fc.active && fc.task?.id == t.id;
        // Live digits tick every second; the static HH:MM total subscribes
        // to nothing — a session on ANOTHER task never repaints this bar.
        final label = live
            ? ValueListenableBuilder<int>(
                valueListenable: fc.tickListenable,
                builder: (context, _, __) =>
                    Text(formatCountdown(fc.remaining),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF9800),
                          fontFeatures: [
                            FontFeature.tabularFigures()
                          ],
                        )),
              )
            : Text(_hhmm(t.focusMinutes ?? 0),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ));
        return GestureDetector(
          onTap: () => _openTimer(t),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: live
                    ? const Color(0xFFFF9800)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.timer,
                  size: 15,
                  color: live
                      ? const Color(0xFFFF9800)
                      : Colors.white70,
                ),
                const SizedBox(width: 8),
                DefaultTextStyle.merge(
                  style: const TextStyle(letterSpacing: 2.2),
                  child: label,
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronRight,
                    size: 15, color: Colors.white38),
              ],
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
