import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../data/api_client.dart';
import '../data/mock_data.dart';
import '../theme/sakura_theme.dart';

/// GitHub-style contribution grid.
///
/// Columns are weeks (oldest left), rows are the 7 days — so month
/// labels sit on top, the newest day is bottom-right, and tapping a
/// cell reports its date + count. Today gets a crimson outline.
class ContributionHeatmap extends StatelessWidget {
  final List<HeatDay> days;
  final String bestStreakLabel;

  const ContributionHeatmap({
    super.key,
    required this.days,
    this.bestStreakLabel = 'Best streak: —',
  });

  /// Cell copy shown by the tap-tooltip: date, completed count and
  /// intensity. Built here so the grid stays free of snackbar queues.
  String _dayMessage(HeatDay d) {
    final fmt = DateFormat('EEE, MMM d');
    final date = fmt.format(d.date);
    final intensity = d.count >= 5
        ? 'Peak day'
        : d.count >= 3
            ? 'Deep day'
            : d.count >= 1
                ? 'Warming up'
                : 'Quiet day';
    return d.count == 0
        ? '$date\nNo tasks · $intensity'
        : '$date\n${d.count} task${d.count == 1 ? '' : 's'} · $intensity';
  }

  /// Five-step intensity swatch (heat0 → heat4) for the legend.
  Color _heatScaleColor(int i) {
    switch (i) {
      case 1:
        return SakuraColors.heat1;
      case 2:
        return SakuraColors.heat2;
      case 3:
        return SakuraColors.heat3;
      case 4:
        return SakuraColors.heat4;
      case 0:
      default:
        return SakuraColors.heat0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weeks = days.isEmpty ? 12 : (days.length / 7).ceil();
    final monthFmt = DateFormat('MMM');

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: SakuraTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A quiet year, waiting',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: SakuraColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Every square is one day — finish something to paint it.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: SakuraColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 4.0;
              // Fixed-size cells, left-aligned like GitHub — never
              // stretched. Leftover width on wide screens stays empty.
              final cell =
                  (constraints.maxWidth - gap * (weeks - 1)) / weeks;
              final size = cell.clamp(8.0, 20.0);
              String? curMonth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(weeks, (w) {
                      final idx = w * 7;
                      final label = idx < days.length
                          ? monthFmt.format(days[idx].date)
                          : '';
                      final show =
                          label.isNotEmpty && label != curMonth;
                      if (show) curMonth = label;
                      return Container(
                        width: size,
                        margin: EdgeInsets.only(
                            right: w == weeks - 1 ? 0 : gap),
                        child: Text(
                          show ? label : '',
                          style: TextStyle(
                            fontSize: 10,
                            color: SakuraColors.inkFaint,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(weeks, (w) {
                      // One repaint boundary per week column: a theme or
                      // streak tick repaints 12 boxes, not 84 cells.
                      return RepaintBoundary(
                        child: Container(
                        margin: EdgeInsets.only(
                            right: w == weeks - 1 ? 0 : gap),
                        child: Column(
                          children: List.generate(7, (d) {
                            final idx = w * 7 + d;
                            final day = idx < days.length
                                ? days[idx]
                                : HeatDay(
                                    date: now.subtract(Duration(
                                        days: days.length - idx)),
                                  );
                            final isToday = day.date.year ==
                                    now.year &&
                                day.date.month == now.month &&
                                day.date.day == now.day;
                            return Tooltip(
                              // Native in-place popover instead of a queued
                              // SnackBar. Default trigger keeps desktop hover
                              // AND touch long-press; excludeFromSemantics is
                              // false so TalkBack reads the same message.
                              message: _dayMessage(day),
                              showDuration: const Duration(seconds: 3),
                              waitDuration: Duration.zero,
                              preferBelow: false,
                              child: Semantics(
                                label: _dayMessage(day),
                                child: Container(
                                width: size,
                                height: size,
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  color: heatColorFor(day.level),
                                  borderRadius: BorderRadius.circular(
                                      size * 0.28),
                                  border: isToday
                                      ? Border.all(
                                          color:
                                              SakuraColors.primary,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                ),
                              ),
                            );
                          }),
                        ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                LucideIcons.flame,
                size: 14,
                color: SakuraColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bestStreakLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: SakuraColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Legend for the intensity scale (heat0 quiet → heat4 peak),
          // right-aligned so it reads as a scale key under the grid.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Less',
                  style: TextStyle(
                      fontSize: 10, color: SakuraColors.inkFaint)),
              const SizedBox(width: 6),
              ...List.generate(
                5,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Semantics(
                    label: 'Intensity $i of 4',
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _heatScaleColor(i),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Text('More',
                  style: TextStyle(
                      fontSize: 10, color: SakuraColors.inkFaint)),
            ],
          ),
        ],
      ),
    );
  }
}
