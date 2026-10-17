import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/mock_data.dart';
import '../data/task_repository.dart';
import '../theme/sakura_theme.dart';
import '../widgets/bloom_dialog.dart';
import '../widgets/motion.dart';
import 'folder_detail_screen.dart';
import 'search_screen.dart';

IconData _iconFor(String name) {
  switch (name) {
    case 'heart':
      return LucideIcons.heart;
    case 'star':
      return LucideIcons.star;
    default:
      return LucideIcons.folder;
  }
}

/// Folders tab — live from Postgres, + adds, tap opens detail.
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  final _api = BloomApi();
  List<BloomFolder> _folders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final folders = await _api.fetchFolders();
      if (!mounted) return;
      setState(() { _folders = folders; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      // Dead token -> AuthGate already routes to login; keep the list
      // empty instead of showing anything as data.
      if (e is AuthExpiredException) {
        setState(() {
          _loading = false;
          _error = 'Session expired — please log in again.';
          _folders = [];
        });
        return;
      }
      // Offline: derive folders from the cached task list so the shelf
      // stays browsable — counts computed locally, never anyone else's.
      final tasks = TaskRepository.instance.tasks;
      final names = <String, List<Task>>{};
      for (final t in tasks) {
        (names[t.folder] ??= []).add(t);
      }
      final fallback = names.entries
          .map((e) => BloomFolder(
                name: e.key,
                total: e.value.length,
                completed:
                    e.value.where((t) => t.status == 'done').length,
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _loading = false;
        _error = tasks.isEmpty
            ? 'API offline — connect to sync your folders.'
            : 'Offline — showing folders from your saved tasks.';
        _folders = fallback;
      });
    }
  }

  Future<void> _addFolder() async {
    final name = await showBloomInput(
      context,
      title: 'New folder',
      hint: 'e.g. Evening Rituals',
    );
    if (name == null || name.isEmpty) return;
    try {
      await _api.createFolder(name);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Folder "$name" added.')));
      }
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString().contains('exists')
                ? 'That folder already exists.'
                : 'Could not add — is the API running?')),
      );
    }
  }

  void _open(BloomFolder f) {
    Navigator.of(context)
        .push(
          SakuraPageRoute(builder: (_) => FolderDetailScreen(folder: f)),
        )
        .then((_) => _load()); // refresh counts on return
  }

  Future<void> _confirmDelete(BloomFolder f) async {
    final yes = await showBloomConfirm(
      context,
      title: 'Delete "${f.name}"?',
      message: f.total > 0
          ? 'It holds ${f.total} task${f.total == 1 ? '' : 's'} — move them out first. Only empty folders can go.'
          : 'This cannot be undone.',
      cancelLabel: 'Keep',
    );
    if (!yes || !mounted) return;
    try {
      await _api.deleteFolder(f.name);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${f.name}".')),
        );
      }
    } catch (e) {
      if (e is AuthExpiredException || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e is AuthException
                ? e.message
                : 'Could not delete folder.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '項目',
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'FOLDERS',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 3.2,
                            fontWeight: FontWeight.w600,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        SakuraPageRoute(
                            builder: (_) => const SearchScreen()),
                      );
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SakuraColors.surface,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: SakuraColors.cardBorder),
                      ),
                      child: Icon(
                        LucideIcons.search,
                        size: 18,
                        color: SakuraColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _addFolder,
                    behavior: HitTestBehavior.opaque,
                    child: Semantics(
                      button: true,
                      label: 'Add folder',
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: SakuraColors.surface,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: SakuraColors.cardBorder),
                        ),
                        child: Icon(
                          LucideIcons.plus,
                          size: 18,
                          color: SakuraColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          fontSize: 11,
                          color: SakuraColors.inkSoft)),
                ),
              const SizedBox(height: 18),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (_folders.isEmpty)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: SakuraTheme.cardDecoration(),
                  child: Column(
                    children: [
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: SakuraColors.primary
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: Icon(LucideIcons.folderPlus,
                              size: 22,
                              color: SakuraColors.primary)),
                      const SizedBox(height: 12),
                      Text('A quiet shelf',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: SakuraColors.ink)),
                      const SizedBox(height: 6),
                      Text(
                          'Turn one area of life — health, work, calm — into a folder. Tasks will gather there.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.55,
                              color: SakuraColors.inkSoft)),
                    ],
                  ),
                )
              else
                ..._folders.map(
                  (f) => GestureDetector(
                    onTap: () => _open(f),
                    onLongPress: () => _confirmDelete(f),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: SakuraTheme.cardDecoration(),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: SakuraColors.tagBg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(_iconFor(f.icon),
                                size: 20,
                                color: SakuraColors.primary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: SakuraColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${f.total} TASKS • ${f.completed} COMPLETED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.6,
                                    fontWeight: FontWeight.w600,
                                    color: SakuraColors.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 18,
                            color: SakuraColors.inkFaint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
