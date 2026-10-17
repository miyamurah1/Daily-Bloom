import 'package:flutter/material.dart';

import '../data/weekly_review.dart';
import '../theme/sakura_theme.dart';

/// Shareable week card: the review's headline numbers on a themed
/// canvas, rendered off-screen into a PNG via [RepaintBoundary].
/// Pure presentational — takes a [WeeklyReview], paints it, done.
/// Capture + system share live with the caller (review screen), which
/// owns the boundary key and the Clipboard fallback.
class ShareCard extends StatelessWidget {
  final WeeklyReview review;

  /// Logical render size (4:5 portrait). Captured at 3x for crispness.
  static const Size canvasSize = Size(360, 450);
  static const double capturePixelRatio = 3.0;

  const ShareCard({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final r = review;
    return Container(
      width: canvasSize.width,
      height: canvasSize.height,
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
      decoration: BoxDecoration(
        color: SakuraColors.background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: SakuraColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '週',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: SakuraColors.primary,
                  letterSpacing: 3.2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MY WEEK IN BLOOM',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 3.2,
                        fontWeight: FontWeight.w600,
                        color: SakuraColors.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reviewWeekLabel(r.weekStart).toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: SakuraColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _num('${r.doneCount}', 'DONE'),
              _num('${r.focusMinutes}m', 'FOCUS'),
              _num('${r.activeDays}', 'ACTIVE DAYS'),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Text(
              r.verdict,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: SakuraColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: SakuraColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SakuraColors.cardBorder),
            ),
            child: Row(
              children: [
                Text(
                  '日常',
                  style: SakuraTheme.display(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: SakuraColors.primary,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.streakCurrent > 0
                        ? '${r.streakCurrent}-day streak'
                        : 'Daily Bloom',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SakuraColors.ink,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: SakuraColors.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
            color: SakuraColors.inkFaint,
          ),
        ),
      ],
    );
  }
}
