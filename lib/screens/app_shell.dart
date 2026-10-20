import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/focus_controller.dart';
import '../data/haptics.dart';
import '../data/mock_data.dart';
import '../data/plan_widget.dart';
import '../data/reminders.dart';
import '../data/task_repository.dart';
import '../data/tap_sound.dart';
import '../game/game.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/focus_mini_player.dart';
import '../widgets/bloom_snackbar.dart';
import '../widgets/motion.dart';
import '../widgets/quick_add_ritual_sheet.dart';
import '../widgets/quick_add_task_sheet.dart';
import '../widgets/sakura_bottom_nav.dart';
import '../widgets/tab_skeleton.dart';
import 'folders_screen.dart';
import 'home_screen.dart';
import 'insights_hub_screen.dart';
import 'review_screen.dart';
import 'rituals_hub_screen.dart';
import 'task_detail_screen.dart';

/// Root shell — owns the 4-tab BottomNav, the contextual "plant" FAB and
/// the page stack.
///
/// Perf contract (mobile 60fps):
/// - Pages are created ONCE in [initState] and cached — a theme or XP
///   tick must never rebuild 4 tab states.
/// - Only the *visible* tab ticks: offscreen pages sit under
///   `TickerMode(enabled: false)` so petal loops, badge spins and glow
///   controllers pause instead of burning GPU in the background.
/// - [DynamicBloomBackground] listens to the game singleton alone; the
///   Scaffold/body does NOT rebuild on every XP tick.
/// - Tab switch is instant ([IndexedStack]) — per-page [Entrance]
///   animations carry the delight, not a full-page AnimatedSwitcher fade.
class AppShell extends StatefulWidget {
  final bool guest;

  const AppShell({super.key, this.guest = false});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool get _isGuest => widget.guest;

  /// Tabs the user has actually visited. Unvisited tabs render a
  /// lightweight placeholder so cold start only pays for Today (1 API
  /// burst instead of 4 parallel bursts on login).
  final Set<int> _visited = {0};

