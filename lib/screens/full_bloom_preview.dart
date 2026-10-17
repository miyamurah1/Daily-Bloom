import 'package:flutter/material.dart';

import '../game/game.dart';
import '../theme/sakura_theme.dart';

/// Full Bloom showcase with two modes:
///
/// - DEMO: mocked max state (Lv 100 Sakura, x5 flow, 5/5 season,
///   12-day streak with petals, critical 250). Nothing is saved.
/// - MY LEVEL: your live profile, same layout — so you can compare.
///
/// "MAX MY PROFILE" writes Lv 100 + x5 combo + 12d streak into the real
/// singleton (local only, no server writes), so Home itself renders
/// Full Bloom everywhere. "Reset" goes back to a fresh Seedling.
///
/// Open from Home → `FULL BLOOM PREVIEW →`. Flip the store theme
/// (Edo / Midnight / Kyoto / Ocean) to see every widget re-skin live —
/// surfaces, ink, and borders follow `SakuraColors`, accents stay
/// signature pink → violet → gold.
class FullBloomPreview extends StatefulWidget {
  const FullBloomPreview({super.key});

  @override
  State<FullBloomPreview> createState() => _FullBloomPreviewState();
}

class _FullBloomPreviewState extends State<FullBloomPreview> {
  bool _live = false;
  int _replayNonce = 0;

  static const _milestones = [
    SeasonMilestone(title: 'First light', reward: '+50 XP'),
    SeasonMilestone(title: 'Seven dawns', reward: '◆ 50'),
    SeasonMilestone(title: 'Still water', reward: '+150 XP'),
    SeasonMilestone(title: 'Deep roots', reward: '◆ 150'),
    SeasonMilestone(title: 'Full bloom', reward: 'Sakura'),
  ];

