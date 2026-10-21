import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/inbox_store.dart';
import '../theme/sakura_theme.dart';
import '../widgets/motion.dart';

class InboxItem {
  final String tag;
  final String time;
  final String title;
  final String body;
  final bool unread;
  const InboxItem({
    required this.tag,
    required this.time,
    required this.title,
    required this.body,
    this.unread = false,
  });
}

/// Inbox tab — live flow messages from the backend (rules engine writes
/// here). Offline shows an honest empty state with a reconnect note —
/// never sample messages presented as the user's own.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _api = BloomApi();
  List<InboxItem> _shown = const [];
  List<InboxMessage> _live = [];
  bool _useLive = false;
  bool _offline = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final msgs = await _api.fetchInbox();
      if (!mounted) return;
      final fmt = DateFormat('MMM d');
      setState(() {
        _live = msgs;
        // Online: show exactly what the server has — even when that is
        // nothing (honest empty state below).
        _useLive = true;
        _offline = false;
        _shown = msgs
            .map((m) => InboxItem(
                  tag: m.tag,
                  time: fmt.format(m.createdAt.toLocal()),
                  title: m.title,
                  body: m.body,
                  unread: m.unread,
                ))
            .toList();
        _loading = false;
      });
      // Publish the authoritative unread count so the hub badge clears
      // immediately when a message is read (not only on re-entry).
      InboxStore.instance
          .setUnread(msgs.where((m) => m.unread).length);
    } catch (e) {
      if (!mounted) return;
      if (e is AuthExpiredException) {
        setState(() {
          _loading = false;
          _offline = false;
          _useLive = false;
          _shown = const [];
        });
        return;
      }
      // Trust rule: offline shows an honest empty state + note —
      // never sample achievements presented as the user's own.
      setState(() {
        _useLive = false;
        _offline = true;
        _shown = const [];
        _loading = false;
      });
    }
  }

  Future<void> _open(int index) async {
    if (!_useLive) return;
    final msg = _live[index];
    if (!msg.unread) return;
    try {
      await _api.markInboxRead(msg.id, false);
      await _load();
    } catch (_) {
      // Reading state is best-effort; the message itself was seen.
    }
  }

  int get _unreadCount =>
      _useLive ? _live.where((m) => m.unread).length : 0;

  /// Top-right button: mark every unread message as read. Offline it
  /// explains instead of silently doing nothing (the old dead tap).
  Future<void> _markAllRead() async {
    if (!_useLive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Connect to sync your inbox first.')),
        );
      }
      return;
    }
    final ids =
        _live.where((m) => m.unread).map((m) => m.id).toList();
    if (ids.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already all caught up.')),
        );
      }
      return;
    }
    try {
      await Future.wait(ids.map((id) => _api.markInboxRead(id, false)));
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${ids.length} message${ids.length == 1 ? '' : 's'} marked read.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update inbox.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: Entrance(
        delayMs: 80,
        child: SafeArea(
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
                          '受信',
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
                          'INBOX',
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
                    onTap: _markAllRead,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SakuraColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: SakuraColors.cardBorder),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            LucideIcons.checkCheck,
                            size: 18,
                            color: _unreadCount > 0
                                ? SakuraColors.primary
                                : SakuraColors.inkFaint,
                          ),
                          if (_unreadCount > 0)
                            Positioned(
                              top: -8,
                              right: -8,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1),
                                decoration: BoxDecoration(
                                  color: SakuraColors.primary,
                                  borderRadius:
                                      BorderRadius.circular(
                                          9),
                                ),
                                child: Text(
                                  '$_unreadCount',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w800,
                                    color: Colors.white,
                                    fontFeatures: [
                                      FontFeature
                                          .tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (_offline)
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
                          child: Icon(LucideIcons.cloudOff,
                              size: 22,
                              color: SakuraColors.primary)),
                      const SizedBox(height: 12),
                      Text("You're offline",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: SakuraColors.ink)),
                      const SizedBox(height: 6),
                      Text(
                          'Connect to sync your inbox — notes from your automations will land here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.55,
                              color: SakuraColors.inkSoft)),
                    ],
                  ),
                )
              else if (_useLive && _shown.isEmpty)
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
                          child: Icon(LucideIcons.inbox,
                              size: 22,
                              color: SakuraColors.primary)),
                      const SizedBox(height: 12),
                      Text('All clear, beautifully',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: SakuraColors.ink)),
                      const SizedBox(height: 6),
                      Text(
                          'Nothing needs you right now. Your automations will whisper here when they do.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.55,
                              color: SakuraColors.inkSoft)),
                    ],
                  ),
                )
              else
                // Activity rows stagger in via Entrance below.
              ..._shown.asMap().entries.map(
                  (entry) {
                    final i = entry.key;
                    final m = entry.value;
                    return GestureDetector(
                      onTap: () => _open(i),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: SakuraTheme.cardDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (m.unread)
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: SakuraColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    m.tag,
                                    style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1.6,
                                      fontWeight: FontWeight.w600,
                                      color: SakuraColors.inkFaint,
                                    ),
                                  ),
                                ),
                                Text(
                                  m.time,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: SakuraColors.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              m.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                                color: SakuraColors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              m.body,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: SakuraColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
