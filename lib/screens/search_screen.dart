import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/ai_client.dart';
import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/haptics.dart';
import '../data/mock_data.dart';
import '../data/task_repository.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/motion.dart';
import '../widgets/task_card.dart';
import 'task_detail_screen.dart';

enum _SearchFilter { all, todo, inProgress, done, highPriority }

/// Global task search — instant 0ms offline-first search across cached tasks,
/// with remote sync fallback and instant filter pills.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = BloomApi();
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Task> _hits = [];
  bool _searching = false;
  bool _touched = false;
  _SearchFilter _activeFilter = _SearchFilter.all;

  /// Ask Bloom answer for the current query (server Flash-Lite,
  /// local keyword scoring offline). Cleared whenever the query resets.
  AiAnswer? _answer;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    TaskRepository.instance.addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    TaskRepository.instance.removeListener(_onRepoChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (!mounted || _ctrl.text.trim().length < 2) return;
    _runLocalSearch(_ctrl.text.trim());
  }

  void _runLocalSearch(String query) {
    final q = query.toLowerCase();
    final localTasks = TaskRepository.instance.tasks;
    final results = localTasks.where((t) {
      final inTitle = t.title.toLowerCase().contains(q);
      final inTag = t.tag.toLowerCase().contains(q);
      final inFolder = t.folder.toLowerCase().contains(q);
      final inDesc = t.description.toLowerCase().contains(q);
      return inTitle || inTag || inFolder || inDesc;
    }).toList();

    setState(() {
      _hits = results;
      _touched = true;
    });
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final query = v.trim();
    if (query.length < 2) {
      setState(() {
        _hits = [];
        _searching = false;
        _touched = false;
        _answer = null;
        _asking = false;
      });
      return;
    }

    // 0ms instant local search from in-memory repository
    _runLocalSearch(query);

    // Background server query if online (merges remote tasks)
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final serverHits = await _api.searchTasks(query);
        if (!mounted || _ctrl.text.trim() != query) return;
        
        // Merge without duplicates by ID
        final seen = <String>{..._hits.map((t) => t.id)};
        final merged = [..._hits];
        for (final t in serverHits) {
          if (seen.add(t.id)) merged.add(t);
        }

        setState(() {
          _hits = merged;
          _searching = false;
        });
      } catch (e) {
        if (!mounted) return;
        if (e is AuthExpiredException) return;
        // Offline: local results are already displayed
        setState(() => _searching = false);
      }
    });
  }

  /// Ask Bloom about the current query. Answers from the server when
  /// online, local keyword scoring offline. Matches open their task.
  Future<void> _ask() async {
    final query = _ctrl.text.trim();
    if (query.length < 2 || _asking) return;
    setState(() {
      _asking = true;
      _answer = null;
    });
    AppHaptics.tap();
    final answer =
        await AiClient().ask(query, TaskRepository.instance.tasks);    if (!mounted) return;
    setState(() {
      _answer = answer;
      _asking = false;
    });
  }

  Future<void> _toggleTask(Task t) async {
    AppHaptics.tap();
    final next = t.status == 'done' ? 'todo' : 'done';
    await TaskRepository.instance.moveTask(t.id, next);
    if (!mounted) return;
    _onChanged(_ctrl.text);
  }

  void _open(Task t) {
    Navigator.of(context)
        .push(SakuraPageRoute(builder: (_) => TaskDetailScreen(task: t)))
        .then((_) {
      if (_ctrl.text.trim().length >= 2) _onChanged(_ctrl.text);
    });
  }

  List<Task> get _filteredHits {
    switch (_activeFilter) {
      case _SearchFilter.all:
        return _hits;
      case _SearchFilter.todo:
        return _hits.where((t) => t.status == 'todo').toList();
      case _SearchFilter.inProgress:
        return _hits.where((t) => t.status == 'in_progress').toList();
      case _SearchFilter.done:
        return _hits.where((t) => t.status == 'done').toList();
      case _SearchFilter.highPriority:
        return _hits.where((t) => t.priority == 'high').toList();
    }
  }

  Widget _filterChip(_SearchFilter filter, String label) {
    final active = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: AppMotion.tap,
        curve: AppMotion.tapCurve,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? SakuraColors.primary.withValues(alpha: 0.16)
              : SakuraColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? SakuraColors.primary : SakuraColors.cardBorder,
            width: active ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? SakuraColors.primary : SakuraColors.inkSoft,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayHits = _filteredHits;

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
          'Search tasks',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: SakuraColors.ink,
          ),
        ),
      ),
      body: Entrance(
          delayMs: 80,
          child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(
                hintText: 'Search title, tag, or folder…',
                hintStyle: TextStyle(color: SakuraColors.inkFaint),
                prefixIcon: Icon(LucideIcons.search,
                    size: 18, color: SakuraColors.inkFaint),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searching)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SakuraColors.primary,
                          ),
                        ),
                      ),
                    if (_ctrl.text.isNotEmpty)
                      IconButton(
                        icon: Icon(LucideIcons.x,
                            size: 16, color: SakuraColors.inkSoft),
                        tooltip: 'Clear',
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      ),
                  ],
                ),
                filled: true,
                fillColor: SakuraColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: SakuraColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: SakuraColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: SakuraColors.primary, width: 1.5),
                ),
              ),
              onChanged: _onChanged,
            ),
          ),
          if (_touched)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  _filterChip(_SearchFilter.all, 'All (${_hits.length})'),
                  const SizedBox(width: 8),
                  _filterChip(
                    _SearchFilter.todo,
                    'To-Do (${_hits.where((t) => t.status == 'todo').length})',
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    _SearchFilter.inProgress,
                    'In Progress (${_hits.where((t) => t.status == 'in_progress').length})',
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    _SearchFilter.done,
                    'Done (${_hits.where((t) => t.status == 'done').length})',
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    _SearchFilter.highPriority,
                    'High Priority (${_hits.where((t) => t.priority == 'high').length})',
                  ),
                ],
              ),
            ),
          if (_touched)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _asking ? null : _ask,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.sparkles,
                          size: 13,
                          color: SakuraColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _asking
                              ? 'Asking Bloom…'
                              : 'Ask Bloom about “${_ctrl.text.trim().length > 30 ? '${_ctrl.text.trim().substring(0, 30)}…' : _ctrl.text.trim()}”',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: SakuraColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_answer != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: SakuraColors.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: SakuraColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _answer!.text,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: SakuraColors.ink,
                            ),
                          ),
                          for (final id in _answer!.ids)
                            Builder(builder: (context) {
                              Task? hit;
                              try {
                                hit = TaskRepository.instance.tasks
                                    .firstWhere((t) => t.id == id);
                              } catch (_) {
                                hit = null;
                              }
                              if (hit == null) {
                                return const SizedBox.shrink();
                              }
                              final h = hit;
                              return GestureDetector(
                                onTap: () => _open(h),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.arrowRight,
                                        size: 12,
                                        color: SakuraColors.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          h.title,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
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
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: !_touched
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.search,
                            size: 32, color: SakuraColors.inkFaint),
                        const SizedBox(height: 10),
                        Text(
                          'Type at least 2 letters to search.',
                          style: TextStyle(
                            fontSize: 13,
                            color: SakuraColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  )
                : displayHits.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.searchX,
                                size: 36, color: SakuraColors.inkFaint),
                            const SizedBox(height: 12),
                            Text(
                              'No blooms found.',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: SakuraColors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try a broader query or switch filters.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: SakuraColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: displayHits.length,
                        itemBuilder: (ctx, i) => TaskCard(
                          task: displayHits[i],
                          onToggle: () => _toggleTask(displayHits[i]),
                          onOpen: () => _open(displayHits[i]),
                        ),
                      ),
          ),
        ],
      ),
      ),
    );
  }
}