  void _showCritical(BuildContext context) {
    MysteryBloomOverlay.show(
      context,
      reward: const MysteryReward(250, isCritical: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ThemeStore.instance,
        GamificationStateNotifier.instance,
      ]),
      builder: (context, _) {
        final game = GamificationStateNotifier.instance;
        // Demo values vs live profile values.
        final level = _live ? game.level : 100;
        final progress = _live ? game.levelProgress : 1.0;
        final xpLine = _live
            ? '${game.xpIntoLevel}/${game.xpNeeded} XP · ◆ ${game.tokens} · ${game.streak}d streak'
            : 'MAX · ◆ 12,480 · 12d streak';
        final rankLine = _live
            ? '${game.rankName} · Lv ${game.level}'
            : 'Sakura Bloom · Lv 100';
        final combo = _live ? game.comboCount : 5;
        final seasonDone =
            _live ? (game.totalXp ~/ 200).clamp(0, 5) : 5;
        final streak = _live ? game.streak : 12;
        final counterTarget = _live ? game.tokens : 250;

        return DynamicBloomBackground(
          streak: streak,
          child: Scaffold(
            backgroundColor: SakuraColors.background,
            appBar: AppBar(
              backgroundColor: SakuraColors.background,
              elevation: 0,
              leading: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Semantics(
                  button: true,
                  label: 'Back',
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SakuraColors.surface,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: SakuraColors.cardBorder),
                    ),
                    child: Icon(Icons.arrow_back,
                        size: 18, color: SakuraColors.ink),
                  ),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '満開',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: SakuraColors.primary,
                      letterSpacing: 4,
                    ),
                  ),
                  Text(
                    _live
                        ? 'FULL BLOOM · MY LEVEL'
                        : 'FULL BLOOM · LV 100 DEMO',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                // Demo ↔ live toggle.
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false, label: Text('Demo')),
                      ButtonSegment(
                          value: true, label: Text('My Lv')),
                    ],
                    selected: {_live},
                    onSelectionChanged: (s) =>
                        setState(() => _live = s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  // 1 — Rank: 5-ring Sakura at max, live badge otherwise.
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration:
                        SakuraTheme.cardDecoration(),
                    child: Row(
                      children: [
                        BloomRankBadge(
                            level: level, size: 84),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                rankLine,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: SakuraColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _live
                                    ? '桜 — your real profile'
                                    : '桜 — five rings, violet shimmer',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      SakuraColors.inkSoft,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(6),
                                child:
                                    LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 7,
                                  backgroundColor: SakuraColors
                                      .primarySoft,
                                  valueColor:
                                      const AlwaysStoppedAnimation<
                                              Color>(
                                          BloomGameColors
                                              .violet),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                xpLine,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      SakuraColors.inkSoft,
                                  fontFeatures: const [
                                    FontFeature
                                        .tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Max-out / reset actions (local only).
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                SakuraColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            GamificationStateNotifier
                                .instance
                                .debugFullBloom();
                            setState(
                                () => _live = true);
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Maxed to Lv 100 — Home shows Full Bloom now.')),
                            );
                          },
                          child: const Text(
                              'Max my profile',
                              style: TextStyle(
                                  fontWeight:
                                      FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            GamificationStateNotifier
                                .instance
                                .debugReset();
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Reset to Seedling Lv 1.')),
                            );
                          },
                          child: const Text('Reset'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 2 — Combo heat.
                  Text(
                    'FLOW x$combo — ${combo >= 3 ? 'VIOLET HEAT' : 'WARMING UP'}',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FlowStateJuiceWidget(
                    comboLevel: combo,
                    gainLabel: (c) => '+50 XP · x$c',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration:
                          SakuraTheme.cardDecoration(),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: SakuraColors.primary,
                              borderRadius:
                                  BorderRadius.circular(
                                      12),
                            ),
                            child: const Icon(Icons.check,
                                size: 19,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Morning pages',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight:
                                        FontWeight.w700,
                                    color: SakuraColors.ink,
                                  ),
                                ),
                                Text(
                                  combo >= 3
                                      ? 'Done · $combo-task chain today'
                                      : 'Done · keep chaining inside 15 min',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: SakuraColors
                                        .inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '+50',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: SakuraColors.primary,
                              fontFeatures: const [
                                FontFeature
                                    .tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 3 — Season (capped on desktop like Home).
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final section = Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'SEASON — $seasonDone / 5 COMPLETE',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 2.2,
                              fontWeight: FontWeight.w600,
                              color: SakuraColors.inkFaint,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration:
                                SakuraTheme.cardDecoration(),
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 6),
                            child: SeasonalJourneyTrack(
                              milestones: _milestones,
                              completedCount: seasonDone,
                            ),
                          ),
                        ],
                      );
                      if (constraints.maxWidth < 760) {
                        return section;
                      }
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxWidth: 680),
                          child: section,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // 4 — Reward counter.
                  Text(
                    _live
                        ? 'MY TOKENS — ◆$counterTarget'
                        : 'CRITICAL BLOOM — ◆250',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                      color: SakuraColors.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration:
                        SakuraTheme.cardDecoration(),
                    child: Column(
                      children: [
                        // Replayable bloom moment: lotus unfolds (900ms)
                        // while the counter rolls (1.5s). Tap the lotus
                        // for the full dialog. Key bump restarts both.
                        GestureDetector(
                          onTap: () =>
                              _showCritical(context),
                          behavior: HitTestBehavior.opaque,
                          child: TweenAnimationBuilder<
                              double>(
                            key: ValueKey<int>(
                                _replayNonce),
                            tween: Tween<double>(
                                begin: 0, end: 1),
                            duration: const Duration(
                                milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) =>
                                BloomingLotus(
                              progress: v,
                              isCritical: true,
                              size: 120,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        RollingTokenCounter(
                          key: ValueKey<String>(
                              'counter-$_replayNonce'),
                          target: counterTarget,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => setState(() =>
                                _replayNonce++),
                            child: const Text(
                                'Replay unfolding lotus'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Clearance so the last card never hides behind the FAB.
                  const SizedBox(height: 72),
                ],
              ),
            ),
            floatingActionButton:
                FloatingActionButton.extended(
              backgroundColor: SakuraColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _showCritical(context),
              icon: const Icon(Icons.spa, size: 18),
              label: const Text('Bloom drop',
                  style:
                      TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        );
      },
    );
  }
}
