import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../theme/sakura_theme.dart';
import '../widgets/motion.dart';

IconData _iconForKind(String kind) {
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

/// Global activity feed — every task event across the workspace,
/// newest first. The runs log shows automation; this shows people.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _api = BloomApi();
  List<TaskEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await _api.fetchActivity(limit: 50);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load activity.')),
      );
    }
  }

  String _line(TaskEvent e) {
    switch (e.kind) {
      case 'status':
        return 'moved to ${_pretty(e.toStatus)}';
      case 'renamed':
        return 'renamed';
      case 'subtask':
        return '${e.toStatus == 'done' ? 'checked' : 'unchecked'} "${e.body}"';
      case 'note':
        return 'logged: "${e.body}"';
      case 'created':
      default:
        return 'created';
    }
  }

  String _pretty(String? s) {
    switch (s) {
      case 'in_progress':
        return 'In Progress';
      case 'done':
        return 'Done';
      default:
        return 'To-Do';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d · HH:mm');
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
        title: Text('Activity',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: SakuraColors.ink)),
      ),
      body: Entrance(
          delayMs: 80,
          child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.activity,
                          size: 28,
                          color: SakuraColors.inkFaint),
                      const SizedBox(height: 10),
                      Text('Nothing yet — go move a task.',
                          style: TextStyle(
                              color: SakuraColors.inkSoft)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: _events.length,
                    itemBuilder: (ctx, i) {
                      final e = _events[i];
                      return Container(
                        margin:
                            const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration:
                            SakuraTheme.cardDecoration(),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding:
                                  const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: SakuraColors.tagBg,
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _iconForKind(e.kind),
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
                                    e.taskTitle?.isNotEmpty == true
                                        ? e.taskTitle!
                                        : _line(e),
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: SakuraColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _line(e),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: SakuraColors.inkSoft,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    fmt.format(
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
                      );
                    },
                  ),
                ),
    ),
    );
  }
}
