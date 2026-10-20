import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/background_music.dart';
import '../data/calendar_export.dart';
import '../data/crash_reports.dart';
import '../data/haptics.dart';
import '../data/habit_store.dart';
import '../data/mock_data.dart';
import '../data/reminders.dart';
import '../data/simple_mode.dart';
import '../data/tap_sound.dart';
import '../data/task_repository.dart';
import '../game/game.dart';

import '../screens/rules_screen.dart';
import '../theme/sakura_theme.dart';


import '../widgets/bloom_dialog.dart';
import '../widgets/motion.dart';
import '../widgets/profile_editor.dart';

String _taskIdentityKey(Task t) =>
    '${t.title.trim().toLowerCase()}|${t.folder.trim().toLowerCase()}|${t.tag.trim().toLowerCase()}|${t.dueAt?.toIso8601String() ?? ''}';


/// Settings — profile, logout, and the Play-required account deletion.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _deleting = false;
  bool _exporting = false;
  bool _exportingIcs = false;
  bool _backupBusy = false;
  bool _reminderOn = false;
  bool _reminderBusy = false;
  int _reminderHour = ReminderService.instance.hour;
  bool _weeklyOn = false;
  bool _simpleOn = false;
  bool _crashOn = true;
  bool _tapSoundOn = true;
  bool _bgmOn = false;

  /// Connection probe state: null = not yet tested this visit.
  bool? _connectionOk;
  String? _connectionDetail;
  bool _probing = false;

  /// Sync issues: pending + dead-letter counts for the Settings row.
  int _pending = 0;
  int _dead = 0;

  @override
  void initState() {
    super.initState();
    ReminderService.instance.load().then((_) {
      if (mounted) {
        setState(() {
          _reminderOn = ReminderService.instance.enabled;
          _reminderHour = ReminderService.instance.hour;
          _weeklyOn = ReminderService.instance.weeklyEnabled;
        });
      }
    });
    SimpleMode.instance.load().then((_) {
      if (mounted) setState(() => _simpleOn = SimpleMode.instance.enabled);
    });
    CrashReports.enabled().then((v) {
      if (mounted) setState(() => _crashOn = v);
    });
    TapSound.load().then((_) {
      if (mounted) setState(() => _tapSoundOn = TapSound.enabled);
    });
    BackgroundMusic.load().then((_) {
      if (mounted) setState(() => _bgmOn = BackgroundMusic.enabled);
    });
  }

  Future<void> _toggleTapSound(bool value) async {
    AppHaptics.tap();
    await TapSound.setEnabled(value);
    if (!mounted) return;
    setState(() => _tapSoundOn = value);
    if (value) await TapSound.tap();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(value
              ? 'Gentle sounds on — taps will whisper.'
              : 'Gentle sounds off — silent touches.')),
    );
  }

  Future<void> _toggleBgm(bool value) async {
    AppHaptics.tap();
    await BackgroundMusic.setEnabled(value);
    if (!mounted) return;
    setState(() => _bgmOn = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(value
              ? 'Background music on — a soft loop follows you around.'
              : 'Background music off — back to quiet blooms.')),
    );
  }

  /// Probe the baked-in backend: GET /health with a short timeout.
  /// Distinguishes "no network" from "server down" from "DB down" so
  /// the user knows which gate is closed (the localhost-APK trap).
  Future<void> _probeConnection() async {
    AppHaptics.tap();
    setState(() {
      _probing = true;
      _connectionOk = null;
      _connectionDetail = null;
    });
    try {
      final res = await BloomApi()
          .probeHealth()
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _connectionOk = res.ok;
        _connectionDetail = res.ok
            ? (res.firebaseReady
                ? 'Backend + database + login all green.'
                : 'Backend reachable, but login service is down — tasks sync, sign-in may fail.')
            : 'Server answered but the database is down (${res.detail ?? 'unknown'}).';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      setState(() {
        _connectionOk = false;
        _connectionDetail = msg.contains('SocketException') ||
                msg.contains('Failed host lookup') ||
                msg.contains('Connection refused')
            ? 'Cannot reach ${BloomApi.baseUrl} — check the baked-in URL or your network.'
            : 'Probe failed: $e';
      });
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _toggleCrash(bool value) async {
    await CrashReports.setEnabled(value);
    if (!mounted) return;
    setState(() => _crashOn = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(value
              ? 'Crash reports on — thanks for helping fix bugs.'
              : 'Crash reports off — takes effect on restart.')),
    );
  }

  Future<void> _toggleReminder(bool value) async {
    setState(() => _reminderBusy = true);
    try {
      final ok = await ReminderService.instance.setEnabled(value);
      if (!mounted) return;
      setState(() {
        _reminderOn = ReminderService.instance.enabled;
      });
      if (value && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Notifications blocked — allow them in system settings, then retry.')),
        );
      }
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  /// Tap the nudge time → OS time picker → re-arm tonight, not tomorrow.
  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: 0),
    );
    if (picked == null || !mounted) return;
    AppHaptics.tap();
    await ReminderService.instance.setTime(picked.hour);
    if (!mounted) return;
    setState(() => _reminderHour = ReminderService.instance.hour);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_reminderOn
            ? 'Daily nudge moved to $_reminderHour:00.'
            : 'Saved — the nudge fires at $_reminderHour:00 when turned on.')));
  }

  /// Sunday review — its own promise (a look-back), its own switch.
  Future<void> _toggleWeekly(bool value) async {
    AppHaptics.tap();
    final ok = await ReminderService.instance.setWeekly(value);
    if (!mounted) return;
    setState(() => _weeklyOn = ok && ReminderService.instance.weeklyEnabled);
    if (value && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Notifications blocked — allow them in system settings, then retry.')));
    }
  }

  /// Simple mode: hide the power tools (Board, Rules) for a calmer app.
  Future<void> _toggleSimpleMode(bool value) async {
    AppHaptics.tap();
    await SimpleMode.instance.setEnabled(value);
    if (!mounted) return;
    setState(() => _simpleOn = SimpleMode.instance.enabled);
  }

  /// Fixed danger crimson — never the theme primary, so Delete reads
  /// as danger even on green (Kyoto) or pink (Midnight) themes.
  static const _danger = Color(0xFFD33A4E);

  /// Profile editor: rename everywhere the name is read from, persist the
  /// timezone pick, and map the two toggles onto the real reminder
  /// services. A denied notification permission keeps the toggles off and
  /// explains instead of failing the whole save.
  Future<void> _openProfileEditor() async {
    final user = AuthStore.instance.user;
    if (user == null) return;
    AppHaptics.tap();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => ProfileEditor(
        user: AuthStore.instance.user ?? user,
        dailyReminderHour: ReminderService.instance.hour,
        onSave: (result) async {
          await AuthStore.instance.updateDisplayName(result.displayName);
          await ReminderService.instance
              .setTimezoneOverride(result.timezone);
          final dailyOk = result.notificationsEnabled
              ? await ReminderService.instance.setEnabled(true)
              : await ReminderService.instance.setEnabled(false);
          final reviewOk = result.dailyReminder
              ? await ReminderService.instance.setWeekly(true)
              : await ReminderService.instance.setWeekly(false);
          await ReminderService.instance.setTime(result.dailyReminderHour);
          if (!dailyOk || !reviewOk) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Notifications blocked - allow them in system settings, then retry.'),
                ),
              );
            }
          }
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      _reminderOn = ReminderService.instance.enabled;
      _reminderHour = ReminderService.instance.hour;
      _weeklyOn = ReminderService.instance.weeklyEnabled;
    });
    if (saved == true && mounted) {
      AppHaptics.confirm();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved.')),
      );
    }
  }

  Future<void> _logout() async {
    ThemeStore.instance.resetToDefault();
    // Drop this account's due alarms: they reference tasks that no
    // longer belong on this device.
    await ReminderService.instance.cancelAllTaskReminders();
    await AuthStore.instance.logout();
    // AuthGate swaps to login; this tree is discarded.
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final data = await BloomApi().fetchExport();
      final text =
          const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: text));
      final n = (data['tasks'] as List?)?.length ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Copied $n tasks + history to clipboard.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed.')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Sync issues row: visible only when something is queued or parked.
  /// Queued items flush automatically on reconnect (already reported by
  /// Home's pill); dead letters need a human — they were rejected 5x,
  /// so Retry + Discard are offered explicitly.
  Widget _syncIssueRow() {
    final repo = TaskRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        _pending = repo.pendingMutations;
        _dead = repo.deadLetterCount;
        if (_pending == 0 && _dead == 0) return const SizedBox.shrink();
        final parts = <String>[
          if (_pending > 0) '$_pending waiting to sync',
          if (_dead > 0) '$_dead could not sync',
        ];
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _dead > 0
                  ? SakuraColors.primary.withValues(alpha: 0.07)
                  : SakuraColors.background,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: SakuraColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _dead > 0
                          ? LucideIcons.triangleAlert
                          : LucideIcons.refreshCw,
                      size: 14,
                      color: SakuraColors.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        parts.join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SakuraColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_dead > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'These changes were rejected. Retry once the server is healthy.',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: SakuraColors.inkSoft),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SakuraColors.primary,
                          side: BorderSide(
                              color: SakuraColors.primary),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                        onPressed: () async {
                          await repo.retryDeadLetters();
                        },
                        child: const Text('Retry',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SakuraColors.inkSoft,
                          side: BorderSide(
                              color: SakuraColors.cardBorder),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                        ),
                        onPressed: () async {
                          await repo.discardDeadLetters();
                        },
                        child: const Text('Discard',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _backupBusy = true);
    try {
      final game = GamificationStateNotifier.instance;
      final backup = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': [
          for (final t in TaskRepository.instance.tasks) t.toJson()
        ],
        'goals': [for (final g in HabitStore.instance.goals) g.toJson()],
        'habits': [
          for (final h in HabitStore.instance.habits) h.toJson()
        ],
        'stats': {
          'totalXp': game.totalXp,
          'tokens': game.tokens,
          'streak': game.streak,
          'level': game.level,
        },
      };
      if (kIsWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Backup files need the mobile or desktop app.')),
        );
        return;
      }
      final file = await File(
              '${Directory.systemTemp.path}/daily-bloom-backup.json')
          .writeAsString(jsonEncode(backup));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          text: 'Daily Bloom Backup',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup export failed.')),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  /// Import a backup: paste JSON (exported above) into the dialog, confirm,
  /// then merge. Existing ids are skipped (no duplicates); game stats only
  /// ever move up, never down.
  Future<void> _importBackup() async {    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return BloomDialog(
          title: 'Import backup',
          confirmLabel: 'Review',
          onConfirm: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste a Daily Bloom backup JSON below. Duplicates are skipped; game stats only move up.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: SakuraColors.inkSoft),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                minLines: 4,
                maxLines: 8,
                maxLength: 500000,
                style: TextStyle(color: SakuraColors.ink, fontSize: 12),
                decoration: BloomDialog.fieldDecoration(
                    '{"version": 1, "tasks": […]}'),
              ),
            ],
          ),
        );
      },
    );
    if (pasted == null || pasted.isEmpty || !mounted) return;
    Map<String, dynamic> backup;
    try {
      final decoded = jsonDecode(pasted);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      backup = decoded;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That is not valid backup JSON.')),
      );
      return;
    }
    final yes = await showBloomConfirm(
      context,
      title: 'Merge this backup?',
      message:
          'New tasks and habits are added; anything already here is skipped. This cannot be undone in bulk.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Merge',
    );
    if (!yes || !mounted) return;
    setState(() => _backupBusy = true);
    try {
      var tasksAdded = 0;
      var tasksSkipped = 0;
      var habitsAdded = 0;
      var habitsSkipped = 0;
      final repo = TaskRepository.instance;
      // Dedupe by id AND by identity: `createTask` mints a fresh id for
      // every restore, so an id-only check let the SAME import run twice
      // silently duplicate every task. Identity (title + folder + tag +
      // due) is the stable key a backup carries across devices.
      final existingIds = repo.tasks.map((t) => t.id).toSet();
      final existingKeys = repo.tasks.map(_taskIdentityKey).toSet();
      final rawTasks = backup['tasks'];
      if (rawTasks is List) {
        for (final raw in rawTasks) {
          if (raw is! Map<String, dynamic>) continue;
          Task task;
          try {
            task = Task.fromJson(raw);
          } catch (_) {
            continue;
          }
          if (task.id.isEmpty ||
              existingIds.contains(task.id) ||
              existingKeys.contains(_taskIdentityKey(task))) {
            tasksSkipped++;
            continue;
          }
          existingKeys.add(_taskIdentityKey(task));
          final created = await repo.createTask(
            title: task.title,
            folder: task.folder,
            tag: task.tag,
            description: task.description,
            priority: task.priority,
            recurring: task.recurring,
            dueAt: task.dueAt,
          );
          final subs = task.subtasks ?? const [];
          for (final s in subs) {
            final sub = await repo.createSubtask(created.id, s.title);
            if (s.done) await repo.setSubtaskDone(sub.id, true);
          }
          if (task.status != 'todo') {
            await repo.moveTask(created.id, task.status);
          }
          tasksAdded++;
        }
      }
      // Goals first (habits reference them); remap old goal ids to new.
      final store = HabitStore.instance;
      final existingHabits = store.habits.map((h) => h.id).toSet();
      final goalMap = <String, String>{};
      final rawGoals = backup['goals'];
      if (rawGoals is List) {
        for (final raw in rawGoals) {
          if (raw is! Map<String, dynamic>) continue;
          HabitGoal goal;
          try {
            goal = HabitGoal.fromJson(raw);
          } catch (_) {
            continue;
          }
          if (goal.id.isEmpty) continue;
          final created = await store.addGoal(
            name: goal.name,
            intention: goal.intention,
            iconIndex: goal.iconIndex,
            accentIndex: goal.accentIndex,
          );
          goalMap[goal.id] = created.id;
        }
      }
      final rawHabits = backup['habits'];
      if (rawHabits is List) {
        for (final raw in rawHabits) {
          if (raw is! Map<String, dynamic>) continue;
          Habit habit;
          try {
            habit = Habit.fromJson(raw);
          } catch (_) {
            continue;
          }
          if (habit.id.isEmpty || existingHabits.contains(habit.id)) {
            habitsSkipped++;
            continue;
          }
          final goalId =
              habit.goalId == null ? null : goalMap[habit.goalId];
          await store.restoreHabit(habit.copyWith(goalId: () => goalId));
          habitsAdded++;
        }
      }
      // Stats only move up — a restore never erases progress.
      final game = GamificationStateNotifier.instance;
      final stats = backup['stats'];
      if (stats is Map<String, dynamic>) {
        final xp = (stats['totalXp'] as num?)?.toInt() ?? 0;
        final tokens = (stats['tokens'] as num?)?.toInt() ?? 0;
        final streak = (stats['streak'] as num?)?.toInt() ?? 0;
        if (xp > game.totalXp) game.addXp(xp - game.totalXp);
        if (tokens > game.tokens) game.addTokens(tokens - game.tokens);
        if (streak > game.streak) game.setStreak(streak);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Restored $tasksAdded tasks, $habitsAdded habits'
                '${tasksSkipped + habitsSkipped > 0 ? ' (${tasksSkipped + habitsSkipped} duplicates skipped)' : ''}.')),
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _exportCalendar() async {
    setState(() => _exportingIcs = true);
    try {
      final tasks = await BloomApi().fetchTasks(withDetails: false);
      final n = datedCount(tasks);
      if (!mounted) return;
      if (n == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No dated tasks — set a due date first.')),
        );
        return;
      }
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Calendar files need the mobile or desktop app.')),
        );
        return;
      }
      final file = await File(
              '${Directory.systemTemp.path}/daily-bloom.ics')
          .writeAsString(buildIcs(tasks));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/calendar')],
          text: 'My Daily Bloom tasks',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calendar export failed.')),
      );
    } finally {
      if (mounted) setState(() => _exportingIcs = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ctrl = TextEditingController();
    var typedOk = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => BloomDialog(
          title: 'Delete account?',
          confirmLabel: 'Delete',
          confirmEnabled: typedOk,
          confirmColor: _SettingsScreenState._danger,
          onConfirm: () => Navigator.of(ctx).pop(true),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This removes your login, tokens, inbox and flows. Task history goes anonymous; shared tasks stay. This cannot be undone.',
                style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: SakuraColors.inkSoft),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.characters,
                decoration: BloomDialog.fieldDecoration(
                    'Type DELETE to confirm'),
                onChanged: (v) =>
                    setSheet(() => typedOk = v.trim() == 'DELETE'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      ThemeStore.instance.resetToDefault();
      await AuthStore.instance.deleteAccount();
      // AuthGate takes it from here.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is AuthException
                ? e.message
                : 'Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Crash-proof avatar initial (empty strings have no `.first`).
  String _initial(AuthUser? user) {
    final src = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : (user?.email ?? '');
    final t = src.trim();
    if (t.isEmpty) return '✿';
    return t.characters.first.toUpperCase();
  }

  ButtonStyle get _actionStyle => OutlinedButton.styleFrom(
        foregroundColor: SakuraColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: SakuraColors.cardBorder),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final user = AuthStore.instance.user;
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
        title: Text('Settings',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: SakuraColors.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: SakuraTheme.cardDecoration(),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: SakuraColors.primarySoft,
                  child: Text(
                    _initial(user),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: SakuraColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName.isNotEmpty == true
                            ? user!.displayName
                            : 'Bloomer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.ink),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                          message: 'Edit profile',
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(88, 40),
                              tapTargetSize: MaterialTapTargetSize.padded,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: _openProfileEditor,
                            icon: Icon(LucideIcons.pencil,
                                size: 13, color: SakuraColors.primary),
                            label: Text(
                              'Edit profile',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: SakuraColors.primary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: SakuraColors.inkSoft),
                      ),
                      const SizedBox(height: 6),
                      ListenableBuilder(
                        listenable:
                            GamificationStateNotifier.instance,
                        builder: (context, _) {
                          final game =
                              GamificationStateNotifier
                                  .instance;
                          final xp = game.level >=
                                  BloomEngine.maxLevel
                              ? 'MAX'
                              : '${game.xpIntoLevel}/${game.xpNeeded} XP';
                          return Text(
                            '${game.rankName} · Lv ${game.level} — $xp · ◆ ${game.tokens} · ${game.streak}d streak',
                            style: TextStyle(
                              fontSize: 11,
                              color: SakuraColors.inkFaint,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: SakuraTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  style: _actionStyle,
                  onPressed: _logout,
                  icon: const Icon(LucideIcons.logOut,
                      size: 15),
                  label: const Text('Log out',
                      style: TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: _actionStyle,
                  onPressed: _exporting ? null : _export,
                  icon: _exporting
                      ? const SizedBox(
                          height: 15,
                          width: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Icon(LucideIcons.download,
                          size: 15),
                  label: const Text('Export my data',
                      style: TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: _actionStyle,
                  onPressed: _exportingIcs ? null : _exportCalendar,
                  icon: _exportingIcs
                      ? const SizedBox(
                          height: 15,
                          width: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Icon(LucideIcons.calendarDays,
                          size: 15),
                  label: const Text('Export calendar (.ics)',
                      style: TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: _actionStyle,
                  onPressed: _backupBusy ? null : _exportBackup,
                  icon: _backupBusy
                      ? const SizedBox(
                          height: 15,
                          width: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Icon(LucideIcons.databaseBackup,
                          size: 15),
                  label: const Text('Export all data (JSON)',
                      style: TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: _actionStyle,
                  onPressed: _backupBusy ? null : _importBackup,
                  icon: const Icon(LucideIcons.databaseZap,
                      size: 15),
                  label: const Text('Import backup (JSON)',
                      style: TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
                _syncIssueRow(),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: SakuraTheme.cardDecoration(),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SakuraColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.bell,
                      size: 15, color: SakuraColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily reminder',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'One gentle nudge at $_reminderHour:00 — never more.',
                        style: TextStyle(
                            fontSize: 12, color: SakuraColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _reminderBusy ? null : _pickReminderTime,
                  child: const Text('Change',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: _reminderOn,
                  onChanged:
                      _reminderBusy ? null : (v) => _toggleReminder(v),
                  activeThumbColor: SakuraColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: SakuraTheme.cardDecoration(),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SakuraColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.bug,
                      size: 15, color: SakuraColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crash reports',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Anonymous crash logs only — off switch takes effect on restart.',
                        style: TextStyle(
                            fontSize: 12, color: SakuraColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _crashOn,
                  onChanged: (v) => _toggleCrash(v),
                  activeThumbColor: SakuraColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: SakuraTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.wifi,
                        size: 13, color: SakuraColors.inkFaint),
                    const SizedBox(width: 7),
                    Text(
                      'CONNECTION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                        color: SakuraColors.inkFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  BloomApi.baseUrl,
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: SakuraColors.inkSoft),
                ),
                const SizedBox(height: 4),
                Text(
                  _connectionOk == null
                      ? 'Untested this visit — tap Test to check the backend, database and login service.'
                      : (_connectionOk!
                          ? _connectionDetail ?? 'All green.'
                          : _connectionDetail ?? 'Unreachable.'),
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: _connectionOk == null
                          ? SakuraColors.inkSoft
                          : (_connectionOk!
                              ? SakuraColors.primary
                              : _danger)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _probing ? null : _probeConnection,
                    icon: _probing
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.activity, size: 14),
                    label: Text(_probing ? 'Testing…' : 'Test connection'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Audio ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: SakuraTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: SakuraColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.volume2,
                        size: 15,
                        color: SakuraColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gentle sounds',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Soft blip on Plant and Done. Focus bell and rain are separate.',
                            style: TextStyle(
                              fontSize: 12,
                              color: SakuraColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Switch(
                  value: _tapSoundOn,
                  onChanged: (v) => _toggleTapSound(v),
                  activeThumbColor: SakuraColors.primary,
                ),
                const SizedBox(height: 4),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: SakuraColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.music,
                        size: 15,
                        color: SakuraColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Background music',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'A soft looping melody across the app. Off until you say so.',
                            style: TextStyle(
                              fontSize: 12,
                              color: SakuraColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Switch(
                  value: _bgmOn,
                  onChanged: (v) => _toggleBgm(v),
                  activeThumbColor: SakuraColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              decoration: SakuraTheme.cardDecoration(),
              child: Row(
                children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SakuraColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.calendarDays,
                      size: 15, color: SakuraColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sunday review',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'A calm look-back at your week, Sunday evening.',
                        style: TextStyle(
                            fontSize: 12, color: SakuraColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _weeklyOn,
                  onChanged: _toggleWeekly,
                  activeThumbColor: SakuraColors.primary,
                ),
              ],
            ),
          ),
          ),
          const SizedBox(height: 14),
          // Simple mode — progressive disclosure for a calmer app.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: SakuraTheme.cardDecoration(),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SakuraColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.moon,
                      size: 15, color: SakuraColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Simple mode',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hide power tools (Board, Rules) for a calmer home.',
                        style: TextStyle(
                            fontSize: 12, color: SakuraColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _simpleOn,
                  onChanged: _toggleSimpleMode,
                  activeThumbColor: SakuraColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Rules & automations — moved out of the Insights hub so it no
          // longer fights for space with analytics/review/inbox.
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              SakuraPageRoute(builder: (_) => const RulesScreen()),
            ),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: SakuraTheme.cardDecoration(),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SakuraColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.workflow,
                        size: 15, color: SakuraColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rules & automations',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Automate task flows, reminders and reviews.',
                          style: TextStyle(
                              fontSize: 12, color: SakuraColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronRight,
                      size: 16, color: SakuraColors.inkFaint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _danger.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _danger.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(LucideIcons.triangleAlert,
                        size: 13, color: _danger),
                    SizedBox(width: 7),
                    Text(
                      'DANGER ZONE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                        color: _danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Deleting removes your login, tokens, inbox and flows. This cannot be undone.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: SakuraColors.inkSoft),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: _danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14))),
                  onPressed:
                      _deleting ? null : _confirmDelete,
                  icon: _deleting
                      ? const SizedBox(
                          height: 15,
                          width: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(LucideIcons.trash2,
                          size: 15),
                  label: Text(
                      _deleting ? 'Deleting…' : 'Delete account',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Daily Bloom 1.0.0 · your data stays yours —\nexport or delete it anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: SakuraColors.inkFaint),
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