  /// Home-screen widget taps (`dailybloom://` URIs, cold + warm).
  StreamSubscription<Uri?>? _widgetClicks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cold start via widget tap: route once the first frame lands.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uri = await PlanWidgetBridge.initialLaunchUri();
      _openWidgetUri(PlanWidgetBridge.parsePlanWidgetUri(uri));
      _drainNotifTask();
    });
    // Warm taps while the shell is alive. Guarded: the updates
    // channel does not exist on web/desktop, where subscribing throws
    // during stream activation (uncatchable via onError).
    _widgetClicks = PlanWidgetBridge.listenWidgetClicks(
      (uri) => _openWidgetUri(PlanWidgetBridge.parsePlanWidgetUri(uri)),
    );
    // Every task mutation anywhere in the app must refresh the widget's
    // ✓ flags — hence the repo listener at the shell, not per-screen.
    TaskRepository.instance.addListener(_syncWidgetDoneFlags);

    // Guest mode: work entirely from local cache, never sync. Explicit on
    // BOTH branches so the guest→sign-in shell swap can't leave the
    // repository pinned in guest-only mode (silently never syncing).
    TaskRepository.instance.setGuestMode(_isGuest);
  }

  /// Route a widget tap: the ✓ button completes its task, a task row
  /// deep-links into its detail, plan jumps to Today. Unknown ids land
  /// on Today — never a dead tap.
  void _openWidgetUri(({String type, String? id})? target) {
    if (target == null || !mounted) return;
    // Launcher ✓ — goes through the repository, so it's optimistic,
    // offline-queued, XP-awarded and widget-flag-refreshing exactly like
    // an in-app completion.
    if (target.type == 'complete' && target.id != null) {
      AppHaptics.bloom();
      unawaited(TaskRepository.instance.moveTask(target.id!, 'done'));
      showBloomSnackBar(context, 'Planted from the widget ✓');
      _go(0);
      return;
    }
    if (target.type == 'plan' || target.id == null) {
      _go(0);
      return;
    }
    Task? found;
    try {
      found = TaskRepository.instance.tasks
          .firstWhere((t) => t.id == target.id);
    } catch (_) {
      found = null;
    }
    if (!mounted) return;
    if (found == null) {
      _go(0);
      return;
    }
    Navigator.of(context).push(
      SakuraPageRoute(builder: (_) => TaskDetailScreen(task: found!)),
    );
  }

  @override
  void dispose() {
    TaskRepository.instance.removeListener(_syncWidgetDoneFlags);
    _widgetClicks?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// TaskRepository -> widget done flags. The bridge diffs internally,
  /// so only real changes cost a platform call.
  void _syncWidgetDoneFlags() {
    PlanWidgetBridge.noteDoneIds(
        TaskRepository.instance.doneTasks.map((t) => t.id).toSet());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume is our "likely back online" signal: drain any mutations
    // queued while the app was backgrounded/offline.
    if (state == AppLifecycleState.resumed) {
      TaskRepository.instance.syncNow();
      // A due-date tap may have launched us: deep-link its task.
      _drainNotifTask();
    }
  }

  /// Open the task behind a due-date notification tap (or the weekly
  /// review behind its own), if any is stashed. A "Done ✓" action press
  /// completes behind the scenes instead — confirmed with a snackbar,
  /// no screen to open because the work is already finished.
  Future<void> _drainNotifTask() async {
    final doneId = await ReminderService.drainNotifDone();
    if (doneId != null && mounted) {
      final known =
          TaskRepository.instance.tasks.any((t) => t.id == doneId);
      if (known) {
        await TaskRepository.instance.moveTask(doneId, 'done');
        if (!mounted) return;
        showBloomSnackBar(context, 'Done — nice tending. 🌸');
      }
      // Unknown id (deleted since the alarm was armed): silently ignore
      // rather than queue a bogus move the server can never apply.
    }
    final section = await ReminderService.drainNotifSection();
    if (section == 'review' && mounted) {
      Navigator.of(context).push(
        SakuraPageRoute(builder: (_) => const ReviewScreen()),
      );
    }
    if (section == 'quickadd' && mounted) {
      // The daily nudge is a one-tap capture: land in quick-add.
      await showQuickAddTask(context);
    }
    final id = await ReminderService.drainNotifTask();
    if (id == null || !mounted) return;
    Task? found;
    try {
      found =
          TaskRepository.instance.tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      found = null;
    }
    if (found == null || !mounted) return;
    Navigator.of(context).push(
      SakuraPageRoute(builder: (_) => TaskDetailScreen(task: found!)),
    );
  }

  void _go(int i) {
    if (i == _index) return;
    AppHaptics.select();
    TapSound.tap();
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  /// Android back: on any tab but Today it returns to Today instead of
  /// quitting the app (standard Android tab behaviour); on Today it
  /// falls through to the default (background the app).
  void _handleSystemBack() {
    if (_index != 0) {
      _go(0);
      return;
    }
    SystemNavigator.pop();
  }

  // Fresh (non-const) instances every build so a theme change repaints
  // every tab. State is preserved by the element tree (same types,
  // same order). A `static const` list would canonicalize the pages and
  // freeze their SakuraColors forever — that was the "theme won't apply" bug.
  //
  // Cost control: fresh widgets are cheap (configuration objects) and
  // only constructed for the *visible* tab + placeholders elsewhere;
  // the expensive work (API fetches, painters) lives in State objects
  // that Flutter preserves across these rebuilds.
  // ignore: prefer_const_constructors
  Widget _pageAt(int i) {
    if (!_visited.contains(i)) {
      // Cheap placeholder — replaced by the real tab on first visit.
      // TickerMode off: an offstage skeleton must not burn a shimmer
      // controller on cold start.
      return const TickerMode(enabled: false, child: TabSkeleton());
    }
    Widget page;
    switch (i) {
      case 0:
        // ignore: prefer_const_constructors
        page = HomeScreen(embedded: true, guest: _isGuest);
        break;
      case 1:
        // Rituals = Habits + Goals hub (mirrors the Insights hub).
        // ignore: prefer_const_constructors
        page = RitualsHubScreen();
        break;
      case 2:
        // ignore: prefer_const_constructors
        page = FoldersScreen();
        break;
      default:
        // Insights = Analytics + Review + Inbox + Rules hub.
        // ignore: prefer_const_constructors
        page = InsightsHubScreen();
        break;
    }
    return TickerMode(
      enabled: i == _index,
      child: page,
    );
  }

  void _openQuickAdd() {
    AppHaptics.tap();
    TapSound.tap();
    showQuickAddTask(context);
  }

  void _openQuickRitual() {
    AppHaptics.tap();
    TapSound.tap();
    showQuickAddRitual(context);
  }

  /// Contextual "plant" action — one FAB, meaning per surface:
  /// Today + Folders plant a task; Rituals plants a ritual (habit/goal);
  /// Insights is for reflection, so it has no FAB at all.
  Widget? _fabForTab() {
    switch (_index) {
      case 3:
        return null;
      case 1:
        return FloatingActionButton(
          key: const ValueKey('fab-ritual'),
          // Distinct hero tags: two FABs coexist during the
          // AnimatedSwitcher cross-fade, so the shared default tag would
          // trip Flutter's duplicate-hero assertion on the next route push.
          heroTag: 'fab-ritual-hero',
          onPressed: _openQuickRitual,
          tooltip: 'Plant a ritual',
          backgroundColor: SakuraColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          child: const Icon(LucideIcons.sprout, size: 24),
        );
      default:
        return FloatingActionButton(
          key: const ValueKey('fab-task'),
          heroTag: 'fab-task-hero',
          onPressed: _openQuickAdd,
          tooltip: 'Quick add task',
          backgroundColor: SakuraColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          child: const Icon(LucideIcons.plus, size: 24),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Theme owns the scaffold chrome; game ticks only rebuild the
    // ambient background (streak strength), never the tab stack.
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) {
        final body = Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < SakuraBottomNav.items.length; i++)
                    _pageAt(i),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: FocusController.instance,
              builder: (context, _) => AnimatedSwitcher(
                duration: AppMotion.snackbar,
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 0.6), end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: animation, curve: AppMotion.settleCurve)),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: FocusMiniPlayer(
                  key: ValueKey<bool>(FocusController.instance.active),
                ),
              ),
            ),
          ],
        );
        // Hoisted OUT of the game listener: on an XP tick the builder
        // only creates a fresh DynamicBloomBackground — Scaffold and nav
        // are the same instances, so Flutter skips them entirely.
        final scaffold = Scaffold(
          backgroundColor: SakuraColors.background,
          body: PopScope(
            canPop: _index == 0,
            onPopInvokedWithResult: (didPop, _) {
              // Today: default exit/background the app.
              if (didPop) return;
              _handleSystemBack();
            },
            child: body,
          ),
          // Contextual "plant" FAB: task on Today/Folders, ritual on
          // Rituals, none on Insights. Cross-fades as tabs change.
          floatingActionButton: AnimatedSwitcher(
            duration: AppMotion.nav,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _fabForTab() ??
                const SizedBox.shrink(key: ValueKey('fab-none')),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          // One stacked navbar on every width — the same
          // bottom bar phones use. No side rail on desktop.
          bottomNavigationBar: SakuraBottomNav(
            currentIndex: _index,
            onTap: _go,
          ),
        );
        return ListenableBuilder(
          listenable: GamificationStateNotifier.instance,
          builder: (context, _) => DynamicBloomBackground(
            streak: GamificationStateNotifier.instance.streak,
            child: scaffold,
          ),
        );
      },
    );
  }
}
