import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/inbox_store.dart';
import '../data/simple_mode.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../widgets/tab_skeleton.dart';
import 'inbox_screen.dart';
import 'insights_screen.dart';
import 'review_screen.dart';

/// Insights tab hub — Analytics + Review + Inbox + Rules under one
/// bottom-nav slot. A compact pill row switches sections; only visited
/// sections build their (network) children, mirroring AppShell's
/// cold-start contract. Inner screens hide their back chevrons because
/// this is a root tab, not a pushed route.
class InsightsHubScreen extends StatefulWidget {
  const InsightsHubScreen({super.key});

  @override
  State<InsightsHubScreen> createState() => _InsightsHubScreenState();
}

class _InsightsHubScreenState extends State<InsightsHubScreen> {
  static const _labels = ['Insights', 'Review', 'Inbox'];
  static const _icons = [
    LucideIcons.barChart3,
    LucideIcons.sparkles,
    LucideIcons.inbox,
  ];

  int _index = 0;
  final Set<int> _visited = {0};

  /// Unread inbox notifications → a small red dot on the Inbox segment.
  /// Shared state: [InboxStore] is published by the Inbox screen itself,
  /// so the dot clears the moment a message is read.
  bool get _hasUnread => InboxStore.instance.hasUnread;

  @override
  void initState() {
    super.initState();
    SimpleMode.instance.load();
    InboxStore.instance.addListener(_onInboxChanged);
    SimpleMode.instance.addListener(_onInboxChanged);
    InboxStore.instance.refresh();
  }

  @override
  void dispose() {
    InboxStore.instance.removeListener(_onInboxChanged);
    SimpleMode.instance.removeListener(_onInboxChanged);
    super.dispose();
  }

  void _onInboxChanged() {
    if (mounted) setState(() {});
  }

  void _go(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
    // Refresh the unread dot when entering the Inbox segment.
    if (i == 2) InboxStore.instance.refresh();
  }

  Widget _pageAt(int i) {
    if (!_visited.contains(i)) {
      // Offstage skeleton placeholder (shimmer paused offscreen).
      return const TickerMode(enabled: false, child: TabSkeleton());
    }
    // Fresh (non-const) instances every build so a theme swap repaints
    // the section: a `const` page canonicalises to the identical widget
    // instance, Flutter skips the child update and the old SakuraColors
    // stay frozen — the same bug AppShell documents for its tab pages.
    // State (stores, scroll offsets) survives — same type, same order.
    Widget page;
    switch (i) {
      case 0:
        // ignore: prefer_const_constructors
        page = InsightsScreen(embedded: true);
        break;
      case 1:
        // ignore: prefer_const_constructors
        page = ReviewScreen(embedded: true);
        break;
      case 2:
        // ignore: prefer_const_constructors
        page = InboxScreen();
        break;
      default:
        // ignore: prefer_const_constructors
        page = InsightsScreen(embedded: true);
        break;
    }
    return TickerMode(enabled: i == _index, child: page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SakuraColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  for (var i = 0; i < _labels.length; i++)
                    Expanded(
                      child: _SegmentButton(
                        label: _labels[i],
                        icon: _icons[i],
                        active: i == _index,
                        badge: i == 2 && _hasUnread,
                        onTap: () => _go(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < _labels.length; i++) _pageAt(i),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;

  /// Small red notification dot (unread inbox items).
  final bool badge;
  final VoidCallback onTap;

  /// Notification red — a system badge semantic, not a theme accent.
  static const _badgeRed = Color(0xFFE53935);

  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        selected: active,
        label: badge ? '$label, unread notifications' : label,
        child: AnimatedContainer(
          duration: AppMotion.nav,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: active
                ? SakuraColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: active
                          ? SakuraColors.navActive
                          : SakuraColors.navInactive,
                    ),
                    if (badge)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _badgeRed,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: SakuraColors.background,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.2,
                  color: active
                      ? SakuraColors.navActive
                      : SakuraColors.navInactive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
