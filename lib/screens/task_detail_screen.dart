import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/ai_client.dart';
import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/energy_store.dart';
import '../data/haptics.dart';
import '../data/mock_data.dart';
import '../data/task_repository.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_dialog.dart';
import '../widgets/bloom_sheet.dart';
import '../widgets/bloom_snackbar.dart';
import '../widgets/motion.dart';
import '../widgets/timeline_rail.dart';
import 'focus_timer_screen.dart';

String _prettyStatus(String s) {
  switch (s) {
    case 'in_progress':
      return 'In Progress';
    case 'done':
      return 'Done';
    default:
      return 'To-Do';
  }
}

IconData _iconForEvent(String kind) {
  switch (kind) {
    case 'status':
      return LucideIcons.arrowRight;
    case 'renamed':
      return LucideIcons.penLine;
    case 'note':
      return LucideIcons.messageCircle;
    case 'subtask':
      return LucideIcons.checkSquare;
    case 'created':
    default:
      return LucideIcons.sparkles;
  }
}

String _textForEvent(TaskEvent e) {
  switch (e.kind) {
    case 'status':
      return '${_prettyStatus(e.fromStatus ?? 'todo')} → ${_prettyStatus(e.toStatus ?? 'todo')}';
    case 'renamed':
      return 'Renamed to "${e.body}"';
    case 'subtask':
      return '${e.toStatus == 'done' ? 'Checked' : 'Unchecked'} "${e.body}"';
    case 'note':
      return e.body;
    case 'created':
    default:
      return 'Created as ${_prettyStatus(e.toStatus ?? 'todo')}';
  }
}

/// Task flow — status toggle + subtask checklist + timeline.
///
/// The timeline is the task's `task_events` history: created / moves /
/// renames happen automatically on the backend, notes are written here.
class TaskDetailScreen extends StatefulWidget {
  final Task task;
  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _repo = TaskRepository.instance;
  final _subCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  late Task _task;
  List<Subtask> _subs = [];
  List<TaskEvent> _events = [];
  FocusHistory? _focus;
  bool _loading = true;
  bool _savingSub = false;
  bool _savingNote = false;
  bool _breaking = false;
  bool _descDirty = false;
  bool _savingDesc = false;
  List<String> _folders = const [
    'Productivity',
    'Work',
    'Personal',
    'Health',
    'Learning',
  ];

  static const _tags = [
    'General',
    'Work',
    'Home',
    'Health',
    'Learning',
    'Idea',
  ];

