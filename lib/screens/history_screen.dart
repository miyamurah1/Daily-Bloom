import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/mock_data.dart';
import '../data/task_repository.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_snackbar.dart';
import '../widgets/motion.dart';
import 'task_detail_screen.dart';

/// History: completed tasks on top, each expandable to its subtasks —
/// then the subtask tick feed below (checked/unchecked, newest first).
///
/// Completed tasks come from one `status=done` fetch with details;
/// subtask rows come from the activity feed filtered to kind `subtask`
/// (logged by the server since migration 014).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = BloomApi();
  final _searchCtrl = TextEditingController();
  List<Task> _done = [];
  List<TaskEvent> _subEvents = [];
  bool _loading = true;
  String? _openId;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.fetchTasks(status: 'done', withDetails: true),
        _api.fetchActivity(limit: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _done = results[0] as List<Task>;
        _subEvents = (results[1] as List<TaskEvent>)
            .where((e) => e.kind == 'subtask')
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      // Offline: the repository's cached done list stands in — history
      // stays browsable (and searchable) with zero network.
      setState(() {
        _done = TaskRepository.instance.doneTasks;
        _loading = false;
      });
      showBloomSnackBar(context, 'Offline — showing your saved history.');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _open(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(builder: (_) => TaskDetailScreen(task: t)))
        .then((_) => _load());
  }

  /// Local filter over the already-loaded history (small datasets:
  /// done tasks + last 100 ticks). Matches titles, tags, and tick bodies.
  List<Task> get _filteredDone {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _done;
    return _done
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.tag.toLowerCase().contains(q))
        .toList();
  }

  List<TaskEvent> get _filteredEvents {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _subEvents;
    return _subEvents
        .where((e) =>
            e.body.toLowerCase().contains(q) ||
            (e.taskTitle ?? '').toLowerCase().contains(q))
        .toList();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('MMM d · HH:mm');
    final done = _filteredDone;
    final events = _filteredEvents;
    final filtering = _query.trim().isNotEmpty;
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
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (v) =>
                    setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search history…',
                  hintStyle: TextStyle(
                      color: SakuraColors.inkFaint),
                  border: InputBorder.none,
                ),
                style: TextStyle(
                    fontSize: 16, color: SakuraColors.ink),
              )
            : Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    '履歴',
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: SakuraColors.primary,
                      letterSpacing: 3.2,
                    ),
                  ),
                  Text(
                    'HISTORY',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 3.2,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(
                _searching
                    ? LucideIcons.x
                    : LucideIcons.search,
                size: 18,
                color: SakuraColors.primary),
            tooltip: _searching
                ? 'Close search'
                : 'Search history',
            onPressed: _toggleSearch,
          ),
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    'COMPLETED TASKS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (done.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration:
                          SakuraTheme.cardDecoration(),
                      child: Text(
                        filtering
                            ? 'No completed tasks match "$_query".'
                            : 'Nothing finished yet — done tasks land here with their subtasks under them.',
                        style: TextStyle(
                            height: 1.5,
                            color: SakuraColors.inkSoft),
                      ),
                    )
                  else
                    ...done.map(_taskCard),
                  const SizedBox(height: 20),
                  Text(
                    'SUBTASK TICKS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (events.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration:
                          SakuraTheme.cardDecoration(),
                      child: Text(
                        filtering
                            ? 'No subtask ticks match "$_query".'
                            : 'No subtask ticks yet — they appear here from now on.',
                        style: TextStyle(
                            height: 1.5,
                            color: SakuraColors.inkSoft),
                      ),
                    )
                  else
                    ...events.map(
                      (e) => Container(
                        margin:
                            const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration:
                            SakuraTheme.cardDecoration(),
                        child: Row(
                          children: [
                            Icon(
                              e.toStatus == 'done'
                                  ? LucideIcons.checkSquare
                                  : LucideIcons.square,
                              size: 15,
                              color: e.toStatus == 'done'
                                  ? const Color(0xFF1B7A3D)
                                  : SakuraColors.inkFaint,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.body,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: SakuraColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${e.taskTitle?.isNotEmpty == true ? e.taskTitle! : 'a task'} • ${timeFmt.format(e.createdAt.toLocal())}',
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
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
    );
  }

  Widget _taskCard(Task t) {
    final subs = t.subtasks ?? [];
    final open = _openId == t.id;
    final doneCount = subs.where((s) => s.done).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _openId = open ? null : t.id),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F4EA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.check,
                        size: 14,
                        color: Color(0xFF1B7A3D)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subs.isEmpty
                              ? 'no subtasks'
                              : '$doneCount/${subs.length} subtasks',
                          style: TextStyle(
                            fontSize: 11,
                            color: SakuraColors.inkFaint,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    open
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 16,
                    color: SakuraColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            Container(
                height: 1, color: SakuraColors.cardBorder),
            if (subs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('No subtasks on this one.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: SakuraColors.inkSoft)),
              )
            else
              ...subs.map(
                (s) => Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        s.done
                            ? LucideIcons.checkSquare
                            : LucideIcons.square,
                        size: 15,
                        color: s.done
                            ? const Color(0xFF1B7A3D)
                            : SakuraColors.inkFaint,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: s.done
                                ? SakuraColors.inkFaint
                                : SakuraColors.ink,
                            decoration: s.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            GestureDetector(
              onTap: () => _open(t),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    16, 4, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Open full flow',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.primary)),
                    const SizedBox(width: 4),
                    Icon(LucideIcons.arrowRight,
                        size: 13,
                        color: SakuraColors.primary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
