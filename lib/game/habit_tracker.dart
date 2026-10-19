import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';
import '../data/haptics.dart';
import 'bloom_engine.dart';
import 'bloom_game_colors.dart';

// ---------------------------------------------------------------------------
// 1. Data Models (Enhanced with Range, Streak Freeze, and Master Goal Anchor)
// ---------------------------------------------------------------------------

/// Represents a single habit (binary or measurable with optional target range).
class HabitModel {
  final String id;
  final String label;
  final String? subtitle;
  final bool isBinary;

  /// Single target value (used for legacy or simple threshold habits).
  final num targetValue;

  /// Range targets: when [minTarget] and [maxTarget] are defined, the habit
  /// enters the "Success Zone" if [currentValue] falls between them.
  final num? minTarget;
  final num? maxTarget;
  final String unit;

  num currentValue;
  int streakCount;

  /// When true, streak is protected and card enters the frosted Icy Blue state.
  bool isFrozen;

  /// ID of the Master Goal this habit belongs to (e.g. "fitness_phase_1").
  final String? masterGoalId;

  HabitModel({
    required this.id,
    required this.label,
    this.subtitle,
    this.isBinary = true,
    this.targetValue = 1,
    this.minTarget,
    this.maxTarget,
    this.unit = '',
    num? currentValue,
    this.streakCount = 0,
    this.isFrozen = false,
    this.masterGoalId,
  }) : currentValue = currentValue ?? (isBinary ? 0 : 0);

  /// True if this habit defines an elastic range target.
  bool get isRange =>
      minTarget != null && maxTarget != null && minTarget! < maxTarget!;

  num get effectiveMin => minTarget ?? targetValue;
  num get effectiveMax => maxTarget ?? targetValue;

  /// Checks if the habit satisfies the completion condition:
  /// - Binary: currentValue >= 1
  /// - Range: currentValue falls within [minTarget, maxTarget]
  /// - Single target: currentValue >= targetValue
  bool get isInSuccessZone {
    if (isBinary) return currentValue >= 1;
    if (isRange) {
      return currentValue >= minTarget! && currentValue <= maxTarget!;
    }
    return currentValue >= targetValue;
  }

  bool get isCompleted => isInSuccessZone;

  /// Normalized progress towards the maximum target.
  double get progress {
    if (isBinary) return currentValue >= 1 ? 1.0 : 0.0;
    final max = effectiveMax;
    return max <= 0 ? 0.0 : (currentValue / max).clamp(0.0, 1.0).toDouble();
  }

  /// Bonsai growth stage icon based on streak length.
  BloomRank get growthStage {
    if (streakCount >= 15) return BloomRank.sakura;
    if (streakCount >= 8) return BloomRank.lotus;
    if (streakCount >= 4) return BloomRank.bonsai;
    if (streakCount >= 1) return BloomRank.sprout;
    return BloomRank.seedling;
  }

  HabitModel copyWith({
    String? label,
    String? subtitle,
    bool? isBinary,
    num? targetValue,
    num? minTarget,
    num? maxTarget,
    String? unit,
    num? currentValue,
    int? streakCount,
    bool? isFrozen,
    String? masterGoalId,
  }) =>
      HabitModel(
        id: id,
        label: label ?? this.label,
        subtitle: subtitle ?? this.subtitle,
        isBinary: isBinary ?? this.isBinary,
        targetValue: targetValue ?? this.targetValue,
        minTarget: minTarget ?? this.minTarget,
        maxTarget: maxTarget ?? this.maxTarget,
        unit: unit ?? this.unit,
        currentValue: currentValue ?? this.currentValue,
        streakCount: streakCount ?? this.streakCount,
        isFrozen: isFrozen ?? this.isFrozen,
        masterGoalId: masterGoalId ?? this.masterGoalId,
      );
}

// ---------------------------------------------------------------------------
// 2. Bonsai Growth Icon
// ---------------------------------------------------------------------------

enum BonsaiTier { seed, sprout, sapling, bonsai, lotus }

BonsaiTier bonsaiTierForStreak(int streak) {
  if (streak <= 0) return BonsaiTier.seed;
  if (streak < 3) return BonsaiTier.sprout;
  if (streak < 8) return BonsaiTier.sapling;
  if (streak < 15) return BonsaiTier.bonsai;
  return BonsaiTier.lotus;
}

