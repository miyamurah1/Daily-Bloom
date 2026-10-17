import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/haptics.dart';
import '../game/gamification_state.dart';
import '../theme/app_motion.dart';
import '../theme/sakura_theme.dart';

/// Level-up reward moment — a one-shot petal burst.
///
/// Shows once when XP crosses a level (wired in Home's `_complete`).
/// Perf-safe: single 900ms controller, static CustomPaint petals
/// (no per-frame BoxShadow blur), transparent barrier (no saveLayer).
class LevelUpBurst extends StatefulWidget {
  final int newLevel;
  final String rankName;

  const LevelUpBurst({super.key, required this.newLevel, required this.rankName});

  /// Fire-and-forget — safe to call during a build (posts a frame).
  static void show(BuildContext context,
      {required int newLevel, required String rankName}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black38,
        builder: (_) => LevelUpBurst(newLevel: newLevel, rankName: rankName),
      );
    });
  }

  static bool _celebrating = false;

  /// Level-up moment with fanfare: heavy tick + burst card, once.
  /// Rapid back-to-back crossings (fast combo chains) collapse into a
  /// single celebration instead of stacking dialogs.
  static void celebrate(
      BuildContext context, GamificationStateNotifier game) {
    if (_celebrating) return;
    _celebrating = true;
    AppHaptics.celebrate();
    show(context, newLevel: game.level, rankName: game.rankName);
    Future.delayed(AppMotion.burst + AppMotion.burstHold, () {
      _celebrating = false;
    });
  }

  @override
  State<LevelUpBurst> createState() => _LevelUpBurstState();
}

class _LevelUpBurstState extends State<LevelUpBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: AppMotion.burst);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: AppMotion.heroCurve),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _c, curve: const Interval(0.0, 0.35, curve: Curves.easeOut)),
    );
    // Forwarding moves to didChangeDependencies: reduced-motion users get
    // the celebration card in its settled state (info, no fly-in).
    Future.delayed(
      AppMotion.burst + AppMotion.burstHold,
      () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is first legal to read here (not initState).
    if (AppMotion.reduced(context)) {
      _c.value = 1; // settled card, no fly-in animation.
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Center card: no saveLayer-heavy blur — opaque surfaces only,
    // petals painted by CustomPainter (one layer, no shadows).
    return Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value.clamp(0.0, 1.0);
          // Petals fly out 0→0.7, card settles 0→0.35, hold, auto-pop.
          final fadeOut = t > 0.75 ? (1.0 - (t - 0.75) / 0.25) : 1.0;
          return Opacity(
            opacity: (_fade.value * fadeOut).clamp(0.0, 1.0),
            child: ScaleTransition(
              scale: _scale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(260, 260),
                    painter: _BurstPetals(progress: t),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 20),
                    decoration: BoxDecoration(
                      color: SakuraColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: SakuraColors.cardBorder),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('✦', style: TextStyle(fontSize: 22)),
                        const SizedBox(height: 6),
                        Text(
                          'LEVEL ${widget.newLevel}',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2.4,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.rankName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: SakuraColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your bloom grows stronger',
                          style: TextStyle(
                            fontSize: 12,
                            color: SakuraColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Static-paint petal ring: 14 petals, position is pure math of [progress].
/// No BoxShadow, no images — one CustomPaint layer at 60fps, mobile-safe.
class _BurstPetals extends CustomPainter {
  final double progress;
  const _BurstPetals({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Theme-matched: everyday bursts bloom in the active primary so the
    // reward feels native on Ocean/Kyoto too — not hard-coded pink.
    final primary = SakuraColors.primary;
    const count = 14;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      // Ease-out flight: fast launch, gentle settle.
      final eased = 1 - math.pow(1 - progress.clamp(0.0, 1.0), 3);
      final dist = 40 + eased * 85 + (i.isEven ? 10 : 0);
      final pos = c +
          Offset(math.cos(angle) * dist, math.sin(angle) * dist - eased * 12);
      final petalSize = 10 - eased * 4;
      final alpha = ((1 - progress) * 0.95).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = (i % 3 == 0
                ? primary
                : Color.lerp(primary, const Color(0xFFFFFFFF), 0.45)!)
            .withValues(alpha: alpha);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle + progress * 1.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero,
              width: petalSize * 0.7,
              height: petalSize * 1.3),
          Radius.circular(petalSize * 0.35),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPetals old) => old.progress != progress;
}
