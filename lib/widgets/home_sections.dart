import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/haptics.dart';
import '../data/simple_mode.dart';
import '../data/task_repository.dart';
import '../widgets/motion.dart';
import '../game/game.dart';
import '../screens/history_screen.dart';
import '../screens/insights_screen.dart';
import '../screens/matrix_screen.dart';
import '../screens/review_screen.dart';
import '../theme/sakura_theme.dart';

/// Live/offline sync pill + offline note. Pure presentational extract.
///
/// Offline honesty: queued counts say "saved on this phone" so users
/// never wonder if their tasks are lost. A Retry tap forces syncNow.
class SyncBanner extends StatelessWidget {
  final bool live;
  final String? note;

  const SyncBanner({super.key, required this.live, this.note});

  @override
  Widget build(BuildContext context) {
    // Queued-mutation count rides the pill: on flaky networks the user
    // sees "2 queued" instead of wondering where their task went.
    return ListenableBuilder(
      listenable: TaskRepository.instance,
      builder: (context, _) {
        final pending = TaskRepository.instance.pendingMutations;
        final label = live
            ? (pending > 0 ? '● live db · $pending queued' : '● live db')
            : (pending > 0 ? '○ offline · $pending queued' : '○ offline');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: pending > 0
                      ? () {
                          AppHaptics.tap();
                          TaskRepository.instance.syncNow();
                        }
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      // Theme-native states: tinted brand when live, quiet
                      // surface when offline — no pastel hardcodes glowing in
                      // Midnight. Matches the app-bar pill language.
                      color: live
                          ? SakuraColors.primarySoft
                          : SakuraColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SakuraColors.cardBorder),
                    ),
                    child: Text(
                      pending > 0 ? '$label · retry' : label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: live
                            ? SakuraColors.primary
                            : SakuraColors.inkSoft,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (note != null)
              Padding(
                padding:
                    const EdgeInsets.only(top: 6, left: 20, right: 20),
                child: Text(
                    pending > 0
                        ? 'API offline — $pending change${pending == 1 ? '' : 's'} saved on this phone, will send when online. Tap the pill to retry.'
                        : note!,
                    style: TextStyle(
                        fontSize: 11, color: SakuraColors.inkSoft)),
              ),
          ],
        );
      },
    );
  }
}

/// Board / History / Insights / Review shortcuts. Extracted so both
/// layouts share it. Door count adapts to Simple Mode (Board is hidden
/// in calm mode — it's a power tool).
class QuickLinks extends StatelessWidget {
  const QuickLinks({super.key});

  /// Door count — Simple mode drops the power door (Board).
  static int get rowCount => SimpleMode.instance.enabled ? 3 : 4;

  /// Single row item for the mobile [SliverList].
  static Widget rowItem(int index, BuildContext context) {
    // One style for all four: all caps, single trailing arrow.
    // Simple mode reindexes: Board is the power tool that goes first.
    final i = SimpleMode.instance.enabled ? index + 1 : index;
    switch (i) {
      case 0:
        return _link(context, 'BOARD →', () {
          Navigator.of(context).push(
            SakuraPageRoute(builder: (_) => const MatrixScreen()),
          );
        });
      case 1:
        return _link(context, 'HISTORY →', () {
          Navigator.of(context).push(
            SakuraPageRoute(builder: (_) => const HistoryScreen()),
          );
        });
      case 2:
        return _link(context, 'VIEW INSIGHTS →', () {
          Navigator.of(context).push(
            SakuraPageRoute(builder: (_) => const InsightsScreen()),
          );
        });
      default:
        return _link(context, 'REVIEW →', () {
          Navigator.of(context).push(
            SakuraPageRoute(builder: (_) => const ReviewScreen()),
          );
        });
    }
  }

  static Widget _link(
      BuildContext context, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
            color: SakuraColors.primary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wrap (not spaceBetween Row): the master column is narrow on
    // desktop and phones are narrower still — never overflow.
    return Wrap(
      spacing: 20,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      children: [
        for (var i = 0; i < rowCount; i++) rowItem(i, context),
      ],
    );
  }
}

/// Compact progression header: rank badge + XP bar + combo / tokens.
/// Listens to the game singleton itself so an XP/tick update rebuilds
/// this card only — Home's root builder no longer subscribes to game
/// state (that rebuilt the heatmap + board on every XP gain).
class GameHud extends StatelessWidget {
  final VoidCallback onBloom;

  const GameHud({super.key, required this.onBloom});

  @override
  Widget build(BuildContext context) {
    // Merge game + theme: the card repaints on XP changes AND theme swaps,
    // so it can never go stale (white-on-dark) after equipping a theme.
    return ListenableBuilder(
      listenable: Listenable.merge([
        GamificationStateNotifier.instance,
        ThemeStore.instance,
      ]),
      builder: (context, _) {
        final game = GamificationStateNotifier.instance;
        // Compact bento cell: rank + level + streak/combo + XP bar + a
        // small bloom button. Sized to live beside the intention cell in
        // the ~130px header.
        return Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: SakuraTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  BloomRankBadge(level: game.level, size: 42, showLabel: false),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Rank name only — the level digit already lives
                        // in the badge core and the cell is too narrow
                        // for 'Name · Lv N' on phones. FittedBox shrinks
                        // the longest rank ('Sakura Bloom') instead of
                        // ellipsising it.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            game.rankName,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: SakuraColors.ink),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(LucideIcons.flame,
                                size: 11, color: SakuraColors.primary),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                '${game.streak}d streak',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: SakuraColors.inkSoft,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: game.levelProgress,
                  minHeight: 6,
                  backgroundColor: SakuraColors.cardBorder,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(SakuraColors.primary),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${game.xpNeeded - game.xpIntoLevel} XP to Level ${game.level + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: SakuraColors.inkSoft,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onBloom,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: SakuraColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.flower,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
