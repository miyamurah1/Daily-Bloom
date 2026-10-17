import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/weekly_review.dart';
import '../theme/sakura_theme.dart';

/// Shareable week card: the review's headline numbers on a themed
/// canvas, rendered off-screen into a PNG via [RepaintBoundary].
/// The centrepiece is a *week-bloom* — seven petals (Mon→Sun) whose
/// openness and saturation track that day's completions. Purely
/// presentational; capture + system share live with the caller.
class ShareCard extends StatelessWidget {
  final WeeklyReview review;

  /// Logical render size (portrait card). Captured at 3x for crispness.
  static const Size canvasSize = Size(360, 470);
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
          const SizedBox(height: 14),
          // The flower: one petal per weekday, open = productive.
          SizedBox(
            width: double.infinity,
            height: 152,
            child: CustomPaint(
              painter: _WeekBloom(daily: r.dailyCounts, total: r.doneCount),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _num('${r.doneCount}', 'DONE'),
              _num('${r.focusMinutes}m', 'FOCUS'),
              _num('${r.activeDays}', 'ACTIVE DAYS'),
            ],
          ),
          const SizedBox(height: 12),
          // Second data row — the stories behind the numbers.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (r.bestDay != null && r.bestDayCount > 0)
                _chip('★ best day ${r.bestDay} ×${r.bestDayCount}'),
              if (r.habitsTotal > 0)
                _chip('habits ${r.habitsKept}/${r.habitsTotal}'),
              if (r.topTag != null && r.topTag!.isNotEmpty)
                _chip(r.topTag!),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              r.verdict,
              maxLines: 4,
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
                        ? '${r.streakCurrent}-day streak · Daily Bloom'
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

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SakuraColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SakuraColors.cardBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: SakuraColors.inkSoft,
        ),
      ),
    );
  }
}

/// Seven-petal week bloom: petal i = weekday i (Mon→Sun). Quiet days
/// stay as small ghost petals; productive days open wide and saturated.
/// Painter-only (no widget tree) — the whole flower costs one canvas.
class _WeekBloom extends CustomPainter {
  final List<int> daily;
  final int total;

  _WeekBloom({required this.daily, required this.total});

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 4);
    const ring = 40.0;
    final maxV = daily.isEmpty ? 0 : daily.reduce(math.max);
    for (var i = 0; i < 7; i++) {
      final n = i < daily.length ? daily[i] : 0;
      final t = maxV > 0 ? n / maxV : 0.0;
      final angle = -math.pi / 2 + i * 2 * math.pi / 7;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + math.pi / 2);
      final petal = Paint()
        ..color = SakuraColors.primary
            .withValues(alpha: n == 0 ? 0.12 : 0.40 + 0.50 * t);
      final grow = n == 0 ? 0.72 : 0.78 + 0.34 * t;
      canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(0, -ring),
            width: 27 * grow,
            height: 40 * grow),
        petal,
      );
      canvas.restore();
      // Day letter just outside the petal tip.
      final lp =
          center + Offset(math.cos(angle), math.sin(angle)) * (ring + 27);
      _word(
          canvas,
          _letters[i],
          lp,
          n > 0
              ? SakuraColors.inkFaint
              : SakuraColors.inkFaint.withValues(alpha: 0.45),
          10);
    }
    // Centre disc: the week's total, like the flower's heart.
    canvas.drawCircle(center, 21, Paint()..color = SakuraColors.surface);
    canvas.drawCircle(
        center,
        21,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = SakuraColors.cardBorder);
    _word(canvas, '$total', center, SakuraColors.primary, 17,
        weight: FontWeight.w800);
  }

  void _word(Canvas canvas, String text, Offset at, Color color,
      double fontSize,
      {FontWeight weight = FontWeight.w700}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: fontSize, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_WeekBloom old) =>
      old.total != total ||
      old.daily.length != daily.length ||
      !List.generate(daily.length, (i) => old.daily[i] == daily[i])
          .every((same) => same);
}
