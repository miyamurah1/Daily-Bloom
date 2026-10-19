import 'package:flutter/material.dart';

import '../theme/sakura_theme.dart';
import 'bloom_engine.dart';
import 'bloom_game_colors.dart';

/// Minimalist circular rank badge with a faint, slowly rotating
/// gradient border. Intricacy (arcs) grows with rank:
///
/// Seedling 1 ring → Sprout 2 → Bonsai 3 → Lotus 4 → Sakura 5.
///
/// The badge is always full-color: it never dims or desaturates. A
/// quiet garden is a resting garden, not a punished one.
///
/// ```dart
/// BloomRankBadge(level: game.level, size: 76)
/// ```
class BloomRankBadge extends StatefulWidget {
  final int level;
  final double size;

  /// When false, renders only the ring core (no rank-name caption) —
  /// used by the compact Bento header cell where vertical room is tight.
  final bool showLabel;

  const BloomRankBadge({
    super.key,
    required this.level,
    this.size = 72,
    this.showLabel = true,
  });

  @override
  State<BloomRankBadge> createState() => _BloomRankBadgeState();
}

class _BloomRankBadgeState extends State<BloomRankBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    // One slow revolution — calm, not spinner-like. Pauses automatically
    // when this tab is offscreen (AppShell wraps pages in TickerMode).
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced-motion: hold the ring still.
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rank = BloomEngine.rankForLevel(widget.level);
    final intricacy = BloomEngine.rankIntricacy(rank);
    final accent = BloomGameColors.rankAccents[rank.index];
    final s = widget.size;

    return SizedBox(
      // +20 width / +26 height: long labels ("SAKURA BLOOM") scale down
      // via FittedBox instead of wrapping into an overflow. The label row
      // is dropped entirely in compact mode.
      width: s + 20,
      height: widget.showLabel ? s + 26 : s,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: s,
            height: s,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => CustomPaint(
                painter: _RankRingPainter(
                  rotation: _spin.value * 2 * 3.1415926535,
                  arcs: intricacy,
                  accent: accent,
                  isSakura: rank == BloomRank.sakura,
                ),
                child: Center(
                  child: Container(
                    width: s - 14,
                    height: s - 14,
                    decoration: BoxDecoration(
                      // Theme-aware core — light Edo or dark Midnight.
                      color: SakuraColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: SakuraColors.cardBorder, width: 1),
                    ),
                    // FittedBox keeps the kanji + level glyphs from
                    // overflowing at small sizes.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            BloomEngine.rankKanji(rank),
                            style: TextStyle(
                              fontSize: s * 0.24,
                              fontWeight: FontWeight.w400,
                              color: accent,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.level}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: SakuraColors.ink,
                              height: 1.0,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showLabel) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: s + 20,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  BloomEngine.rankName(rank).toUpperCase(),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 8.5,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: SakuraColors.inkFaint,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Faint rotating arcs: [arcs] 1..5 evenly spaced, thin (2px),
/// low alpha so it reads as shimmer, not chrome.
///
/// Perf: solid strokes (no per-frame SweepGradient shader compile),
/// wrapped in a RepaintBoundary by the caller.
class _RankRingPainter extends CustomPainter {
  final double rotation;
  final int arcs;
  final Color accent;
  final bool isSakura;

  _RankRingPainter({
    required this.rotation,
    required this.arcs,
    required this.accent,
    required this.isSakura,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 3;

    for (var i = 0; i < arcs; i++) {
      final start = rotation + i * (2 * 3.1415926535 / arcs);
      // Higher ranks sweep longer arcs with smaller gaps.
      final sweep = (2 * 3.1415926535 / arcs) * (0.55 + i * 0.06);
      final baseAlpha = i == arcs - 1 ? 0.55 : 0.30;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = (isSakura && i == arcs - 1 ? BloomGameColors.bloom : accent)
            .withValues(alpha: baseAlpha);
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RankRingPainter old) =>
      old.rotation != rotation ||
      old.arcs != arcs ||
      old.accent != accent ||
      old.isSakura != isSakura;
}
