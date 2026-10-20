import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';

/// Reusable bottom nav — Today / Rituals / Folders / Insights.
/// Four ergonomic tabs (down from six): Rituals folds Habits + Goals,
/// Insights folds Analytics + Review + Inbox + Rules. The same order is
/// mirrored 1:1 by AppShell's page stack.
class SakuraBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SakuraBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  /// Shared tab order — AppShell's page stack mirrors this 1:1.
  static const items = [
    LucideIcons.sun,
    LucideIcons.sprout,
    LucideIcons.folder,
    LucideIcons.barChart3,
  ];

  static const labels = [
    'Today',
    'Habits',
    'Folders',
    'Insights',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SakuraColors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
            top: BorderSide(color: SakuraColors.cardBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(SakuraBottomNav.items.length, (i) {
              final active = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Semantics(
                    button: true,
                    label: SakuraBottomNav.labels[i],
                    child: AnimatedContainer(
                      duration: AppMotion.nav,
                      padding:
                          const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: active
                            ? SakuraColors.primary.withValues(alpha: 0.10)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              SakuraBottomNav.items[i],
                              size: 20,
                              color: active
                                  ? SakuraColors.navActive
                                  : SakuraColors.navInactive,
                            ),
                          ),
                        const SizedBox(height: 3),
                        Text(
                          SakuraBottomNav.labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w600,
                            letterSpacing: 0.3,
                            color: active
                                ? SakuraColors.navActive
                                : SakuraColors.navInactive,
                          ),
                        ),
                        AnimatedContainer(
                          duration: AppMotion.nav,
                          width: active ? 5 : 0,
                          height: active ? 5 : 0,
                          margin: const EdgeInsets.only(top: 3),
                          decoration: BoxDecoration(
                            color: SakuraColors.navActive,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            }),
          ),
        ),
      ),
    );
  }
}
