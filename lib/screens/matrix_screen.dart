import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/energy_store.dart';
import '../data/mock_data.dart';
import '../data/task_repository.dart';
import '../theme/sakura_theme.dart';
import '../widgets/kanban_board.dart';
import '../widgets/motion.dart';
import 'focus_timer_screen.dart';
import 'task_detail_screen.dart';

/// Board opens the Kanban board (your desktop reference): TO-DO /
/// IN PROGRESS / DONE columns side by side on wide screens, segmented
/// tabs on phones. One fetch, split client-side by status.
class MatrixScreen extends StatefulWidget {
  const MatrixScreen({super.key});

  @override
  State<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends State<MatrixScreen> {
  final _repo = TaskRepository.instance;
  List<Task> _todo = [];
  List<Task> _prog = [];
  List<Task> _done = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_sync);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_sync);
    super.dispose();
  }

  /// Repository -> columns. Fires on cache load, sync and optimistic edits.
  void _sync() {
    if (!mounted) return;
    setState(() {
      _todo = _repo.todoTasks;
      _prog = _repo.inProgressTasks;
      _done = _repo.doneTasks;
      _loading = false;
    });
  }

  Future<void> _load() async {
    await _repo.loadRemote(withDetails: true);
    if (!mounted) return;
    _sync();
    // Exhaustive id set (unfiltered fetch): safe prune point.
    await EnergyStore.instance.prune(_repo.tasks.map((t) => t.id));
  }

  Future<void> _complete(Task t) => _repo.moveTask(t.id, nextStatus(t));

  Future<void> _toggleSub(Subtask s, bool done) =>
      _repo.setSubtaskDone(s.id, done);

  void _open(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(
            builder: (_) => TaskDetailScreen(task: t)))
        .then((_) => _load());
  }

  void _openTimer(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(
            builder: (_) =>
                FocusTimerScreen(task: t, heroTag: 'board-focus-${t.id}')))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE, MMM d').format(DateTime.now());
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '優先',
              style: TextStyle(
                fontSize: 22,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: SakuraColors.primary,
                letterSpacing: 3.2,
              ),
            ),
            Text(
              'BOARD • $today',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w600,
                color: SakuraColors.inkFaint,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.refreshCw,
                size: 18, color: SakuraColors.inkSoft),
            tooltip: 'Reload',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                children: [
                  Expanded(
                    child: KanbanBoard(
                      todo: _todo,
                      progress: _prog,
                      done: _done,
                      onTap: _complete,
                      onOpen: _open,
                      onToggleSub: _toggleSub,
                      onTimer: _openTimer,
                      expand: true,
                      heroPrefix: 'board-focus-',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