/// Tiny evolving mark: dot -> sprout -> lotus. Icy when frozen.
/// A zero streak rests at the base tier — quiet, never desaturated.
class BonsaiGrowthIcon extends StatelessWidget {
  final int streakCount;
  final double size;
  final bool isFrozen;

  const BonsaiGrowthIcon({
    super.key,
    required this.streakCount,
    this.size = 26,
    this.isFrozen = false,
  });

  @override
  Widget build(BuildContext context) {
    final tier = bonsaiTierForStreak(streakCount);
    final resting = streakCount <= 0 && !isFrozen;
    final accent = isFrozen
        ? BloomGameColors.icyBlue
        : tier == BonsaiTier.lotus
            ? BloomGameColors.bloom
            : tier.index >= BonsaiTier.sapling.index
                ? BloomGameColors.violet
                : SakuraColors.inkSoft;

    return Tooltip(
      message: isFrozen
          ? '$streakCount-day streak · Frozen'
          : resting
              ? 'Resting — start today'
              : '$streakCount-day streak · ${tier.name}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: streakCount.clamp(0, 15) / 15),
        duration: AppMotion.progress,
        curve: AppMotion.progressCurve,
        builder: (context, t, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: isFrozen ? 0.16 : 0.12 + 0.06 * t),
            border: Border.all(
              color: accent.withValues(alpha: isFrozen ? 0.5 : 0.4),
            ),
          ),
          alignment: Alignment.center,
          child: CustomPaint(
            size: Size(size * 0.55, size * 0.55),
            painter: _BonsaiGlyphPainter(tier: tier, color: accent),
          ),
        ),
      ),
    );
  }
}

class _BonsaiGlyphPainter extends CustomPainter {
  final BonsaiTier tier;
  final Color color;

  const _BonsaiGlyphPainter({required this.tier, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    if (tier == BonsaiTier.seed) {
      canvas.drawCircle(c, size.width * 0.14, p);
      return;
    }
    final stem = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width * 0.07);
    canvas.drawLine(
      Offset(c.dx, c.dy + size.height * 0.32),
      Offset(c.dx, c.dy - size.height * (tier == BonsaiTier.sprout ? 0.1 : 0.2)),
      stem,
    );
    if (tier == BonsaiTier.sprout) {
      _leaf(canvas, c + Offset(-size.width * 0.16, 0), -0.6, size, p);
      _leaf(canvas, c + Offset(size.width * 0.16, -size.height * 0.08), 0.6, size, p);
      return;
    }
    if (tier == BonsaiTier.sapling || tier == BonsaiTier.bonsai) {
      _leaf(canvas, c + Offset(-size.width * 0.2, size.height * 0.08), -0.5, size, p);
      _leaf(canvas, c + Offset(size.width * 0.2, 0), 0.5, size, p);
      _leaf(canvas, c + Offset(0, -size.height * 0.22), 0, size, p);
      return;
    }
    for (final dx in [-0.22, 0.0, 0.22]) {
      canvas.drawCircle(
        c + Offset(size.width * dx, -size.height * 0.14),
        size.width * 0.13,
        p,
      );
    }
    canvas.drawCircle(c + Offset(0, size.height * 0.1), size.width * 0.1, p);
  }

  void _leaf(Canvas canvas, Offset at, double tilt, Size size, Paint p) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(tilt);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 0.3,
        height: size.height * 0.16,
      ),
      p,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BonsaiGlyphPainter old) =>
      old.tier != tier || old.color != color;
}

// ---------------------------------------------------------------------------
// 3. Shared Streak Tag & Unfreeze Button
// ---------------------------------------------------------------------------

/// Streak badge: flame icon when active, snowflake when frozen (Lucide
/// glyphs, never emoji — they render unevenly across platforms).
class StreakTag extends StatelessWidget {
  final int streakCount;
  final Color accent;
  final bool isFrozen;

  const StreakTag({
    super.key,
    required this.streakCount,
    required this.accent,
    this.isFrozen = false,
  });

