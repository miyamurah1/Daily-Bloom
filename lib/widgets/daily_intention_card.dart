import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/mock_data.dart';
import '../game/bloom_game_colors.dart';
import '../game/daily_intention.dart';
import '../screens/task_detail_screen.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import 'motion.dart';

/// Sleek daily-target card for the top of Home: today's intention +
/// a thin animated bar. At 100% the bar fills and the card breathes a
/// soft neon-pink glow.
///
/// Tapping the fulfilled card calls [onTargetMet] exactly once per day
/// (the hook for the mystery token drop). Nothing ever pops up on its
/// own — the user always initiates the gather.
///
/// Built only on framework primitives: [TweenAnimationBuilder] for the
/// fill, one repeat-reverse controller for the glow. No game engines.
class DailyIntentionCard extends StatefulWidget {
  final DailyIntentionNotifier? intention;
  final VoidCallback? onTargetMet;

  /// Compact cell for the Home bento header (~70px): icon + title +
  /// progress + thin bar. Same gather/edit behaviour, smaller footprint.
  final bool compact;

  const DailyIntentionCard({
    super.key,
    this.intention,
    this.onTargetMet,
    this.compact = false,
  });

  @override
  State<DailyIntentionCard> createState() =>
      _DailyIntentionCardState();
}

class _DailyIntentionCardState extends State<DailyIntentionCard> {
  DailyIntentionNotifier get _game =>
      widget.intention ?? DailyIntentionNotifier.instance;

  /// Day-key the drop was already gathered for — the once-gate.
  String? _gatheredKey;

  /// Fully-loaded pinned tasks (subtasks + timestamps) by id, for the
  /// `task` kind only. Fetched lazily: the notifier stores just
  /// id/title/done, so the rows still draw while this is empty.
  Map<String, Task> _pinnedById = const {};
  String? _pinnedForKey;