  static const _priorities = ['none', 'low', 'medium', 'high'];

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _descCtrl.text = _task.description;
    _descCtrl.addListener(() {
      final dirty = _descCtrl.text != _task.description;
      if (dirty != _descDirty && mounted) {
        setState(() => _descDirty = dirty);
      }
    });
    _load();
    _loadFolders();
  }

  @override
  void dispose() {
    _subCtrl.dispose();
    _noteCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Folder options: live list when reachable, curated fallback offline.
  Future<void> _loadFolders() async {
    try {
      final folders = await BloomApi().fetchFolders();
      if (!mounted || folders.isEmpty) return;
      setState(() {
        _folders = folders.map((f) => f.name).toList();
      });
    } catch (_) {
      // Offline: curated fallback stands.
    }
  }

  Future<void> _load() async {
    try {
      // Read-through cache: server when reachable, last-known copy offline.
      final results = await Future.wait([
        _repo.subtasksFor(_task.id),
        _repo.taskEvents(_task.id),
        _repo.taskFocus(_task.id),
      ]);
      if (!mounted) return;
      setState(() {
        _subs = results[0] as List<Subtask>;
        _events = results[1] as List<TaskEvent>;
        _focus = results[2] as FocusHistory;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return; // AuthGate bounces to login.
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load task flow.')),
      );
    }
  }

  Future<void> _toggleStatus() async {
    final next = nextStatus(_task);
    // Repository: optimistic + offline-safe (queued when offline).
    if (mounted) setState(() => _task = _task.copyWith(status: next));
    await TaskRepository.instance.moveTask(_task.id, next);
    await _load(); // timeline gains a 'status' row
  }

  Future<void> _toggleSub(Subtask s) async {
    // Free two-way toggle: no confirm gate, no lock-in. Light haptic on
    // completion plus a 3s UNDO snackbar; reopening is silently reversed.
    // Routed through the repository so it works offline too.
    final next = !s.done;
    AppHaptics.tap();
    await TaskRepository.instance.setSubtaskDone(s.id, next);
    await _load();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(next ? 'Subtask done 🌸' : 'Subtask reopened'),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await TaskRepository.instance.setSubtaskDone(s.id, !next);
          await _load();
        },
      ),
    ));
  }

  Future<void> _addSub() async {
    final title = _subCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a subtask first.')),
      );
      return;
    }
    setState(() => _savingSub = true);
    final focus = FocusScope.of(context);
    // Repository: optimistic + queued offline.
    await TaskRepository.instance.createSubtask(_task.id, title);
    _subCtrl.clear();
    focus.unfocus();
    await _load();
    if (mounted) setState(() => _savingSub = false);
  }

  Future<void> _deleteSub(Subtask s) async {
    await TaskRepository.instance.deleteSubtask(s.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subtask deleted.')),
      );
    }
  }

  /// AI breakdown: suggest 3-5 subtasks, confirm before creating.
  /// Server upgrades quality (Flash-Lite); offline uses templates.
  Future<void> _breakdown() async {
    if (_breaking) return;
    setState(() => _breaking = true);
    try {
      final steps = await AiClient().breakdown(_task.title);
      if (!mounted || steps.isEmpty) return;
      AppHaptics.tap();
      final picked = await showDialog<List<AiStep>>(
        context: context,
        builder: (ctx) {
          final selected = steps.map((_) => true).toList();
          return StatefulBuilder(
            builder: (ctx, setSheet) => AlertDialog(
              backgroundColor: SakuraColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text('Break it down',
                  style: TextStyle(color: SakuraColors.ink)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      CheckboxListTile(
                        value: selected[i],
                        onChanged: (v) =>
                            setSheet(() => selected[i] = v ?? true),
                        title: Text(steps[i].title,
                            style: TextStyle(color: SakuraColors.ink)),
                        subtitle: Text('${steps[i].minutes} min',
                            style:
                                TextStyle(color: SakuraColors.inkSoft)),
                        activeColor: SakuraColors.primary,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel',
                      style: TextStyle(color: SakuraColors.inkSoft)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: SakuraColors.primary),
                  onPressed: () => Navigator.of(ctx).pop([
                    for (var i = 0; i < steps.length; i++)
                      if (selected[i]) steps[i]
                  ]),
                  child: const Text('Add selected'),
                ),
              ],
            ),
          );
        },
      );
      if (picked == null || picked.isEmpty) return;
      for (final s in picked) {
        await TaskRepository.instance.createSubtask(_task.id, s.title);
      }
      await _load();
    } finally {
      if (mounted) setState(() => _breaking = false);
    }
  }

  Future<void> _addNote() async {
    final body = _noteCtrl.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write the note first.')),
      );
      return;
    }
    setState(() => _savingNote = true);
    final focus = FocusScope.of(context);
    // Repository: online returns the stored event; offline queues it.
    await TaskRepository.instance.addTaskNote(_task.id, body);
    _noteCtrl.clear();
    focus.unfocus();
    await _load();
    if (mounted) setState(() => _savingNote = false);
  }

  /// Opens the full-screen digital timer. Duration picking, countdown,
  /// pause/finish all live there; [FocusController] stays the source
  /// of truth so the mini-player keeps ticking underneath.
  void _showFocusSheet() {
    Navigator.of(context).push(
      SakuraPageRoute(builder: (_) => FocusTimerScreen(task: _task)),
    );
  }

  Future<void> _confirmDelete() async {
    final yes = await showBloomConfirm(
      context,
      title: 'Delete this task?',
      message:
          '"${_task.title}" and its subtasks, notes and history go with it. This cannot be undone.',
      cancelLabel: 'Keep',
    );
    if (!yes || !mounted) return;
    await TaskRepository.instance.deleteTask(_task.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _task.dueAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    // Time is optional: dismissing the time picker keeps date-only.
    final at = await showTimePicker(
      context: context,
      initialTime: _task.dueAt == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(_task.dueAt!.toLocal()),
      helpText: 'Due time (optional — cancel for date-only)',
    );
    if (!mounted) return;
    final due = at == null
        ? DateTime(picked.year, picked.month, picked.day)
        : DateTime(picked.year, picked.month, picked.day, at.hour, at.minute);
    await TaskRepository.instance.updateTask(_task.id, dueAt: due);
    if (!mounted) return;
    setState(() => _task = _task.copyWith(dueAt: due));
  }

  Future<void> _clearDue() async {
    await TaskRepository.instance.updateTask(_task.id, clearDue: true);
    if (!mounted) return;
    setState(() => _task = _task.copyWith(clearDue: true));
  }

  /// Rename via dialog. Empty titles are rejected with feedback.
  Future<void> _editTitle() async {
    final ctrl = TextEditingController(text: _task.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => BloomDialog(
        title: 'Rename task',
        confirmLabel: 'Save',
        onConfirm: () => Navigator.of(ctx).pop(ctrl.text.trim()),
        body: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: BloomDialog.fieldDecoration('Task title'),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
      ),
    );
    // No dispose: showDialog's future completes on pop(), before the
    // reverse transition finishes — disposing here crashes the still-
    // mounted field. The route GCs the controller with itself.
    if (result == null || !mounted) return;
    if (result.isEmpty) {
      showBloomSnackBar(context, 'A title needs at least one character.');
      return;
    }
    await TaskRepository.instance.updateTask(_task.id, title: result);
    if (!mounted) return;
    setState(() => _task = _task.copyWith(title: result));
  }

  /// Save the header description field (Markdown or plaintext).
  Future<void> _saveDescription() async {
    final text = _descCtrl.text.trim();
    setState(() => _savingDesc = true);
    try {
      await TaskRepository.instance
          .updateTask(_task.id, description: text);
      if (!mounted) return;
      setState(() {
        _task = _task.copyWith(description: text);
        _descDirty = false;
      });
    } finally {
      if (mounted) setState(() => _savingDesc = false);
    }
  }

  /// Generic option picker bottom sheet. Returns the tapped value.
  Future<String?> _pickOption({
    required String title,
    required List<String> options,
    required String selected,
  }) {
    return showBloomSheet<String>(
      context,
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              for (final o in options)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(o),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: o == selected
                          ? SakuraColors.primary.withValues(alpha: 0.10)
                          : SakuraColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: o == selected
                            ? SakuraColors.primary
                            : SakuraColors.cardBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            o == 'none' ? 'None' : o,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: o == selected
                                  ? SakuraColors.primary
                                  : SakuraColors.ink,
                            ),
                          ),
                        ),
                        if (o == selected)
                          Icon(LucideIcons.check,
                              size: 15,
                              color: SakuraColors.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickTag() async {
    final options = {
      ..._tags,
      if (!_tags.contains(_task.tag)) _task.tag,
    }.toList();
    final picked = await _pickOption(
        title: 'Tag', options: options, selected: _task.tag);
    if (picked == null || picked == _task.tag || !mounted) return;
    await TaskRepository.instance.updateTask(_task.id, tag: picked);
    if (!mounted) return;
    setState(() => _task = _task.copyWith(tag: picked));
  }

  Future<void> _pickFolder() async {
    final options = {
      ..._folders,
      if (!_folders.contains(_task.folder)) _task.folder,
    }.toList();
    final picked = await _pickOption(
        title: 'Folder', options: options, selected: _task.folder);
    if (picked == null || picked == _task.folder || !mounted) return;
    await TaskRepository.instance.updateTask(_task.id, folder: picked);
    if (!mounted) return;
    setState(() => _task = _task.copyWith(folder: picked));
  }

  Future<void> _pickPriority() async {
    final picked = await _pickOption(
        title: 'Priority', options: _priorities, selected: _task.priority);
    if (picked == null || picked == _task.priority || !mounted) return;
    await TaskRepository.instance.updateTask(_task.id, priority: picked);
    if (!mounted) return;
    setState(() => _task = _task.copyWith(priority: picked));
  }

  /// Snooze-worthy: dated, open, and due today or overdue. A future
  /// date hides the button — pushing next month to tomorrow would be
  /// a lie, and the picker already covers it.
  bool get _snoozable {
    final d = _task.dueAt;
    if (d == null || _task.status == 'done') return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day + 1));
  }

  /// Push the due date out exactly one day, keeping the time of day.
  /// Undo restores the previous stamp; offline reports instead of
  /// hanging.
  Future<void> _snooze() async {
    final prev = _task.dueAt;
    if (prev == null) return;
    final next = DateTime(
        prev.year, prev.month, prev.day + 1, prev.hour, prev.minute);
    await TaskRepository.instance.updateTask(_task.id, dueAt: next);
    if (!mounted) return;
    setState(() => _task = _task.copyWith(dueAt: next));
    showBloomSnackBar(
      context,
      'Snoozed → ${DateFormat('EEE, MMM d').format(next.toLocal())}',
      actionLabel: 'Undo',
      onAction: () async {
        await TaskRepository.instance.updateTask(_task.id, dueAt: prev);
        if (!mounted) return;
        setState(() => _task = _task.copyWith(dueAt: prev));
      },
    );
  }

  Future<void> _reorderSubs(int oldI, int newI) async {
    // onReorderItem already adjusts newI for the removed item.
    final items = [..._subs];
    final moved = items.removeAt(oldI);
    items.insert(newI, moved);
    setState(() => _subs = items);
    // Repository: optimistic + queued offline.
    await TaskRepository.instance
        .reorderSubtasks(_task.id, items.map((s) => s.id).toList());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _subs.where((s) => s.done).length;
    final timeFmt = DateFormat('MMM d · HH:mm');

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
        actions: [
          IconButton(
            icon: Icon(LucideIcons.trash2,
                size: 18, color: SakuraColors.primary),
            tooltip: 'Delete task',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: Entrance(
        delayMs: 80,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  // --- Header: what + where it stands ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: SakuraTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _pickTag,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: SakuraColors.tagBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _task.tag.toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 1.6,
                                            fontWeight: FontWeight.w700,
                                            color: SakuraColors.tagText,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        LucideIcons.penLine,
                                        size: 10,
                                        color: SakuraColors.tagText,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _task.status == 'done'
                                    ? const Color(0xFFE6F4EA)
                                    : SakuraColors.primarySoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _prettyStatus(_task.status).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w700,
                                  color: _task.status == 'done'
                                      ? const Color(0xFF1B7A3D)
                                      : SakuraColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _editTitle,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _task.title,
                                  style: TextStyle(
                                    fontSize: 18,
                                    height: 1.4,
                                    fontWeight: FontWeight.w700,
                                    color: SakuraColors.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Icon(
                                  LucideIcons.penLine,
                                  size: 15,
                                  color: SakuraColors.inkFaint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap the title or badges to edit',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Folder + priority: tappable pills, saved via
                        // the repository (optimistic + offline-queued).
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            GestureDetector(
                              onTap: _pickFolder,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: SakuraColors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: SakuraColors.cardBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.folder,
                                      size: 12,
                                      color: SakuraColors.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        _task.folder,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: SakuraColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _pickPriority,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _task.priority == 'high'
                                      ? SakuraColors.primary
                                          .withValues(alpha: 0.12)
                                      : SakuraColors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _task.priority == 'high'
                                        ? SakuraColors.primary
                                        : SakuraColors.cardBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.flag,
                                      size: 12,
                                      color: _task.priority == 'high'
                                          ? SakuraColors.primary
                                          : SakuraColors.inkFaint,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _task.priority == 'none'
                                          ? 'No priority'
                                          : _task.priority[0]
                                                  .toUpperCase() +
                                              _task.priority.substring(1),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: _task.priority == 'high'
                                            ? SakuraColors.primary
                                            : SakuraColors.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Description / notes: multiline, explicit save.
                        Text(
                          'DESCRIPTION / NOTES',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _descCtrl,
                          minLines: 2,
                          maxLines: 6,
                          textCapitalization:
                              TextCapitalization.sentences,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: SakuraColors.ink),
                          decoration: InputDecoration(
                            hintText:
                                'What does done look like? Links, context…',
                            hintStyle: TextStyle(
                                color: SakuraColors.inkFaint),
                            filled: true,
                            fillColor: SakuraColors.background,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: SakuraColors.cardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: SakuraColors.cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: SakuraColors.primary, width: 1.5),
                            ),
                          ),
                        ),
                        if (_descDirty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: SakuraColors.primary,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 11),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                              onPressed:
                                  _savingDesc ? null : _saveDescription,
                              child: Text(
                                _savingDesc
                                    ? 'Saving…'
                                    : 'Save description',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _pickDue,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.calendarDays,
                                      size: 14,
                                      color: _task.dueAt != null &&
                                              _task.dueAt!.isBefore(
                                                  DateTime.now()) &&
                                              _task.status != 'done'
                                          ? SakuraColors.primary
                                          : SakuraColors.inkFaint,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _task.dueAt == null
                                            ? 'No due date — tap to set'
                                            : 'Due ${DateFormat('EEE, MMM d').format(_task.dueAt!.toLocal())}${_task.dueAt!.hour != 0 || _task.dueAt!.minute != 0 ? ' · ${DateFormat('HH:mm').format(_task.dueAt!.toLocal())}' : ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: SakuraColors.inkSoft,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_snoozable)
                              GestureDetector(
                                onTap: _snooze,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: SakuraColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.alarmClock,
                                          size: 12,
                                          color: SakuraColors.primary),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Tomorrow',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: SakuraColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_task.dueAt != null)
                              GestureDetector(
                                onTap: _clearDue,
                                behavior: HitTestBehavior.opaque,
                                child: Semantics(
                                  button: true,
                                  label: 'Clear due date',
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      LucideIcons.x,
                                      size: 14,
                                      color: SakuraColors.inkFaint,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Energy cost: local overlay (no server column),
                        // set here, read on every card. Tapping the
                        // selected level clears it back to unset.
                        ListenableBuilder(
                          listenable: EnergyStore.instance,
                          builder: (context, _) {
                            final level = EnergyStore.instance
                                .levelFor(_task.id);
                            return Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'ENERGY',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1.6,
                                    fontWeight: FontWeight.w600,
                                    color: SakuraColors.inkFaint,
                                  ),
                                ),
                                for (final l in const [
                                  EnergyStore.low,
                                  EnergyStore.medium,
                                  EnergyStore.high
                                ])
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () => EnergyStore.instance
                                          .setLevel(_task.id,
                                              level == l ? null : l),
                                      behavior:
                                          HitTestBehavior.opaque,
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 7),
                                        decoration: BoxDecoration(
                                          color: level == l
                                              ? SakuraColors.primary
                                                  .withValues(
                                                      alpha: 0.12)
                                              : SakuraColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  12),
                                          border: Border.all(
                                            color: level == l
                                                ? SakuraColors.primary
                                                : SakuraColors
                                                    .cardBorder,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize:
                                              MainAxisSize.min,
                                          children: [
                                            Icon(
                                              energyIcon(l),
                                              size: 13,
                                              color: level == l
                                                  ? SakuraColors
                                                      .primary
                                                  : SakuraColors
                                                      .inkSoft,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              energyLabel(l),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: level == l
                                                    ? SakuraColors
                                                        .primary
                                                    : SakuraColors
                                                        .inkSoft,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        // The task's own created -> done rail, same
                        // grammar as the subtask rows below.
                        if (_task.createdAt != null) ...[
                          const SizedBox(height: 10),
                          TimelineRail(
                            created: _task.createdAt,
                            completed: _task.completedAt,
                            done: _task.status == 'done',
                          ),
                        ],
                        if (_focus != null &&
                            _focus!.totalSessions > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(LucideIcons.timer,
                                  size: 13,
                                  color: SakuraColors.inkFaint),
                              const SizedBox(width: 5),
                              Text(
                                '${_focus!.totalMinutes} min · ${_focus!.totalSessions} sessions',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: SakuraColors.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      SakuraColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                                onPressed: _toggleStatus,
                                child: Text(
                                  _task.status == 'done'
                                      ? 'Reopen task'
                                      : 'Mark done',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _showFocusSheet,
                              child: Container(
                                padding:
                                    const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: SakuraColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    LucideIcons.timer,
                                    size: 18,
                                    color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // --- Subtasks ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: SakuraTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'SUBTASKS',
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
                            const Spacer(),
                            Text(
                              '$doneCount/${_subs.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: SakuraColors.inkSoft,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: GestureDetector(
                                onTap: _breaking ? null : _breakdown,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.sparkles,
                                      size: 12,
                                      color: SakuraColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        _breaking ? 'Thinking…' : 'Break down',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: SakuraColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_subs.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _subs.isEmpty
                                  ? 0
                                  : doneCount / _subs.length,
                              minHeight: 6,
                              backgroundColor:
                                  SakuraColors.primarySoft,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                      SakuraColors.primary),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (_subs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No subtasks yet — break it down below.',
                              style: TextStyle(
                                  color: SakuraColors.inkSoft),
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            itemCount: _subs.length,
                            onReorderItem: _reorderSubs,
                            itemBuilder: (ctx, i) {
                              final s = _subs[i];
                              return Container(
                                key: ValueKey(s.id),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: s.done,
                                      activeColor:
                                          SakuraColors.primary,
                                      // Free toggle: a finished subtask
                                      // can be reopened.
                                      onChanged: (_) =>
                                          _toggleSub(s),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  s.title,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: s.done
                                                        ? SakuraColors
                                                            .inkFaint
                                                        : SakuraColors
                                                            .ink,
                                                    decoration: s.done
                                                        ? TextDecoration
                                                            .lineThrough
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          TimelineRail(
                                            created: s.startedAt,
                                            completed: s.completedAt,
                                            done: s.done,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete subtask',
                                      icon: Icon(
                                          LucideIcons.trash2,
                                          size: 15,
                                          color: SakuraColors
                                              .inkFaint),
                                      onPressed: () =>
                                          _deleteSub(s),
                                    ),
                                    Icon(
                                      LucideIcons.gripVertical,
                                      size: 15,
                                      color:
                                          SakuraColors.inkFaint,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _subCtrl,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: 'Add a subtask…',
                                  filled: true,
                                  fillColor: SakuraColors.surface,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 11),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color:
                                            SakuraColors.cardBorder),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color:
                                            SakuraColors.cardBorder),
                                  ),
                                ),
                                onSubmitted: (_) => _addSub(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _savingSub ? null : _addSub,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: SakuraColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: _savingSub
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(LucideIcons.plus,
                                        size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // --- Timeline ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: SakuraTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FLOW — WHERE THIS TASK HAS BEEN',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w600,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _noteCtrl,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: 'Log an update…',
                                  filled: true,
                                  fillColor: SakuraColors.surface,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 11),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color:
                                            SakuraColors.cardBorder),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color:
                                            SakuraColors.cardBorder),
                                  ),
                                ),
                                onSubmitted: (_) => _addNote(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _savingNote ? null : _addNote,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: SakuraColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: _savingNote
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(LucideIcons.send,
                                        size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_events.isEmpty)
                          Text(
                            'No history yet.',
                            style: TextStyle(
                                color: SakuraColors.inkSoft),
                          )
                        else
                          ..._events.map(
                            (e) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: e.kind == 'note'
                                          ? SakuraColors.primarySoft
                                          : SakuraColors.tagBg,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      _iconForEvent(e.kind),
                                      size: 14,
                                      color: SakuraColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _textForEvent(e),
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            height: 1.4,
                                            color: SakuraColors.ink,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          timeFmt.format(
                                              e.createdAt.toLocal()),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                SakuraColors.inkFaint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