  @override
  Widget build(BuildContext context) {
    // Frozen streaks always show (even at 0) — the tag carries the
    // frozen state. Live streaks keep the original >= 3 rule.
    if (streakCount < 3 && !isFrozen) return const SizedBox.shrink();
    final effectiveAccent = isFrozen ? BloomGameColors.icyBlue : accent;

    // Scale-down shell: the frozen copy ('14 Days (Frozen)') is wide —
    // on narrow cards it shrinks instead of overflowing the title line.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: AppMotion.toggle,
        curve: AppMotion.toggleCurve,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: effectiveAccent.withValues(alpha: isFrozen ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: effectiveAccent.withValues(alpha: isFrozen ? 0.6 : 0.38),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: AppMotion.toggle,
              child: Icon(
                isFrozen ? LucideIcons.snowflake : LucideIcons.flame,
                key: ValueKey(isFrozen),
                size: 10.5,
                color: effectiveAccent,
              ),
            ),
            const SizedBox(width: 3.5),
            Text(
              isFrozen ? '$streakCount Days (Frozen)' : '$streakCount Days',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: effectiveAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimalist frosted pill button for thawing a frozen streak.
class _UnfreezeButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _UnfreezeButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    // Scale-down shell (matches StreakTag): the price copy is wide —
    // on narrow cards it shrinks instead of overflowing its row.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          splashColor: BloomGameColors.icyBlue.withValues(alpha: 0.25),
          highlightColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: BloomGameColors.icyBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: BloomGameColors.icyBlue.withValues(alpha: 0.45),
                width: 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: BloomGameColors.icyBlue.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.diamond,
                    size: 11, color: BloomGameColors.icyBlue),
                SizedBox(width: 5),
                Text(
                  'Unfreeze for 500',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: BloomGameColors.icyBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Shared Habit Shell (Dark Theme with Glow & Frost States)
// ---------------------------------------------------------------------------

class _HabitShell extends StatelessWidget {
  final bool active;
  final bool isFrozen;
  final Color accent;
  final Widget child;

  const _HabitShell({
    required this.active,
    this.isFrozen = false,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = isFrozen ? BloomGameColors.icyBlue : accent;
    final surfaceColor =
        isFrozen ? BloomGameColors.frozenSurface : SakuraColors.surface;

    return AnimatedContainer(
      duration: AppMotion.toggle,
      curve: AppMotion.toggleCurve,
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            if (isFrozen) ...[
              Color.lerp(surfaceColor, BloomGameColors.icyBlue, 0.09)!,
              surfaceColor,
            ] else if (active) ...[
              Color.lerp(SakuraColors.surface, effectiveAccent, 0.12)!,
              SakuraColors.surface,
            ] else ...[
              SakuraColors.surface,
              SakuraColors.surface,
            ],
          ],
        ),
        border: Border.all(
          color: isFrozen
              ? BloomGameColors.icyBlue.withValues(alpha: 0.55)
              : active
                  ? effectiveAccent.withValues(alpha: 0.7)
                  : SakuraColors.cardBorder,
          width: isFrozen || active ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          if (isFrozen)
            BoxShadow(
              color: BloomGameColors.icyBlue.withValues(alpha: 0.22),
              blurRadius: 20,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            )
          else if (active)
            BoxShadow(
              color: effectiveAccent.withValues(alpha: 0.26),
              blurRadius: 22,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: child,
    );
  }
}

class AnimatedSaturation extends StatelessWidget {
  final bool saturated;
  final Widget child;

  const AnimatedSaturation(
      {super.key, required this.saturated, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: saturated ? 0.0 : 1.0, end: saturated ? 1.0 : 0.0),
      duration: AppMotion.toggle,
      curve: AppMotion.toggleCurve,
      builder: (context, v, _) => ColorFiltered(
        colorFilter: ColorFilter.matrix([
          0.2126 + 0.7874 * v, 0.7152 - 0.7152 * v, 0.0722 - 0.0722 * v, 0, 0,
          0.2126 - 0.2126 * v, 0.7152 + 0.2848 * v, 0.0722 - 0.0722 * v, 0, 0,
          0.2126 - 0.2126 * v, 0.7152 - 0.7152 * v, 0.0722 + 0.9278 * v, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. BinaryHabitCard (Yes/No + Streak Freeze Support)
// ---------------------------------------------------------------------------

class BinaryHabitCard extends StatefulWidget {
  final HabitModel? habit;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool isCompleted;
  final ValueChanged<bool> onToggle;
  final int streakCount;
  final bool isFrozen;
  final VoidCallback? onUnfreeze;

  BinaryHabitCard({
    super.key,
    this.habit,
    String? title,
    this.subtitle,
    this.icon,
    bool? isCompleted,
    ValueChanged<bool>? onToggle,
    int? streakCount,
    bool? isFrozen,
    this.onUnfreeze,
  })  : title = title ?? habit?.label ?? '',
        isCompleted = isCompleted ?? habit?.isCompleted ?? false,
        onToggle = onToggle ?? ((_) {}),
        streakCount = streakCount ?? habit?.streakCount ?? 0,
        isFrozen = isFrozen ?? habit?.isFrozen ?? false;

  @override
  State<BinaryHabitCard> createState() => _BinaryHabitCardState();
}

class _BinaryHabitCardState extends State<BinaryHabitCard> {
  int _bounceKey = 0;

  void _fire(bool v) {
    if (v) setState(() => _bounceKey++);
    widget.onToggle(v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.isCompleted;
    final accent = widget.isFrozen
        ? BloomGameColors.icyBlue
        : BloomGameColors.bloom;

    return TweenAnimationBuilder<double>(
      key: ValueKey(_bounceKey),
      tween: Tween(begin: on ? 0.98 : 1.0, end: on ? 1.02 : 1.0),
      duration: AppMotion.bounce,
      curve: AppMotion.bounceCurve,
      builder: (context, s, child) => Transform.scale(
        scale: on ? s : 1.0,
        child: child,
      ),
      child: _HabitShell(
        active: on,
        isFrozen: widget.isFrozen,
        accent: accent,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              AppHaptics.tap();
              _fire(!on);
            },
            splashColor: accent.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BonsaiGrowthIcon(
                        streakCount: widget.streakCount,
                        isFrozen: widget.isFrozen,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Wrap (not Row): on narrow cards the frozen tag
                            // drops below the title instead of overflowing.
                            Wrap(
                              crossAxisAlignment:
                                  WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: SakuraColors.ink,
                                  ),
                                ),
                                StreakTag(
                                  streakCount: widget.streakCount,
                                  accent: accent,
                                  isFrozen: widget.isFrozen,
                                ),
                              ],
                            ),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                widget.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: SakuraColors.inkFaint,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _NeonToggle(
                        value: on,
                        accentColor: accent,
                        onChanged: _fire,
                      ),
                    ],
                  ),
                  if (widget.isFrozen) ...[
                    const SizedBox(height: 12),
                    // Align (not end-Row): bounded width lets the
                    // button's scale-down shell actually engage.
                    Align(
                      alignment: Alignment.centerRight,
                      child: _UnfreezeButton(onTap: widget.onUnfreeze),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeonToggle extends StatelessWidget {
  final bool value;
  final Color accentColor;
  final ValueChanged<bool> onChanged;

  const _NeonToggle({
    required this.value,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AppMotion.toggle,
        curve: AppMotion.toggleCurve,
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: value
              ? accentColor
              : SakuraColors.inkFaint.withValues(alpha: 0.25),
          border: Border.all(
            color: value ? accentColor : SakuraColors.cardBorder,
          ),
          boxShadow: [
            if (value)
              BoxShadow(
                color: accentColor.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: AnimatedAlign(
          duration: AppMotion.bounce,
          curve: AppMotion.bounceCurve,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. MeasurableHabitCard (Range Support, Neon Pink Success Glow & Frozen State)
// ---------------------------------------------------------------------------

/// Measurable habit card with elastic range targets and streak freeze support.
///
/// Features:
/// - Distinct "Success Zone" on circular indicator ([minTarget] .. [maxTarget]).
/// - When user's logged value is in the success zone, ring glows neon pink (`#FF2A55`).
/// - When [isFrozen] is true, card accent shifts to icy blue, the streak
///   icon changes from flame to snowflake, and a small "Unfreeze for
///   500" button appears.
class MeasurableHabitCard extends StatefulWidget {
  final HabitModel? habit;
  final String title;
  final num currentValue;
  final num targetValue;
  final num? minTarget;
  final num? maxTarget;
  final String unit;
  final num step;
  final ValueChanged<num> onProgressChanged;
  final ValueChanged<int>? onIncrement;
  final int incrementStep;
  final int streakCount;
  final IconData? icon;
  final bool isFrozen;
  final VoidCallback? onUnfreeze;

  MeasurableHabitCard({
    super.key,
    this.habit,
    String? title,
    num? currentValue,
    num? targetValue,
    num? minTarget,
    num? maxTarget,
    this.unit = '',
    this.step = 1,
    ValueChanged<num>? onProgressChanged,
    this.onIncrement,
    int? incrementStep,
    int? streakCount,
    this.icon,
    bool? isFrozen,
    this.onUnfreeze,
  })  : title = title ?? habit?.label ?? '',
        currentValue = currentValue ?? habit?.currentValue ?? 0,
        targetValue = targetValue ?? habit?.targetValue ?? 1,
        minTarget = minTarget ?? habit?.minTarget,
        maxTarget = maxTarget ?? habit?.maxTarget,
        onProgressChanged = onProgressChanged ?? ((_) {}),
        incrementStep = incrementStep ?? 1,
        streakCount = streakCount ?? habit?.streakCount ?? 0,
        isFrozen = isFrozen ?? habit?.isFrozen ?? false;

  @override
  State<MeasurableHabitCard> createState() => _MeasurableHabitCardState();
}

class _MeasurableHabitCardState extends State<MeasurableHabitCard> {
  bool _pulsed = false;

  num get _effectiveMin => widget.minTarget ?? widget.targetValue;
  num get _effectiveMax => widget.maxTarget ?? widget.targetValue;
  bool get _isRange =>
      widget.minTarget != null &&
      widget.maxTarget != null &&
      widget.minTarget! < widget.maxTarget!;

  bool get _isInSuccessZone {
    if (_isRange) {
      return widget.currentValue >= _effectiveMin &&
          widget.currentValue <= _effectiveMax;
    }
    return widget.currentValue >= _effectiveMin;
  }

  num get _next {
    final n = widget.currentValue + widget.step;
    return n;
  }

  void _increment() {
    AppHaptics.tap();
    setState(() => _pulsed = true);
    Future.delayed(
      AppMotion.tap,
      () => mounted ? setState(() => _pulsed = false) : null,
    );
    widget.onProgressChanged(_next);
    if (widget.onIncrement != null) {
      widget.onIncrement!(widget.incrementStep);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inSuccess = _isInSuccessZone;

    // Accent: Icy Blue if frozen, Neon Pink (#FF2A55) if in success zone, else Violet.
    final accent = widget.isFrozen
        ? BloomGameColors.icyBlue
        : inSuccess
            ? BloomGameColors.bloom // #FF2A55
            : BloomGameColors.violet;

    String fmt(num v) =>
        v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

    return _HabitShell(
      active: inSuccess,
      isFrozen: widget.isFrozen,
      accent: accent,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v > 120) _increment();
          },
          onTap: _increment,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BonsaiGrowthIcon(
                      streakCount: widget.streakCount,
                      isFrozen: widget.isFrozen,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Wrap (not Row): on narrow cards the tag drops
                          // below the title instead of overflowing.
                          Wrap(
                            crossAxisAlignment:
                                WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: SakuraColors.ink,
                                ),
                              ),
                              StreakTag(
                                streakCount: widget.streakCount,
                                accent: accent,
                                isFrozen: widget.isFrozen,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          if (_isRange) ...[
                            // Range target presentation: e.g. "8 - 10 Glasses".
                            // Wrap (not Row): the target suffix drops below
                            // the value on narrow cards.
                            Wrap(
                              crossAxisAlignment:
                                  WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                Text(
                                  '${fmt(widget.currentValue)} ${widget.unit.isEmpty ? '' : widget.unit}',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: inSuccess && !widget.isFrozen
                                        ? BloomGameColors.bloom // #FF2A55
                                        : SakuraColors.ink,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                Text(
                                  '· target ${fmt(_effectiveMin)}–${fmt(_effectiveMax)}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: SakuraColors.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.sparkles,
                                  size: 11,
                                  color: inSuccess && !widget.isFrozen
                                      ? BloomGameColors.bloom
                                      : SakuraColors.inkSoft,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    inSuccess
                                        ? 'In Success Zone'
                                        : widget.currentValue < _effectiveMin
                                            ? '${fmt(_effectiveMin - widget.currentValue)} more to zone'
                                            : '${fmt(widget.currentValue - _effectiveMax)} past range',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: inSuccess && !widget.isFrozen
                                          ? BloomGameColors.bloom
                                          : SakuraColors.inkSoft,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            // Single target presentation
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: fmt(widget.currentValue),
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: inSuccess && !widget.isFrozen
                                          ? BloomGameColors.bloom
                                          : SakuraColors.ink,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        ' / ${fmt(_effectiveMax)}${widget.unit.isEmpty ? '' : ' ${widget.unit}'}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: SakuraColors.inkFaint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    AnimatedScale(
                      scale: _pulsed ? 1.12 : 1.0,
                      duration: AppMotion.tap,
                      curve: AppMotion.tapCurve,
                      child: _SuccessZoneRing(
                        currentValue: widget.currentValue,
                        minTarget: _effectiveMin,
                        maxTarget: _effectiveMax,
                        isRange: _isRange,
                        inSuccessZone: inSuccess,
                        isFrozen: widget.isFrozen,
                      ),
                    ),
                  ],
                ),
                if (widget.isFrozen) ...[
                  const SizedBox(height: 12),
                  // Align (not end-Row): bounded width lets the
                  // button's scale-down shell actually engage.
                  Align(
                    alignment: Alignment.centerRight,
                    child: _UnfreezeButton(onTap: widget.onUnfreeze),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Circular Indicator with Success Zone Arc & Neon Pink (#FF2A55) Glow
// ---------------------------------------------------------------------------

class _SuccessZoneRing extends StatelessWidget {
  final num currentValue;
  final num minTarget;
  final num maxTarget;
  final bool isRange;
  final bool inSuccessZone;
  final bool isFrozen;

  const _SuccessZoneRing({
    required this.currentValue,
    required this.minTarget,
    required this.maxTarget,
    required this.isRange,
    required this.inSuccessZone,
    required this.isFrozen,
  });

  @override
  Widget build(BuildContext context) {
    const size = 48.0;

    // Scale calculation: if range, display track represents 115% of maxTarget
    // so the success zone has an entry and exit segment.
    final displayMax = isRange
        ? (maxTarget > 0 ? (maxTarget * 1.15).toDouble() : 1.0)
        : (maxTarget > 0 ? maxTarget.toDouble() : 1.0);

    final currentFrac = (currentValue / displayMax).clamp(0.0, 1.0).toDouble();
    final minZoneFrac = isRange
        ? (minTarget / displayMax).clamp(0.0, 1.0).toDouble()
        : 1.0;
    final maxZoneFrac = isRange
        ? (maxTarget / displayMax).clamp(0.0, 1.0).toDouble()
        : 1.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: currentFrac),
      duration: AppMotion.progress,
      curve: AppMotion.progressCurve,
      builder: (context, animatedProgress, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(size, size),
              painter: _RangeRingPainter(
                currentProgress: animatedProgress,
                minZoneProgress: minZoneFrac,
                maxZoneProgress: maxZoneFrac,
                isRange: isRange,
                inSuccessZone: inSuccessZone,
                isFrozen: isFrozen,
                trackColor: SakuraColors.cardBorder.withValues(alpha: 0.6),
                neonPinkGlow: BloomGameColors.bloom, // #FF2A55
                icyBlue: BloomGameColors.icyBlue,
              ),
            ),
            AnimatedSwitcher(
              duration: AppMotion.toggle,
              transitionBuilder: (c, a) =>
                  ScaleTransition(scale: a, child: c),
              child: Icon(
                isFrozen
                    ? Icons.ac_unit_rounded
                    : inSuccessZone
                        ? Icons.check_rounded
                        : Icons.add_rounded,
                key: ValueKey(isFrozen ? 'f' : inSuccessZone ? 's' : 'a'),
                size: 20,
                color: isFrozen
                    ? BloomGameColors.icyBlue
                    : inSuccessZone
                        ? BloomGameColors.bloom // #FF2A55
                        : SakuraColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeRingPainter extends CustomPainter {
  final double currentProgress;
  final double minZoneProgress;
  final double maxZoneProgress;
  final bool isRange;
  final bool inSuccessZone;
  final bool isFrozen;
  final Color trackColor;
  final Color neonPinkGlow;
  final Color icyBlue;

  const _RangeRingPainter({
    required this.currentProgress,
    required this.minZoneProgress,
    required this.maxZoneProgress,
    required this.isRange,
    required this.inSuccessZone,
    required this.isFrozen,
    required this.trackColor,
    required this.neonPinkGlow,
    required this.icyBlue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.4;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Full base track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // 2. Distinct "Success Zone" indicator on the track
    if (isRange && maxZoneProgress > minZoneProgress) {
      final startAngle = -math.pi / 2 + (2 * math.pi * minZoneProgress);
      final sweepAngle = 2 * math.pi * (maxZoneProgress - minZoneProgress);

      final zonePaint = Paint()
        ..color = (inSuccessZone && !isFrozen
                ? neonPinkGlow
                : BloomGameColors.violet)
            .withValues(alpha: inSuccessZone ? 0.35 : 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweepAngle, false, zonePaint);

      // Subtle zone bounding ticks
      final tickPaint = Paint()
        ..color = (inSuccessZone && !isFrozen ? neonPinkGlow : SakuraColors.inkFaint)
            .withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      _drawTick(canvas, center, radius, startAngle, tickPaint);
      _drawTick(canvas, center, radius, startAngle + sweepAngle, tickPaint);
    }

    // 3. User's active progress arc
    if (currentProgress > 0) {
      final progressSweep = 2 * math.pi * currentProgress.clamp(0.0, 1.0);

      // Glowing Neon Pink (#FF2A55) bloom effect when in the success zone
      if (inSuccessZone && !isFrozen) {
        final glowPaint = Paint()
          ..color = neonPinkGlow.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 5.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0)
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(rect, -math.pi / 2, progressSweep, false, glowPaint);
      } else if (isFrozen) {
        final icyGlowPaint = Paint()
          ..color = icyBlue.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 4.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(rect, -math.pi / 2, progressSweep, false, icyGlowPaint);
      }

      // Crisp active arc
      final activePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      if (isFrozen) {
        activePaint.color = icyBlue;
      } else if (inSuccessZone) {
        activePaint.color = neonPinkGlow; // Glows Neon Pink #FF2A55
      } else {
        activePaint.shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [BloomGameColors.violet, BloomGameColors.bloom],
        ).createShader(rect);
      }

      canvas.drawArc(rect, -math.pi / 2, progressSweep, false, activePaint);
    }
  }

  void _drawTick(
      Canvas canvas, Offset center, double radius, double angle, Paint paint) {
    const tickLen = 3.5;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final inner = Offset(
        center.dx + (radius - tickLen) * cosA, center.dy + (radius - tickLen) * sinA);
    final outer = Offset(
        center.dx + (radius + tickLen) * cosA, center.dy + (radius + tickLen) * sinA);
    canvas.drawLine(inner, outer, paint);
  }

  @override
  bool shouldRepaint(covariant _RangeRingPainter old) =>
      old.currentProgress != currentProgress ||
      old.minZoneProgress != minZoneProgress ||
      old.maxZoneProgress != maxZoneProgress ||
      old.inSuccessZone != inSuccessZone ||
      old.isFrozen != isFrozen ||
      old.trackColor != trackColor;
}

// ---------------------------------------------------------------------------
// 8. GoalAnchoredHabitGroup Widget (Master Goal Container & Slow Increment)
// ---------------------------------------------------------------------------

/// Visual container grouping daily habits under a long-term "Master Goal".
///
/// Features:
/// - Prominent Master Goal header (Title, Tagline, Category badge).
/// - Slow-moving Master Progress bar at the top with ambient glow.
/// - When all child habits are checked off for the day, the master bar gracefully
///   increments using [TweenAnimationBuilder] with an ease-out curve.
/// - Strictly minimalist dark mode aesthetic with frosted border and micro-animations.
class GoalAnchoredHabitGroup extends StatelessWidget {
  /// Name of the Master Goal (e.g. "Fitness Phase 1", "Morning Zen Ritual").
  final String title;

  /// Optional inspirational tagline or long-term timeframe (e.g. "30-Day Ritual Arc").
  final String? subtitle;

  /// Goal Category tag (e.g. "PHYSICAL VITALITY", "DEEP WORK").
  final String? category;

  /// Distinctive icon for the Master Goal.
  final IconData? icon;

  /// Base long-term progress value between 0.0 and 1.0 (e.g. 0.45 = 45% of 30 days).
  final double masterProgress;

  /// Graceful increment added when all child habits are completed today (default: +2.5%).
  final double dailyBonusIncrement;

  /// True when all child habits inside this group are completed today.
  final bool allHabitsCompletedToday;

  /// Number of completed habits today.
  final int completedCount;

  /// Total number of habits under this goal.
  final int totalCount;

  /// List of habit cards (e.g. [MeasurableHabitCard] or [BinaryHabitCard]).
  final List<Widget> children;

  /// Optional tap handler for viewing master goal details/milestones.
  final VoidCallback? onMasterGoalTap;

  /// Accent color for the Master Goal (defaults to signature Bloom pink #FF2A55).
  final Color? accentColor;

  const GoalAnchoredHabitGroup({
    super.key,
    required this.title,
    this.subtitle,
    this.category,
    this.icon,
    required this.masterProgress,
    this.dailyBonusIncrement = 0.025,
    required this.allHabitsCompletedToday,
    this.completedCount = 0,
    this.totalCount = 0,
    required this.children,
    this.onMasterGoalTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? BloomGameColors.bloom;

    // Target master progress: smoothly steps forward when all habits are complete today
    final targetProgress = (allHabitsCompletedToday
            ? (masterProgress + dailyBonusIncrement)
            : masterProgress)
        .clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: AppMotion.toggle,
      curve: AppMotion.toggleCurve,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: BloomGameColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: allHabitsCompletedToday
              ? effectiveAccent.withValues(alpha: 0.45)
              : BloomGameColors.cardBorder,
          width: allHabitsCompletedToday ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          if (allHabitsCompletedToday)
            BoxShadow(
              color: effectiveAccent.withValues(alpha: 0.16),
              blurRadius: 28,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------------------------------------------------------------
          // Master Goal Header & Slow-Moving Master Progress Bar
          // ---------------------------------------------------------------
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            onTap: onMasterGoalTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Goal Icon Glyph Badge
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: effectiveAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: effectiveAccent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Icon(
                          icon ?? Icons.flag_rounded,
                          size: 20,
                          color: effectiveAccent,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category != null) ...[
                              Text(
                                category!.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                  color: effectiveAccent,
                                ),
                              ),
                              const SizedBox(height: 2),
                            ],
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: SakuraColors.ink,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: SakuraColors.inkSoft,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Daily Status Pill
                      AnimatedContainer(
                        duration: AppMotion.toggle,
                        curve: AppMotion.toggleCurve,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: allHabitsCompletedToday
                              ? effectiveAccent.withValues(alpha: 0.18)
                              : BloomGameColors.locked.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: allHabitsCompletedToday
                                ? effectiveAccent.withValues(alpha: 0.5)
                                : BloomGameColors.cardBorder,
                            width: 0.9,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (allHabitsCompletedToday) ...[
                              Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: effectiveAccent,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              allHabitsCompletedToday
                                  ? 'Done Today'
                                  : '$completedCount/$totalCount Done',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: allHabitsCompletedToday
                                    ? effectiveAccent
                                    : SakuraColors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // -----------------------------------------------------------
                  // Master Goal Progress Bar with TweenAnimationBuilder
                  // -----------------------------------------------------------
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: masterProgress,
                      end: targetProgress,
                    ),
                    duration: AppMotion.counter,
                    curve: AppMotion.counterCurve,
                    builder: (context, animValue, _) {
                      final pct = (animValue * 100).toInt();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'MASTER GOAL PROGRESS',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                  color: SakuraColors.inkFaint,
                                ),
                              ),
                              Row(
                                children: [
                                  if (allHabitsCompletedToday)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Text(
                                        '+${(dailyBonusIncrement * 100).toStringAsFixed(1)}% today',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: effectiveAccent,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    '$pct%',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: SakuraColors.ink,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Stack(
                              children: [
                                // Background track
                                Container(
                                  height: 7,
                                  width: double.infinity,
                                  color: SakuraColors.cardBorder.withValues(alpha: 0.5),
                                ),
                                // Animated glowing progress bar
                                FractionallySizedBox(
                                  widthFactor: animValue.clamp(0.0, 1.0),
                                  child: Container(
                                    height: 7,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          BloomGameColors.violet,
                                          effectiveAccent,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: effectiveAccent.withValues(alpha: 0.55),
                                          blurRadius: 8,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Subtle divider line
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: SakuraColors.cardBorder.withValues(alpha: 0.4),
          ),

          // ---------------------------------------------------------------
          // Child Habits List
          // ---------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