  @override
  void initState() {
    super.initState();
    // Restore the user's own target (if set) without blocking paint.
    unawaited(_game.loadCustom());
    _game.addListener(_syncPinned);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPinned());
  }

  @override
  void dispose() {
    _game.removeListener(_syncPinned);
    super.dispose();
  }

  /// Keeps [_pinnedById] in step with the notifier's pins: refetch when
  /// the id list changes, clear when the target stops pinning tasks.
  void _syncPinned() {
    final ids = _game.pinnedTaskIds;
    if (ids.isEmpty) {
      if (_pinnedById.isNotEmpty || _pinnedForKey != null) {
        setState(() {
          _pinnedById = const {};
          _pinnedForKey = null;
        });
      }
      return;
    }
    final key = ids.join(',');
    if (key == _pinnedForKey) return;
    _pinnedForKey = key;
    unawaited(_loadPinned(key, List<String>.of(ids)));
  }

  Future<void> _loadPinned(String key, List<String> ids) async {
    try {
      final tasks = await BloomApi().fetchTasks(withDetails: true);
      if (!mounted || _pinnedForKey != key) return;
      final hits = <String, Task>{
        for (final t in tasks)
          if (ids.contains(t.id)) t.id: t,
      };
      setState(() => _pinnedById = hits);
      // Server truth: pins finished anywhere count as done here.
      if (hits.isNotEmpty) {
        await _game.setPinsDone(<String>{
          for (final e in hits.entries)
            if (e.value.status == 'done') e.key,
        });
      }
    } catch (_) {
      // Offline: keep the notifier's titles/done as last known truth.
    }
  }

  /// Deep-link into one pinned task; on return the counts may have moved.
  Future<void> _openPinned(String id) async {
    final t = _pinnedById[id];
    if (t == null) {
      // Details not loaded yet: refresh the notifier's done-set only.
      await _game.refresh();
      return;
    }
    await Navigator.of(context).push(
      SakuraPageRoute(builder: (_) => TaskDetailScreen(task: t)),
    );
    if (!mounted) return;
    await _game.refresh();
    unawaited(_reloadPinned());
  }

  /// Force a re-read of the pins (after the detail screen touched one).
  Future<void> _reloadPinned() async {
    _pinnedForKey = null;
    _syncPinned();
  }

  void _gather() {
    if (!mounted) return;
    if (!_game.met || _gatheredKey == _game.dayKey) return;
    _gatheredKey = _game.dayKey;
    widget.onTargetMet?.call();
  }

  Future<void> _customize() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: SakuraColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _TargetEditorSheet(game: _game),
    );
  }

  /// The pinned-task links: one small row per pin — subtask progress and
  /// elapsed time, tap to open the real task. Titles come from the
  /// notifier, so the rows still draw offline.
  Widget _pinnedRows() {
    final ids = _game.pinnedTaskIds;
    final titles = _game.pinnedTaskTitles;
    return Column(
      children: [
        for (var i = 0; i < ids.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _pinnedRow(ids[i], i < titles.length ? titles[i] : ''),
        ],
      ],
    );
  }

  Widget _pinnedRow(String id, String fallbackTitle) {
    final t = _pinnedById[id];
    final title = (t != null && t.title.isNotEmpty) ? t.title : fallbackTitle;
    final subs = t?.subtasks ?? const <Subtask>[];
    final openSubs = subs.where((s) => !s.done).length;
    final elapsed = t == null ? null : taskElapsed(t);
    final done = _game.pinnedDoneIds.contains(id);
    // One pin already has its title in the headline; several need each
    // row to name itself.
    final named = _game.pinnedTaskIds.length > 1;

    final bits = <String>[
      if (done)
        'done'
      else
        'open',
      if (subs.isNotEmpty) '$openSubs of ${subs.length} subtasks left',
      if (elapsed != null && subs.isEmpty)
        '${done ? 'took' : 'open for'} ${fmtElapsed(elapsed)}',
    ];

    return GestureDetector(
      onTap: () => _openPinned(id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: SakuraColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_outline_rounded
                  : Icons.open_in_new_rounded,
              size: 14,
              color: SakuraColors.primary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (named && title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: SakuraColors.ink,
                      ),
                    ),
                  Text(
                    bits.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              done ? 'REVIEW' : 'OPEN TASK',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
                color: SakuraColors.primary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                size: 15, color: SakuraColors.primary),
          ],
        ),
      ),
    );
  }

  /// Condensed bento cell: identity row + thin animated fill. Everything
  /// the full card does (gather, customise, pinned opening) still works —
  /// only the vertical rhythm is tightened.
  Widget _compactCard(bool met) {
    final target = _game.target;
    final subtitle = met
        ? 'Tap to gather'
        : target.kind == IntentionKind.task && _game.pinnedTaskIds.isNotEmpty
            ? '${_game.pinnedTaskIds.length} task'
                '${_game.pinnedTaskIds.length == 1 ? '' : 's'} pinned'
            : target.title;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: met
              ? [
                  SakuraColors.primary.withValues(alpha: 0.16),
                  SakuraColors.surface,
                ]
              : [
                  SakuraColors.primary.withValues(alpha: 0.08),
                  SakuraColors.surface,
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: met
              ? SakuraColors.primary.withValues(alpha: 0.5)
              : SakuraColors.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: SakuraColors.primary.withValues(alpha: met ? 0.16 : 0.07),
            blurRadius: met ? 16 : 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Fill the 130px bento cell: the headline block pins to the top
        // and the bar + count row pins to the bottom. A min-size column
        // left a dead band under the bar — the cell read half-empty
        // beside the evenly-distributed GameHud on phones.
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: met
                      ? SakuraColors.primary
                      : SakuraColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  met ? Icons.local_florist_outlined : Icons.spa_outlined,
                  size: 13,
                  color: met ? Colors.white : SakuraColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      met ? 'Your bloom is ready' : "Today's focus",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: SakuraColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: met ? SakuraColors.primary : SakuraColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // The count rides the bar row: the number sits beside the
          // progress it describes, and the headline row keeps the full
          // width for the target title on phones.
          Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _game.fraction),
                  duration: AppMotion.progress,
                  curve: AppMotion.progressCurve,
                  builder: (context, v, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      backgroundColor: SakuraColors.primarySoft,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          SakuraColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_game.progress.clamp(0, 1 << 30)}/${_game.goal}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return GestureDetector(
      onTap: met ? _gather : _customize,
      behavior: HitTestBehavior.opaque,
      child: met ? _CelebrationGlow(child: card) : card,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_game, ThemeStore.instance]),
      builder: (context, _) {
        final met = _game.met;
        if (widget.compact) return _compactCard(met);
        final card = Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: met
                  ? [
                      SakuraColors.primary.withValues(alpha: 0.16),
                      SakuraColors.surface,
                    ]
                  : [
                      SakuraColors.primary.withValues(alpha: 0.08),
                      SakuraColors.surface,
                    ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: met
                  ? SakuraColors.primary.withValues(alpha: 0.5)
                  : SakuraColors.cardBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: SakuraColors.primary.withValues(
                    alpha: met ? 0.18 : 0.08),
                blurRadius: met ? 24 : 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: met
                          ? SakuraColors.primary
                          : SakuraColors.primary
                              .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      met
                          ? Icons.local_florist_outlined
                          : Icons.spa_outlined,
                      size: 14,
                      color: met
                          ? Colors.white
                          : SakuraColors.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          met
                              ? 'Your bloom is ready'
                              : "Today's focus",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: SakuraColors.ink,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          met
                              ? 'Tap to gather it'
                              : (_game.isCustom
                                  ? 'Your own intention'
                                  : 'A gentle suggestion — make it yours'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: met
                                ? SakuraColors.primary
                                : SakuraColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_game.progress.clamp(0, 1 << 30)}/${_game.goal}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: SakuraColors.ink,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: SakuraColors.primary
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: SakuraColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                met
                    ? 'Beautiful — your intention bloomed.'
                    : _game.target.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: SakuraColors.ink,
                ),
              ),
              if (_game.target.kind == IntentionKind.task) ...[
                const SizedBox(height: 8),
                _pinnedRows(),
              ],
              const SizedBox(height: 12),
              // Thin fill: animates on every progress change.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                    begin: 0, end: _game.fraction),
                duration: AppMotion.progress,
                curve: AppMotion.progressCurve,
                builder: (context, v, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor:
                        SakuraColors.primarySoft,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(
                            SakuraColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Operable footer: visual hint only — the outer card tap
              // handles gather/customize so there is exactly one gesture.
              Row(
                  children: [
                    Icon(
                      met
                          ? Icons.local_florist_outlined
                          : Icons.tune_rounded,
                      size: 13,
                      color: met
                          ? SakuraColors.primary
                          : SakuraColors.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        met
                            ? 'Tap to gather your bloom'
                            : _game.target.kind == IntentionKind.task
                                ? _game.pinnedTaskIds.length > 1
                                    ? 'Open a task below · tap card to edit'
                                    : 'Open the task below · tap card to edit'
                                : 'Tap the card to set your own target',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: met
                              ? SakuraColors.primary
                              : SakuraColors.inkSoft,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SakuraColors.primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _game.isCustom ? 'Yours' : 'Suggested',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: SakuraColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
        return GestureDetector(
          onTap: met ? _gather : _customize,
          behavior: HitTestBehavior.opaque,
          child: met ? _CelebrationGlow(child: card) : card,
        );
      },
    );
  }
}

/// One repeat-reverse controller breathing a pink [BoxShadow].
/// Mounted only while the target is met, so it costs nothing otherwise.
///
/// Perf: the shadow itself is a stable decoration rasterized once — the
/// breath rides a [FadeTransition] layer (alpha-only update). Mutating
/// `BoxShadow.color` per frame (old code) re-blurred 26px at 60×/sec on
/// the Home screen whenever the daily target was met.
class _CelebrationGlow extends StatefulWidget {
  final Widget child;
  const _CelebrationGlow({required this.child});

  @override
  State<_CelebrationGlow> createState() => _CelebrationGlowState();
}

class _CelebrationGlowState extends State<_CelebrationGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: AppMotion.glow,
    );
    // Alpha rides the layer (min → max) — matches the old per-frame
    // `withValues(alpha: 0.14 + 0.14 * _c.value)` exactly.
    _breath = Tween<double>(
            begin: BloomGameColors.glowCelebrateMin,
            end: BloomGameColors.glowCelebrateMax)
        .animate(
      CurvedAnimation(parent: _c, curve: AppMotion.settleInCurve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced-motion: hold a steady glow (no breathing).
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _breath,
            child: DecoratedBox(
              // Built once per build (not per frame); primary follows the
              // active theme, so it can't be const. Alpha-kept: a full
              // opacity primary glow blooms white-hot on dark themes.
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: SakuraColors.primary.withValues(alpha: 0.35),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Set-your-own-target sheet: Tasks count, Focus minutes, or the tasks
/// you pick (finish them + their subtasks today). Saving stores today's
/// override — until midnight, then the suggested rotation resumes.
class _TargetEditorSheet extends StatefulWidget {
  final DailyIntentionNotifier game;
  const _TargetEditorSheet({required this.game});

  @override
  State<_TargetEditorSheet> createState() => _TargetEditorSheetState();
}

class _TargetEditorSheetState extends State<_TargetEditorSheet> {
  late IntentionKind _kind;
  late int _goal;
  bool _saving = false;
  bool _tracking = false;

  /// Picked pins, id → title, in the order they were tapped.
  final Map<String, String> _picked = <String, String>{};
  bool _loadingTasks = false;
  String? _tasksError;
  List<Task> _openTasks = [];

  @override
  void initState() {
    super.initState();
    _kind = widget.game.target.kind;
    _goal = widget.game.target.goal;
    final ids = widget.game.target.taskIds.isNotEmpty
        ? widget.game.target.taskIds
        : widget.game.pinnedTaskIds;
    final titles = widget.game.target.taskTitles.isNotEmpty
        ? widget.game.target.taskTitles
        : widget.game.pinnedTaskTitles;
    for (var i = 0; i < ids.length; i++) {
      _picked[ids[i]] = i < titles.length ? titles[i] : '';
    }
    if (_kind == IntentionKind.task) _loadOpenTasks();
  }

  int get _step => _kind == IntentionKind.tasks ? 1 : 5;
  int get _min => _kind == IntentionKind.tasks ? 1 : 5;
  int get _max => _kind == IntentionKind.tasks ? 20 : 180;

  void _pickKind(IntentionKind kind) {
    setState(() {
      _kind = kind;
      // Snap the goal into the new kind's range.
      _goal = DailyIntentionNotifier.clampGoal(kind, _goal);
      if (kind == IntentionKind.task) _loadOpenTasks();
    });
  }

  Future<void> _loadOpenTasks() async {
    if (_loadingTasks) return;
    setState(() {
      _loadingTasks = true;
      _tasksError = null;
    });
    try {
      final tasks = await BloomApi().fetchTasks(withDetails: true);
      if (!mounted) return;
      final open = tasks.where((t) => t.status != 'done').toList()
        ..sort((a, b) {
          final ad = a.dueAt;
          final bd = b.dueAt;
          if (ad == null && bd == null) return a.title.compareTo(b.title);
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });
      setState(() {
        // Keep picked titles fresh (a task may have been renamed); a pin
        // that is already done is simply not offered here, but it stays
        // part of today's target.
        for (final t in tasks) {
          if (_picked.containsKey(t.id)) _picked[t.id] = t.title;
        }
        _openTasks = open.take(30).toList();
        _loadingTasks = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTasks = false;
        _tasksError = 'Could not load tasks — check the API.';
      });
    }
  }

  String get _summary {
    if (_kind == IntentionKind.task) {
      if (_picked.isEmpty) return 'Pick the tasks you’ll finish today';
      return DailyIntentionNotifier.taskTitlesOf(_picked.values.toList());
    }
    return DailyIntentionNotifier.customTitle(_kind, _goal);
  }

  bool get _canSave {
    if (_saving) return false;
    if (_kind == IntentionKind.task) return _picked.isNotEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today’s target',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      widget.game.isCustom
                          ? 'Yours until midnight'
                          : 'Suggested — make it yours',
                      style: TextStyle(
                          fontSize: 12,
                          color: SakuraColors.inkSoft),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close,
                    size: 18, color: SakuraColors.inkSoft),
                style: IconButton.styleFrom(
                  backgroundColor: SakuraColors.background,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _kindChip(IntentionKind.tasks)),
              const SizedBox(width: 10),
              Expanded(child: _kindChip(IntentionKind.focus)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _kindChip(IntentionKind.task),
          ),
          const SizedBox(height: 14),
          if (_kind == IntentionKind.task) _taskPicker(),
          if (_kind != IntentionKind.task)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: SakuraColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SakuraColors.cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Decrease goal',
                  onPressed: _goal > _min
                      ? () => setState(() => _goal -= _step)
                      : null,
                  icon: const Icon(Icons.remove, size: 18),
                ),
                Column(
                  children: [
                    Text('$_goal',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.ink,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    Text(
                      _kind == IntentionKind.tasks
                          ? 'tasks'
                          : 'minutes',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w600,
                          color: SakuraColors.inkFaint),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Increase goal',
                  onPressed: _goal < _max
                      ? () => setState(() => _goal += _step)
                      : null,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: SakuraColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
                _kind == IntentionKind.task
                    ? _summary
                    : '$_summary today',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SakuraColors.primary)),
          ),
          const SizedBox(height: 14),
          if (_kind != IntentionKind.task &&
              widget.game.trackedTaskId == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SakuraColors.primary,
                    side: BorderSide(color: SakuraColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _tracking
                      ? null
                      : () async {
                          setState(() => _tracking = true);
                          try {
                            final t =
                                await widget.game.trackAsTask();
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(t == null
                                    ? 'Already tracked today — tap its row below.'
                                    : 'Planted on the board and pinned for today.'),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            if (e is AuthExpiredException) return;
                            setState(() => _tracking = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Connect to track it as a task.')),
                            );
                          }
                        },
                  icon: _tracking
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Icon(LucideIcons.sprout, size: 16),
                  label: Text(_tracking ? 'Planting…' : 'Track as task',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: SakuraColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            onPressed: !_canSave
                ? null
                : () async {
                    setState(() => _saving = true);
                    await widget.game.setCustomTarget(
                        kind: _kind,
                        // The pinned goal is the pin count itself.
                        goal: _kind == IntentionKind.task
                            ? _picked.length
                            : _goal,
                        taskIds: _kind == IntentionKind.task
                            ? _picked.keys.toList()
                            : null,
                        taskTitles: _kind == IntentionKind.task
                            ? _picked.values.toList()
                            : null);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
            child: Text(_saving ? 'Setting…' : 'Set my target',
                style:
                    const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (widget.game.isCustom) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () async {
                await widget.game.clearCustomTarget();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: Text('Back to suggested',
                  style: TextStyle(
                      fontSize: 12,
                      color: SakuraColors.inkSoft)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kindChip(IntentionKind kind) {
    final selected = _kind == kind;
    return GestureDetector(
      onTap: () => _pickKind(kind),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? SakuraColors.primary
              : SakuraColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected
                  ? SakuraColors.primary
                  : SakuraColors.cardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              switch (kind) {
                IntentionKind.tasks => Icons.checklist_rounded,
                IntentionKind.focus => Icons.timer_outlined,
                IntentionKind.task => Icons.flag_rounded,
              },
              size: 15,
              color: selected ? Colors.white : SakuraColors.inkSoft,
            ),
            const SizedBox(width: 7),
            Text(
                switch (kind) {
                  IntentionKind.tasks => 'Tasks',
                  IntentionKind.focus => 'Focus',
                  IntentionKind.task => 'Pick tasks',
                },
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : SakuraColors.ink)),
          ],
        ),
      ),
    );
  }

  /// Open-task list for the pinned kind: tap rows to pick them (the tap
  /// order is the order they're counted in). Rows carry the subtask count
  /// so the user can see what "done" means.
  Widget _taskPicker() {
    if (_loadingTasks) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_tasksError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(_tasksError!,
                  style: TextStyle(
                      fontSize: 12, color: SakuraColors.inkSoft)),
            ),
            TextButton(
              onPressed: _loadOpenTasks,
              child: Text('Retry',
                  style: TextStyle(color: SakuraColors.primary)),
            ),
          ],
        ),
      );
    }
    if (_openTasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          'No open tasks — add one on the board first.',
          style: TextStyle(fontSize: 12, color: SakuraColors.inkSoft),
        ),
      );
    }
    final full = _picked.length >= DailyIntentionNotifier.maxPins;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 232),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: SakuraColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SakuraColors.cardBorder),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(4),
            itemCount: _openTasks.length,
            itemBuilder: (context, i) => _taskRow(_openTasks[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            _picked.isEmpty
                ? 'Tap to pick up to ${DailyIntentionNotifier.maxPins} '
                    'tasks — the order is yours'
                : full
                    ? '${_picked.length} of '
                        '${DailyIntentionNotifier.maxPins} picked — '
                        'that’s a full day'
                    : '${_picked.length} of '
                        '${DailyIntentionNotifier.maxPins} picked · '
                        'tap again to unpick',
            style: TextStyle(
                fontSize: 11, color: SakuraColors.inkFaint),
          ),
        ),
      ],
    );
  }

  Widget _taskRow(Task t) {
    // Position in the pick order: what the summary will count towards.
    final order = _picked.keys.toList().indexOf(t.id);
    final selected = order >= 0;
    final full = _picked.length >= DailyIntentionNotifier.maxPins;
    final subs = t.subtasks ?? const <Subtask>[];
    final openSubs = subs.where((s) => !s.done).length;
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _picked.remove(t.id);
          return;
        }
        if (full) return; // the hint under the list says why
        _picked[t.id] = t.title;
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? SakuraColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            // The checkbox doubles as the pick-order badge once it is on.
            if (selected)
              Container(
                width: 17,
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SakuraColors.primary,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${order + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              )
            else
              Icon(
                Icons.check_box_outline_blank_rounded,
                size: 17,
                color: full
                    ? SakuraColors.inkFaint.withValues(alpha: 0.4)
                    : SakuraColors.inkFaint,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? SakuraColors.primary
                          : SakuraColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subs.isEmpty
                        ? (taskElapsed(t) == null
                            ? t.tag
                            : 'open ${fmtElapsed(taskElapsed(t)!)}')
                        : '$openSubs of ${subs.length} subtasks left',
                    style: TextStyle(
                        fontSize: 11, color: SakuraColors.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
