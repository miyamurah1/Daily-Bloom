import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ai_client.dart';
import '../data/analytics.dart';
import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/calendar_export.dart';
import '../data/guest_store.dart';
import '../data/energy_store.dart';
import '../data/habit_store.dart';
import '../data/plan_widget.dart';
import '../data/profile_name.dart';
import '../data/reminders.dart';
import '../data/haptics.dart';
import '../data/share_inbox.dart';
import '../data/simple_mode.dart';
import '../data/tap_sound.dart';
import '../data/mock_data.dart';
import '../data/task_repository.dart';
import '../game/first_week_arc.dart';
import '../game/game.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_snackbar.dart';
import '../widgets/concept_map_card.dart';
import '../widgets/contribution_heatmap.dart';
import '../widgets/home_sections.dart';
import '../widgets/daily_bloom_app_bar.dart';
import '../widgets/daily_intention_card.dart';
import '../widgets/first_task_guide.dart';
import '../widgets/level_up_burst.dart';
import '../widgets/motion.dart';
import '../widgets/quick_add_task_sheet.dart';
import '../widgets/task_flow_list.dart';
import 'daily_shutdown_screen.dart';
import 'focus_timer_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'store_screen.dart';
import 'task_detail_screen.dart';

/// Home tab â€” clean, performant routing hub.
///
/// Data layer (Postgres via [BloomApi] with mock fallback) lives here;
/// all section UI is delegated to modular widgets. Top-to-bottom order:
///
/// - Bento header â€” [DailyIntentionCard] (compact) + [GameHud]
///   (seedling rank / XP / streak) in one band.
/// - Planner card, then the 12-week [ContributionHeatmap] (visible,
///   collapsible), then [QuickLinks] doors.
/// - [TaskFlowList] â€” Today's tasks FINAL, at the bottom: the work
///   closes the page after the proof and the doors.
///
/// Habit tracking lives only in the dedicated Habits tab
/// (`HabitsScreen`) â€” Home intentionally shows no habit UI.
///
/// Responsive contract (breakpoint 600):
/// - Mobile (< 600): one unified [CustomScrollView] ([SliverList] +
///   [SliverToBoxAdapter]) + [BottomNavigationBar] section nav.
/// - Desktop (>= 600): same stacked flow, full viewport width.
///   One column everywhere means no side column can ever sit empty
///   beside a longer one â€” the page simply ends after the last card.
/// App-level tab routing stays in AppShell and is the app's ONLY nav
/// system (the old desktop rail was removed). The inner section bar here
/// exists solely for the standalone/test configuration; pass [embedded]
/// when hosted inside AppShell so it hides and never doubles the outer
/// bottom nav.
class HomeScreen extends StatefulWidget {
  /// True when hosted inside AppShell's tab stack.
  final bool embedded;

  /// True when the user is a guest (no Firebase account). Limits tasks to 3
  /// and hides sync-dependent features.
  final bool guest;

  const HomeScreen({super.key, this.embedded = false, this.guest = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _breakpoint = 600;

  final _api = BloomApi();

  List<Task> _todo = const [];
  List<Task> _prog = const [];
  List<Task> _done = const [];
  List<HeatDay> _heat = [];
  bool _live = false;
  String? _note;
  int _bestStreak = 0;

  /// Personalized greeting name (onboarding / account), empty = brand.
  String _userName = '';

  /// Guest mode: caps tasks at 3 and hides sync-dependent features.
  bool get _isGuest => widget.guest;

  /// First-run helpers: the dismissible concept map (persisted) and the
  /// guided sample-task button (live + empty account only).
  static const _kConceptSeen = 'bloom_concept_seen_v1';
  static const _kArcSeen = 'bloom_arc_seen_v1';
  bool _conceptVisible = true;
  bool _creatingSample = false;

  /// True once the user has opened the arc â€” the taller intro card collapses
  /// to the thin row afterwards (one-time, persisted).
  bool _arcSeen = false;

  /// AI day planner: top-3 picks with reasons. Server upgrades quality
  /// (Flash-Lite); offline falls back to local scoring so it always works.
  bool _planning = false;
  bool _plannedOnce = false;
  List<AiPick> _picks = const [];

  /// One "Clean sweep" share nudge per plan: fires once when every pick
  /// of the current plan is finished. A celebration, never a nag.
  bool _planCelebrated = false;

  /// 12-week evidence grid. Expanded by default so the proof is
  /// visible; collapsible for a shorter scroll. State survives
  /// rebuilds (not route pops â€” visible is the product decision).
  bool _heatExpanded = true;

  /// Peak finishing hour from Insights (best hour to tackle #1).
  /// Fetched on plan only â€” never blocks the plan itself.
  int? _peakHour;

  /// In-home section nav (Intention / Flow).
  int _sectionIndex = 0;
  final ScrollController _mobileScroll = ScrollController();
  final _intentionKey = GlobalKey();
  final _flowKey = GlobalKey();

  /// Honest offline grid: 12 weeks of quiet days. Never anyone else's
  /// activity â€” the live heatmap replaces this on a successful sync.
  List<HeatDay> _zeroHeat({int weeks = 12}) {
    final today = DateTime.now();
    final total = weeks * 7;
    return List<HeatDay>.generate(
      total,
      (i) => HeatDay(
        date: today.subtract(Duration(days: total - 1 - i)),
        count: 0,
        level: 0,
      ),
    );
  }

  String get _streakLabel =>
      _live && _bestStreak > 0 ? 'Best streak: $_bestStreak days' : 'Best streak: â€”';

  @override
  void initState() {
    super.initState();
    _heat = _zeroHeat(weeks: 1);
    _loadConcept();
    _loadArcSeen();
    _loadLastPlan();
    FirstWeekArc.instance.load();
    GuestStore.instance.load();
    // Greeting: onboarding name, else the account's display name.
    ProfileName.read().then((v) {
      if (!mounted) return;
      final display =
          v.isNotEmpty ? v : (AuthStore.instance.user?.displayName ?? '');
      setState(() => _userName = display);
    });
    // Simple mode hides/shows the Board door â€” repaint on the flip.
    SimpleMode.instance.addListener(_onSimpleModeChanged);
    // Share-to-app: text shared from other apps opens a prefilled
    // quick-add (cold start and warm, exactly once each).
    ShareInbox.instance.init();
    ShareInbox.instance.addListener(_onSharedText);
    // Offline-first: Home renders the repository's cached tasks and
    // repaints whenever it changes, so a failed sync never blanks the
    // screen. The repo owns optimistic edits + local persistence.
    TaskRepository.instance.addListener(_onRepoChanged);
    TaskRepository.instance.init();
    _refresh();
    // Evening review invite on first open past 8pm (behavior, not alarm).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || DateTime.now().hour < 20) return;
      _maybeReviewNudge(evening: true);
    });
  }

  /// Repository -> local lists. Fires on cache load, remote sync and
  /// every optimistic create/move/delete, keeping the board live even
  /// while offline.
  void _onRepoChanged() {
    if (!mounted) return;
    setState(() {
      _todo = TaskRepository.instance.todayTasks;
      _prog = TaskRepository.instance.inProgressTasks;
      _done = TaskRepository.instance.doneTasks;
      _updateCarry();
    });
    _maybeCelebratePlan();
    // Keep due-date alarms truthful: diff-only, so steady state costs
    // zero platform calls. Retimed/completed/deleted tasks re-arm here.
    unawaited(
        ReminderService.instance.syncTaskReminders(TaskRepository.instance.tasks));
    _pushWidgetStats();
  }

  /// Yesterday's unfinished plan, carried as tomorrow's draft: the user
  /// confirms instead of authoring from blank. Persisted as ids + day.
  static const _kLastPlanDay = 'ai_last_plan_day';
  static const _kLastPlanIds = 'bloom_last_plan_ids';
  String? _lastPlanDay;
  List<String> _lastPlanIds = const [];
  List<Task> _carry = const [];

  Future<void> _loadLastPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _lastPlanDay = prefs.getString(_kLastPlanDay);
        _lastPlanIds = prefs.getStringList(_kLastPlanIds) ?? const [];
        _updateCarry();
      });
    } catch (_) {}
  }

  /// Recompute the carry draft from the live lists: last plan was
  /// yesterday and those ids are still open.
  void _updateCarry() {
    final day = _lastPlanDay;
    if (day == null || _lastPlanIds.isEmpty) {
      if (_carry.isNotEmpty) _carry = const [];
      return;
    }
    // Day-boundary safe: parse + compare dates, never day-1 arithmetic.
    DateTime? planDay;
    try {
      planDay = DateTime.parse(day);
    } catch (_) {
      planDay = null;
    }
    final now = DateTime.now();
    final isYesterday = planDay != null &&
        _dayOnly(now).difference(_dayOnly(planDay)).inDays == 1;
    if (!isYesterday) {
      if (_carry.isNotEmpty) _carry = const [];
      return;
    }
    final open = {for (final t in [..._todo, ..._prog]) t.id: t};
    _carry = [
      for (final id in _lastPlanIds)
        if (open.containsKey(id)) open[id]!,
    ];
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _saveLastPlan(List<String> ids) async {
    final now = DateTime.now();
    final day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _lastPlanDay = day;
    _lastPlanIds = ids;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastPlanDay, day);
      await prefs.setStringList(_kLastPlanIds, ids);
    } catch (_) {}
  }

  /// Push the current plan to the home-screen widget (top-3 + done
  /// flags). Best-effort: no-ops off Android/iOS, never throws.
  Future<void> _syncPlanWidget() async {
    if (!_plannedOnce || _picks.isEmpty) return;
    final done = TaskRepository.instance.doneTasks.map((t) => t.id).toSet();
    final rows = [
      for (final p in _picks)
        (
          id: p.id,
          title: p.title,
          reason: p.reason,
          done: done.contains(p.id),
        ),
    ];
    await PlanWidgetBridge.pushPlan(rows);
    // Remember the plan so any screen's completion can refresh âœ“ flags
    // â€” completing from the detail screen, board, folders, or search.
    PlanWidgetBridge.rememberPlan(
        rows.map((r) => (id: r.id, title: r.title, reason: r.reason)).toList());
  }

  /// Plan the carried draft first: yesterday's unfinished, picked again.
  void _planCarry() {
    if (_carry.isEmpty || _planning) return;
    final picks = _carry
        .take(3)
        .map((t) => AiPick(id: t.id, title: t.title, reason: 'carried over'))
        .toList();
    setState(() {
      _picks = picks;
      _plannedOnce = true;
      _carry = const [];
      _planCelebrated = false;
    });
    AppHaptics.tap();
    _saveLastPlan(picks.map((p) => p.id).toList());
    _syncPlanWidget();
  }

  /// The concept map shows until dismissed once (persisted). Offline test
  /// pumps with empty prefs, so it is visible there too â€” by design.
  Future<void> _loadArcSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _arcSeen = prefs.getBool(_kArcSeen) ?? false);
    } catch (_) {}
  }

  /// True once the user has opened the arc â€” the taller intro card collapses
  /// to the thin row afterwards (one-time, persisted).
  bool get _arcIntro => !_arcSeen;

  Future<void> _loadConcept() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _conceptVisible = !(prefs.getBool(_kConceptSeen) ?? false);
      });
    } catch (_) {}
  }

  Future<void> _dismissConcept() async {
    setState(() => _conceptVisible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kConceptSeen, true);
    } catch (_) {}
  }

  /// True for a live-but-empty account: the guided sample's moment.
  /// Offline stays honestly empty (Phase 1 trust rule).
  bool get _showGuide =>
      _live &&
      _todo.isEmpty &&
      _prog.isEmpty &&
      _done.isEmpty;

  /// Plants three REAL starter tasks â€” a warm welcome, not a "sample".
  /// Toggling any of them done runs the genuine loop (heatmap +1, XP +
  /// combo); the user renames or deletes them afterwards â€” they convert
  /// into their own data.
  Future<void> _createSample() async {
    if (_creatingSample || !_live) return;
    setState(() => _creatingSample = true);
    try {
      for (final s in starterTasks) {
        await _api.createTask(
          s.title,
          tag: s.tag,
          description: s.description,
        );
      }
      await _refresh();
      if (mounted) {
        showBloomSnackBar(context,
            'Welcome blooms planted â€” tap the first one done. ðŸŒ¸');
      }
    } catch (e) {
      if (mounted) {
        if (e is AuthExpiredException) return;
        showBloomSnackBar(context, 'Could not plant â€” try again.');
      }
    } finally {
      if (mounted) setState(() => _creatingSample = false);
    }
  }

  @override
  void dispose() {
    TaskRepository.instance.removeListener(_onRepoChanged);
    SimpleMode.instance.removeListener(_onSimpleModeChanged);
    ShareInbox.instance.removeListener(_onSharedText);
    _mobileScroll.dispose();
    super.dispose();
  }

  void _onSimpleModeChanged() {
    if (mounted) setState(() {});
  }

  /// A share landed â†’ open quick-add with the text already in place.
  void _onSharedText() {
    final text = ShareInbox.instance.pending;
    if (text == null || !mounted) return;
    ShareInbox.instance.take();
    _openQuickAdd(initialText: text);
  }

  /// Opens quick-add, enforcing the 3-task guest cap.
  Future<void> _openQuickAdd({String? initialText}) async {
    if (_isGuest && GuestStore.instance.atLimit) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Keep your blooms'),
          content: const Text(
            'Guests can add up to 3 tasks. Create a free account to keep '
            'adding tasks and sync them across devices.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Maybe later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_leaveGuestAndSignIn());
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
      return;
    }
    showQuickAddTask(context, initialText: initialText);
  }

  /// Leave guest mode and route to sign-in. Guest tasks are intentionally
  /// kept (not cleared): after a successful sign-in, [migrateGuestTasks]
  /// carries them into the synced repository. Clearing happens only after
  /// migration succeeds, or on explicit logout.
  Future<void> _leaveGuestAndSignIn() async {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Widget stats line: streak + today's progress on the launcher.
  /// Pushed only when the string changes (each push = a broadcast).
  String _lastWidgetStats = '';

  Future<void> _pushWidgetStats() async {
    final now = DateTime.now();
    final doneToday = _done.where((t) {
      final c = t.completedAt;
      return c != null &&
          c.year == now.year &&
          c.month == now.month &&
          c.day == now.day;
    }).length;
    final stats = PlanWidgetBridge.formatStats(
      streak: GamificationStateNotifier.instance.streak,
      done: doneToday,
      open: _todo.length + _prog.length,
    );
    if (stats == _lastWidgetStats) return;
    _lastWidgetStats = stats;
    await PlanWidgetBridge.pushStats(stats);
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        _api.fetchHeatmapFull(weeks: 12),
        _api.fetchProgress(),
        _api.fetchWallet(),
      ]);
      if (!mounted) return;
      final progress = results[1] as Map<String, int>;
      setState(() {
        _heat = (results[0] as List<HeatDay>);
        _bestStreak = progress['bestStreak'] ?? 0;
        _live = true;
        _note = null;
      });
      // Pull the authoritative list; the repository notifies and the
      // board repaints from cache + remote through one path.
      await TaskRepository.instance.loadRemote(withDetails: true);
      await EnergyStore.instance
          .prune(TaskRepository.instance.tasks.map((t) => t.id));
      await _syncIntention();
      _maybeHabitNudge(); // one quiet line when a streak ends tonight
      _pushWidgetStats(); // launcher widget: streak + today's progress
    } catch (e) {
      if (!mounted) return;
      // Expired session: AuthStore already bounced to login via AuthGate.
      if (e is AuthExpiredException) return;
      // Offline: never wipe. The repository keeps whatever it cached so
      // tasks stay visible and editable until the next successful sync.
      setState(() {
        _todo = TaskRepository.instance.todayTasks;
        _prog = TaskRepository.instance.inProgressTasks;
        _done = TaskRepository.instance.doneTasks;
        if (_heat.isEmpty) _heat = _zeroHeat();
        _live = false;
        _note = 'API offline â€” showing your saved tasks.';
      });
      DailyIntentionNotifier.instance.markOffline();
    }
  }

  Future<void> _complete(Task t) async {
    // Local game juice first â€” works offline so combo is always visible.
    // XP moves only with the transition: completing grants, reopening
    // revokes (anti-farm â€” done â†’ undo â†’ done must not mint XP).
    final game = GamificationStateNotifier.instance;
    final levelBefore = game.level;
    final next = nextStatus(t);
    if (next == 'done') {
      game.registerTaskCompletion(taskId: t.id);
      // Done celebration: double-pulse haptic + soft blip.
      AppHaptics.bloom();
      TapSound.tap();
    } else {
      game.revokeTaskCompletion(taskId: t.id);
      AppHaptics.tap();
    }
    // Level crossing â†’ one-shot burst + fanfare (no dialog stacks).
    if (game.level > levelBefore && mounted) {
      LevelUpBurst.celebrate(context, game);
    }
    // Repository move is optimistic + persisted: the board updates at
    // 0ms and survives offline. No "start the backend" dead-end.
    await TaskRepository.instance.moveTask(t.id, next);
    _syncPlanWidget(); // widget âœ“ flags stay truthful
    if (mounted) {
      showBloomSnackBar(
          context,
          next == 'done'
              ? 'Done â€” heatmap +1 (like git commit).'
              : 'Back to to-do â€” start it when ready.');
    }
    // Analytics catch up only when the backend is reachable.
    if (_live) await _refresh();
    // Third bloom of the day: behavior beats the clock â€” suggest the
    // review while the evidence is fresh, exactly once.
    _maybeReviewNudge();
  }

  /// Evening-or-milestone review invite. Fires once a day, either after
  /// the 3rd completion or on first open past 8pm with something done â€”
  /// never a fixed alarm, never a nag.
  void _maybeReviewNudge({bool evening = false}) {
    final game = GamificationStateNotifier.instance;
    if (!mounted || game.reviewNudgedToday) return;
    if (evening) {
      if (game.todayCompletions == 0) return;
    } else {
      if (game.todayCompletions != 3) return;
    }
    game.markReviewNudged();
    showBloomSnackBar(
      context,
      evening
          ? 'Day is done â€” see how the week looks?'
          : '3 blooms today â€” peek at your week?',
      actionLabel: 'Review',
      onAction: () {
        Navigator.of(context).push(
          SakuraPageRoute(builder: (_) => const ReviewScreen()),
        );
      },
    );
  }

  void _openDetail(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(builder: (_) => TaskDetailScreen(task: t)))
        .then((_) => _refresh()); // counts may have changed inside
  }

  void _toggleSub(Subtask s, bool done) async {
    // Routed through the repository: optimistic locally and queued in
    // the offline outbox when the backend is unreachable. TaskCard owns
    // the petal burst + UNDO snackbar.
    await TaskRepository.instance.setSubtaskDone(s.id, done);
  }

  void _openTimer(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(
            builder: (_) =>
                FocusTimerScreen(task: t, heroTag: 'home-focus-${t.id}')))
        .then((_) => _refresh()); // focus time may have grown
  }

  /// Backlog groom: duplicates to clear, stale to defer, vague to sharpen.
  /// Server upgrades grouping (Flash-Lite); offline uses local rules.
  /// Deletes and defers only run on explicit Apply â€” nothing auto-changes.
  Future<void> _groom() async {
    if (_planning) return;
    setState(() => _planning = true);
    try {
      final groups = await AiClient().groom([..._todo, ..._prog]);
      if (!mounted) return;
      if (groups.isEmpty) {
        showBloomSnackBar(context, 'Pile looks tidy â€” nothing to groom.');
        return;
      }
      final byId = {for (final t in [..._todo, ..._prog]) t.id: t};
      final selected = <String, Set<String>>{
        for (final g in groups)
          if (g.action != 'review') g.title: g.ids.toSet(),
      };
      final apply = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => AlertDialog(
            backgroundColor: SakuraColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text('Tidy the pile',
                style: TextStyle(color: SakuraColors.ink)),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in groups) ...[
                      Text(
                        g.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: SakuraColors.ink,
                        ),
                      ),
                      Text(
                        g.note,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: SakuraColors.inkSoft),
                      ),
                      const SizedBox(height: 4),
                      if (g.action == 'review')
                        for (final id in g.ids)
                          GestureDetector(
                            onTap: () {
                              Navigator.of(ctx).pop(false);
                              final t = byId[id];
                              if (t != null) _openDetail(t);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Text(
                                'â€¢ ${byId[id]?.title ?? id}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: SakuraColors.primary,
                                ),
                              ),
                            ),
                          )
                      else
                        for (final id in g.ids)
                          CheckboxListTile(
                            value: selected[g.title]?.contains(id) ?? false,
                            onChanged: (v) => setSheet(() {
                              if (v == true) {
                                selected[g.title]?.add(id);
                              } else {
                                selected[g.title]?.remove(id);
                              }
                            }),
                            title: Text(
                              byId[id]?.title ?? id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: SakuraColors.ink),
                            ),
                            subtitle: Text(
                              g.action == 'delete-others'
                                  ? 'clear copy'
                                  : 'defer a week',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: SakuraColors.inkSoft),
                            ),
                            activeColor: SakuraColors.primary,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel',
                    style: TextStyle(color: SakuraColors.inkSoft)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: SakuraColors.primary),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );
      if (apply != true) return;
      var cleared = 0;
      var deferred = 0;
      final nextWeek = DateTime.now().add(const Duration(days: 7));
      for (final g in groups) {
        final ids = selected[g.title] ?? const <String>{};
        if (ids.isEmpty) continue;
        if (g.action == 'delete-others') {
          for (final id in ids) {
            await TaskRepository.instance.deleteTask(id);
            cleared++;
          }
        } else if (g.action == 'defer-week') {
          for (final id in ids) {
            await TaskRepository.instance
                .updateTask(id, dueAt: nextWeek);
            deferred++;
          }
        }
      }
      await _refresh();
      if (mounted && (cleared > 0 || deferred > 0)) {
        showBloomSnackBar(context,
            'Tidied: $cleared cleared Â· $deferred deferred a week.');
      }
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Task? _findTask(String id) {
    for (final t in [..._todo, ..._prog, ..._done]) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// AI day plan: top-3 open tasks with reasons. Tap a pick to open it.
  Future<void> _planDay() async {
    if (_planning) return;
    setState(() => _planning = true);
    try {
      final picks = await AiClient().plan([..._todo, ..._prog]);
      if (!mounted) return;
      setState(() {
        _picks = picks;
        _plannedOnce = true;
        _planCelebrated = false;
      });
      AppHaptics.tap();
      _saveLastPlan(picks.map((p) => p.id).toList());
      _syncPlanWidget();
      FirstWeekArc.instance.report(FirstWeekStep.planned);
      BloomAnalytics.planMyDay();
      _syncBannerHint();
      // Peak hour annotates the plan; failure keeps the plan as-is.
      try {
        final ins = await _api.fetchInsights();
        if (!mounted || ins.hours.isEmpty) return;
        final peak =
            ins.hours.reduce((a, b) => a['n']! >= b['n']! ? a : b);
        if (mounted) setState(() => _peakHour = peak['h']);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  /// Time-block export: today's picks as back-to-back calendar events
  /// starting at the peak hour. Same no-SDK .ics file as Settings.
  Future<void> _exportPlan() async {
    if (_picks.isEmpty) return;
    if (kIsWeb) {
      showBloomSnackBar(
          context, 'Calendar files need the mobile or desktop app.');
      return;
    }
    final all = {for (final t in [..._todo, ..._prog, ..._done]) t.id: t};
    final blocks = [
      for (final p in _picks)
        if (all.containsKey(p.id))
          PlanBlock(
              id: p.id,
              title: all[p.id]!.title,
              minutes: estimatedMinutes(all[p.id]!)),
    ];
    if (blocks.isEmpty || !mounted) return;
    try {
      final file =
          await File('${Directory.systemTemp.path}/bloom-today.ics')
              .writeAsString(
                  buildPlanBlocks(blocks, startHour: _peakHour ?? 9));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/calendar')],
          text: "Today's plan",
        ),
      );
    } catch (_) {
      if (mounted) showBloomSnackBar(context, 'Calendar export failed.');
    }
  }

  static const _kHabitNudgeDay = 'bloom_habit_nudge_day';

  static String _dayString([DateTime? d]) {
    final n = d ?? DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// At-risk habit nudge: longest living streak ending tonight gets one
  /// quiet line with a one-tap save. Once a day, never a list, never a nag.
  Future<void> _maybeHabitNudge() async {
    try {
      await HabitStore.instance.load();
      final atRisk = HabitStore.atRisk(HabitStore.instance.habits);
      if (atRisk.isEmpty || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final today = _dayString();
      if (prefs.getString(_kHabitNudgeDay) == today) return;
      await prefs.setString(_kHabitNudgeDay, today);
      if (!mounted) return;
      final h = atRisk.first;
      showBloomSnackBar(
        context,
        'â€œ${h.name}â€ streak (${h.streak}d) ends tonight â€” 5 min keeps it.',
        actionLabel: 'Keep it',
        onAction: () async {
          await HabitStore.instance.toggleToday(h.id);
        },
      );
    } catch (_) {}
  }

  /// Evening streak guard: after 6pm with a live streak and zero
  /// completions today, offer one-tap rescue. Data-driven â€” completing
  /// anything hides it; offline hides it too (no heatmap truth).
  bool get _streakAtRisk {
    if (!_live || DateTime.now().hour < 18) return false;
    final today = DateTime.now();
    final doneToday = _heat.any((d) =>
        d.date.year == today.year &&
        d.date.month == today.month &&
        d.date.day == today.day &&
        d.count > 0);
    return !doneToday && GamificationStateNotifier.instance.streak > 0;
  }

  Widget _streakRiskCard() {
    final streak = GamificationStateNotifier.instance.streak;
    return Container(
      key: const ValueKey('home-streak-risk'),
      padding: const EdgeInsets.all(16),
      decoration: SakuraTheme.cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: SakuraColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.flame,
                size: 15, color: SakuraColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Day $streak is on the line',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  'One small bloom tonight keeps it alive.',
                  style: TextStyle(
                      fontSize: 12, color: SakuraColors.inkSoft),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SakuraColors.primary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              AppHaptics.tap();
              TapSound.tap();
              _openQuickAdd();
            },
            child: const Text('Plant',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// Planner header action: past 8pm with a plan done, the most useful
  /// thing is the review â€” otherwise (re)plan the day.
  void _plannerAction() {
    if (_planning) return;
    if (_plannedOnce && DateTime.now().hour >= 20) {
      Navigator.of(context).push(
        SakuraPageRoute(builder: (_) => const ReviewScreen()),
      );
      return;
    }
    _planDay();
  }

  /// First-week arc: refresh the prompt row (state lives in the store).
  void _syncBannerHint() => setState(() {});

  Widget _arcRow() {
    final step = FirstWeekArc.instance.nextStep;
    if (step == null) return const SizedBox.shrink();
    const tags = ['FIRST GARDEN', 'DAILY PLAN', 'DEEP WORK'];
    const ctas = ['Plant', 'Plan', 'Focus'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The "first week" nameplate shows only until the arc is opened once;
        // afterwards the card collapses to a thin prompt row.
        if (_arcIntro) ...[
          Row(
            children: [
              Icon(LucideIcons.flower, size: 13, color: SakuraColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'YOUR FIRST WEEK',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w700,
                    color: SakuraColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        GestureDetector(
          onTap: _arcAction,
          behavior: HitTestBehavior.opaque,
          child: Container(
            key: const ValueKey('home_arc_card'),
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SakuraColors.primary.withValues(alpha: 0.16),
                  SakuraColors.primarySoft,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: SakuraColors.primary.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: SakuraColors.primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  tags[step],
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                    color: SakuraColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    FirstWeekArc.instance.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.ink),
                  ),
                ),
                const SizedBox(width: 8),
            Text(
              ctas[step],
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
    );
  }

  /// Arc CTA: plant opens the FAB sheet, plan plans, focus opens the
  /// focus timer (finishing a session completes the arc).
  void _arcAction() {
    if (!_arcSeen) {
      setState(() => _arcSeen = true);
      SharedPreferences.getInstance()
          .then((p) => p.setBool(_kArcSeen, true))
          .catchError((_) => false);
    }
    final step = FirstWeekArc.instance.nextStep;
    if (step == null) return;
    if (step == 0) {
      _openQuickAdd();
    } else if (step == 1) {
      _planDay();
    } else {
      Navigator.of(context).push(
        SakuraPageRoute(builder: (_) => const FocusTimerScreen()),
      );
    }
  }

  /// Full-plan celebration: when every pick of the current plan is done,
  /// offer the share card once. Replaces v1's stake settle â€” the same
  /// peak moment, minus the punishment.
  void _maybeCelebratePlan() {
    if (_planCelebrated || !_plannedOnce || _picks.isEmpty) return;
    final done = TaskRepository.instance.doneTasks.map((t) => t.id).toSet();
    final allDone = _picks.every((p) => done.contains(p.id));
    if (!allDone) return;
    _planCelebrated = true;
    if (!mounted) return;
    showBloomSnackBar(
      context,
      'Clean sweep â€” a week worth sharing.',
      actionLabel: 'Share',
      onAction: () {
        Navigator.of(context).push(
          SakuraPageRoute(builder: (_) => const ReviewScreen()),
        );
      },
    );
  }

  Future<void> _syncIntention() async {
    final game = DailyIntentionNotifier.instance;
    if (!_live) {
      game.markOffline();
      return;
    }
    // Tasks signal reuses the heatmap already in hand â€” zero extra IO.
    if (game.target.kind == IntentionKind.tasks) {
      game.update(
        contributionsToday: heatCountFor(_heat, DateTime.now()),
        focusMinutesToday: 0,
      );
      return;
    }
    try {
      final days = await _api.fetchFocusSummary(days: 1);
      if (!mounted) return;
      game.update(
        contributionsToday: 0,
        focusMinutesToday: days.fold<int>(0, (a, d) => a + d.minutes),
      );
    } catch (_) {
      game.markOffline();
    }
  }

  void _claimBloom() {
    // Gather thump: the reward moment gets the heavier buzz.
    AppHaptics.confirm();
    TapSound.tap();
    GamificationStateNotifier.instance.claimDailyRitual();
    // Loot box removed: rewards land directly, no mystery roll.
    showBloomSnackBar(context, 'Bloom claimed ðŸŒ±');
  }

  void _jumpToSection(int index) {
    AppHaptics.select();
    TapSound.tap();
    setState(() => _sectionIndex = index);
    final keys = [_intentionKey, _flowKey];
    final ctx = keys[index.clamp(0, keys.length - 1)].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: AppMotion.scroll,
        curve: AppMotion.scrollCurve,
      );
    }
  }

  /// In-home section [BottomNavigationBar] (standalone only).
  BottomNavigationBar _sectionBar() {
    return BottomNavigationBar(
      currentIndex: _sectionIndex,
      onTap: _jumpToSection,
      type: BottomNavigationBarType.fixed,
      backgroundColor: SakuraColors.surface,
      selectedItemColor: SakuraColors.primary,
      unselectedItemColor: SakuraColors.navInactive,
      selectedFontSize: 10,
      unselectedFontSize: 10,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(LucideIcons.sun), label: 'Intention'),
        BottomNavigationBarItem(
            icon: Icon(LucideIcons.listChecks), label: 'Flow'),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Routing hub: watches game + theme, then branches on width.
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Theme-only listener at the root. Game/XP ticks used to live here
    // too â€” which rebuilt the heatmap, HUD, quick links AND the whole
    // 30-card board on every XP gain. Streak/tokens now read inside
    // GameHud (listens itself) and the app bar's token pill (listens
    // itself), so an XP tick repaints those two small subtrees only.
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isMobile = constraints.maxWidth < _breakpoint;
            // Serene dark baseline (#120D1C) resolves through the active
            // Sakura theme â€” midnight paints near-identical.
            return Scaffold(
              backgroundColor:
                  Theme.of(context).scaffoldBackgroundColor,
              appBar: DailyBloomAppBar(
                greetingName: _userName.isEmpty ? null : _userName,
                onStoreTap: () {
                  Navigator.of(context).push(
                    SakuraPageRoute(
                        builder: (_) => const StoreScreen()),
                  );
                },
                onLogoutTap: () async {
                  ThemeStore.instance.resetToDefault();
                  await AuthStore.instance.logout();
                  // No navigation needed: AuthGate swaps to LoginScreen and
                  // the old AppShell tree is discarded (no back-button leak).
                },
                onSettingsTap: () {
                  Navigator.of(context).push(
                    SakuraPageRoute(
                        builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              body: isMobile ? _mobileBody() : _desktopBody(),
              // One stacked section bar on every width when
              // standalone â€” AppShell already owns the outer app
              // nav and must stay the single bottom bar.
              bottomNavigationBar:
                  !widget.embedded ? _sectionBar() : null,
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Mobile (< 600): one unified CustomScrollView.
  // ------------------------------------------------------------------

  /// Compact Zen Bento header (~130px): today's intention beside the
  /// seedling (rank + XP + streak). Consolidates the three former stacked
  /// cards into one glance, freeing vertical room so "Today's Flow" lands
  /// in the primary viewport on phones.
  Widget _bentoHeader() {
    // Responsive: narrow phones stack focus OVER level (full-width cells
    // so nothing ellipsises); wide screens keep the compact side-by-side
    // ~130px bento band.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        if (narrow) {
          return Column(
            key: const ValueKey('home_hud_card'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DailyIntentionCard(
                compact: true,
                onTargetMet: _claimBloom,
              ),
              const SizedBox(height: 10),
              GameHud(onBloom: _claimBloom),
            ],
          );
        }
        return SizedBox(
          key: const ValueKey('home_hud_card'),
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // 5:4 (was 3:2): the seedling cell needs ~140px on a 360px
                // phone for rank/streak text beside the badge â€” at 3:2 its
                // text column collapsed to ~48px and ellipsised every rank.
                flex: 5,
                child: DailyIntentionCard(
                  compact: true,
                  onTargetMet: _claimBloom,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: GameHud(onBloom: _claimBloom),
              ),
            ],
          ),
        );
      },
    );
  }

  /// AI day planner card: "Plan my day" ranks open tasks (server
  /// Flash-Lite, local fallback offline). Picks open their task on tap.
  Widget _plannerCard() {
    return Container(
      key: const ValueKey('home_plan_card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles,
                  size: 13, color: SakuraColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "TODAY'S PLAN",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w600,
                    color: SakuraColors.inkFaint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _planning ? null : _plannerAction,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  _planning
                      ? 'Thinkingâ€¦'
                      : _plannedOnce && DateTime.now().hour >= 20
                          ? 'Review today'
                          : _plannedOnce
                              ? 'Refresh'
                              : 'Plan my day',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: SakuraColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_plannedOnce && _carry.isNotEmpty)
            GestureDetector(
              onTap: _planning ? null : _planCarry,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.history,
                        size: 12, color: SakuraColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Yesterday left ${_carry.length} unfinished â€” re-plan first?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: SakuraColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_plannedOnce)
            Text(
              'Overdue, due-soon and high-priority first â€” tap Plan my day.',
              style: TextStyle(fontSize: 12.5, color: SakuraColors.inkSoft),
            )
          else if (_picks.isEmpty)
            Text(
              'Nothing open â€” enjoy the quiet.',
              style: TextStyle(fontSize: 12.5, color: SakuraColors.inkSoft),
            )
          else
            for (var i = 0; i < _picks.length; i++)
              GestureDetector(
                onTap: () {
                  final t = _findTask(_picks[i].id);
                  if (t != null) _openDetail(t);
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(
                      top: i == 0 ? 2 : 8, bottom: i == _picks.length - 1 ? 2 : 0),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: SakuraColors.primary
                              .withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _picks[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: SakuraColors.ink,
                              ),
                            ),
                            Text(
                              _picks[i].reason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: SakuraColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ListenableBuilder(
                        listenable: EnergyStore.instance,
                        builder: (context, _) {
                          final level = EnergyStore.instance
                              .levelFor(_picks[i].id);
                          if (level == null) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: SakuraColors.primary
                                    .withValues(alpha: 0.10),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                energyLabel(level),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: SakuraColors.primary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Icon(LucideIcons.chevronRight,
                          size: 15, color: SakuraColors.inkFaint),
                    ],
                  ),
                ),
              ),
          if (_plannedOnce && _picks.isNotEmpty)
            Builder(builder: (context) {
              final total = planDayTotalMinutes(
                  [..._todo, ..._prog, ..._done], _picks);
              final heavy = total > 120;
              final peak = _peakHour;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'â‰ˆ ${fmtLoad(total)} across top ${_picks.length}${peak != null ? ' Â· peak $peak:00 â€” tackle #1 then' : ''}${heavy ? ' Â· heavy day â€” consider deferring one' : ' Â· fits a calm day'}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: heavy
                          ? SakuraColors.primary
                          : SakuraColors.inkSoft),
                ),
              );
            }),
          Builder(builder: (context) {
            final repeats =
                repeatCandidates([..._todo, ..._prog], _done);
            if (repeats.isEmpty) return const SizedBox.shrink();
            final r = repeats.first;
            final name = r.task.title.length > 34
                ? '${r.task.title.substring(0, 34)}â€¦'
                : r.task.title;
            return GestureDetector(
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await TaskRepository.instance
                    .updateTask(r.task.id, recurring: 'weekly');
                await _refresh();
                if (!mounted) return;
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(content: Text('â€œ$nameâ€ repeats weekly now.')),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.repeat,
                        size: 12, color: SakuraColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'â€œ$nameâ€ done ${r.times}x â€” repeat weekly?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: SakuraColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (_plannedOnce && _picks.isNotEmpty)
            GestureDetector(
              onTap: _exportPlan,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.calendarPlus,
                      size: 12,
                      color: SakuraColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Add to calendar (.ics)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: SakuraColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if ((_todo.length + _prog.length) >= 15)
            GestureDetector(
              onTap: _planning ? null : _groom,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.broom,
                      size: 12,
                      color: SakuraColors.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Pile growing? Tidy itâ€¦',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: SakuraColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 12-week evidence grid behind a disclosure: visible by default so
  /// the proof reads on the page; collapsible for a shorter scroll.
  /// The grid keeps its state while hidden (maintainState) so
  /// collapsing never refetches.
  Future<void> _shareGarden() async {
    final streak = GamificationStateNotifier.instance.streak;
    final done = _done.length;
    final text = 'My Daily Bloom garden: $streak-day streak, $done blooms completed. '
        'Growing one meaningful thing at a time. \u{1F338}';
    await SharePlus.instance.share(ShareParams(text: text, subject: 'My Daily Bloom garden'));
  }

  Widget _shutdownButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DailyShutdownScreen()),
        ),
        icon: const Icon(Icons.nightlight_round, size: 18),
        label: const Text('Close the garden for today'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _miniHud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SakuraColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SakuraColors.cardBorder),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.flame, size: 16, color: SakuraColors.primary),
              const SizedBox(width: 6),
              Text(
                'Streak: ${GamificationStateNotifier.instance.streak}d',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SakuraColors.ink,
                ),
              ),
            ],
          ),
          Text(
            GamificationStateNotifier.instance.graceDayAvailable
                ? '1 grace day'
                : 'Grace used',
            style: TextStyle(
              fontSize: 12,
              color: SakuraColors.inkSoft,
            ),
          ),
          Text(
            '${_todo.length + _prog.length} seeds',
            style: TextStyle(
              fontSize: 12,
              color: SakuraColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
  Widget _collapsibleHeat() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _heatExpanded = !_heatExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'YOUR PROOF',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _heatExpanded ? 'Hide' : 'Show',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SakuraColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _heatExpanded
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 15,
                  color: SakuraColors.primary,
                ),
              ],
            ),
          ),
        ),
        Visibility(
          visible: _heatExpanded,
          maintainState: true,
          maintainAnimation: false,
          maintainSize: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ContributionHeatmap(
              days: _heat,
              bestStreakLabel: _streakLabel,
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileBody() {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: SakuraColors.primary,
      backgroundColor: SakuraColors.surface,
      strokeWidth: 2.5,
      child: CustomScrollView(
        controller: _mobileScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SyncBanner(live: _live, note: _note)),
          if (_conceptVisible)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: ConceptMapCard(onDismiss: _dismissConcept),
              ),
            ),
          // Zen Bento header: greeting + seedling.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Container(key: _intentionKey, child: _bentoHeader()),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          // Today's Flow: the work, right under the header.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                key: _flowKey,
                child: TaskFlowList(
                  todo: _todo,
                  progress: _prog,
                  done: _done,
                  onTap: _complete,
                  onOpen: _openDetail,
                  onToggleSub: _toggleSub,
                  onTimer: _openTimer,
                  heroPrefix: 'home-focus-',
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          // First-week arc: shows in both modes (first-week guide, not power tool).
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _arcRow(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          // Shutdown + Share: the two closing actions.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: _shutdownButton()),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _shareGarden,
                    icon: const Icon(LucideIcons.share2, size: 20),
                    tooltip: 'Share your garden',
                    style: IconButton.styleFrom(
                      backgroundColor: SakuraColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: SakuraColors.cardBorder),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          // Mini garden HUD: streak + grace day.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _miniHud(),
            ),
          ),
          // Advanced-only surfaces (Simple Mode hides these).
          if (!SimpleMode.instance.enabled) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // First-week arc: one quiet prompt until the loop is learned.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _arcRow(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // Plan: the day's planner.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _plannerCard(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // Evidence: collapsed until asked for.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _collapsibleHeat(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (_streakAtRisk)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _streakRiskCard(),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  key: ValueKey('home_quick_link_$i'),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: QuickLinks.rowItem(i, context),
                ),
                childCount: QuickLinks.rowCount,
              ),
            ),
          ],
          if (_showGuide)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: FirstTaskGuide(
                  onCreate: _createSample,
                  creating: _creatingSample,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
  Widget _desktopBody() {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: SakuraColors.primary,
      backgroundColor: SakuraColors.surface,
      strokeWidth: 2.5,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SyncBanner(live: _live, note: _note),
            if (_conceptVisible)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: ConceptMapCard(onDismiss: _dismissConcept),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Container(key: _intentionKey, child: _bentoHeader()),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                key: _flowKey,
                child: TaskFlowList(
                  todo: _todo,
                  progress: _prog,
                  done: _done,
                  onTap: _complete,
                  onOpen: _openDetail,
                  onToggleSub: _toggleSub,
                  onTimer: _openTimer,
                  heroPrefix: 'home-focus-',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _arcRow(),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: _shutdownButton()),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _shareGarden,
                    icon: const Icon(LucideIcons.share2, size: 20),
                    tooltip: 'Share your garden',
                    style: IconButton.styleFrom(
                      backgroundColor: SakuraColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: SakuraColors.cardBorder),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _miniHud(),
            ),
            if (!SimpleMode.instance.enabled) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _plannerCard(),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _collapsibleHeat(),
              ),
              const SizedBox(height: 8),
              if (_streakAtRisk)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _streakRiskCard(),
                ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: QuickLinks(key: ValueKey('home_quick_links')),
              ),
            ],
            if (_showGuide)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: FirstTaskGuide(
                  onCreate: _createSample,
                  creating: _creatingSample,
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
