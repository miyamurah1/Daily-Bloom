import 'dart:math';

import 'package:flutter/material.dart';

import 'bloom_game_colors.dart';

/// Environment wrapper — whisper-quiet petal drift on every streak.
///
/// Fresh gardens (streak 0) drift softly so day 0 already feels alive;
/// earned streaks (>= 3) bloom fuller. One 14s loop, ~22 motes, one
/// [CustomPainter] — no shadows, no wilt dimming.
///
/// ```dart
/// DynamicBloomBackground(
///   streak: game.streak,
///   child: Scaffold(...),
/// )
/// ```
class DynamicBloomBackground extends StatefulWidget {
  final int streak;
  final Widget child;

  const DynamicBloomBackground({
    super.key,
    required this.streak,
    required this.child,
  });

  @override
  State<DynamicBloomBackground> createState() =>
      _DynamicBloomBackgroundState();
}

class _DynamicBloomBackgroundState extends State<DynamicBloomBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    // One 14s loop for all motes — positions derive from progress,
    // so per-frame cost is a single CustomPaint repaint.
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The user can flip "remove animations" at any time, so re-evaluate on
    // every dependency change: pause the loop outright under reduced-motion
    // (stopping the ticker, not just hiding the layer) so nothing repaints
    // in the background; resume otherwise. Guarded so a stopped controller
    // is never re-repeated twice.
    final mq = MediaQuery.maybeOf(context);
    final reduce = mq != null && mq.disableAnimations;
    if (reduce && _drift.isAnimating) {
      _drift.stop();
    } else if (!reduce && !_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced-motion: skip the drift layer entirely (PetalRain does the
    // same) so the OS "remove animations" setting is honored here too —
    // a fresh garden still renders, just still.
    final mq = MediaQuery.maybeOf(context);
    if (mq != null && mq.disableAnimations) return widget.child;
    // Day-0 magic: a fresh garden (streak 0) gets the same whisper-quiet
    // drift as a streak — at half strength — so the first session already
    // feels alive. Earned streaks (>= 3) bloom fuller. No wilt dimming:
    // a blank desaturated screen is the opposite of a welcome.
    final welcome = widget.streak <= 0;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _drift,
                builder: (context, _) => CustomPaint(
                  painter: _DriftPainter(
                    progress: _drift.value,
                    strength: welcome
                        ? 0.45
                        : (0.5 +
                                0.5 *
                                    ((widget.streak - 2) / 5)
                                        .clamp(0.0, 1.0))
                            .clamp(0.4, 1.0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Deterministic mote field: fixed seed so layout never jumps on rebuild.
/// Each mote drifts slowly upward with a sine sway; alpha stays whisper
/// quiet (0.05–0.14) to read as dust, not snow.
///
/// Perf: paints cached per (pink × strength-bucket), no per-mote Paint
/// allocation in the loop. 14 motes on mobile (was 22).
class _DriftPainter extends CustomPainter {
  final double progress;
  final double strength;

  _DriftPainter({required this.progress, required this.strength});

  static final List<_Mote> _motes = _buildMotes();

  static List<_Mote> _buildMotes() {
    final rand = Random(7);
    return List.generate(14, (_) {
      return _Mote(
        x: rand.nextDouble(),
        y: rand.nextDouble(),
        r: 1.2 + rand.nextDouble() * 2.2,
        speed: 0.03 + rand.nextDouble() * 0.06,
        sway: 0.015 + rand.nextDouble() * 0.03,
        phase: rand.nextDouble() * 2 * pi,
        alpha: 0.05 + rand.nextDouble() * 0.09,
        pink: rand.nextBool(),
      );
    });
  }

  static final Map<int, Paint> _paintCache = {};

  Paint _paintFor(bool pink, double alpha) {
    // Bucket alpha to 8 steps so the cache stays tiny while motes still
    // shimmer as strength changes.
    final bucket = (alpha * 8).round().clamp(0, 8);
    final key = (pink ? 100 : 0) + bucket;
    return _paintCache.putIfAbsent(
        key,
        () => Paint()
          ..color = (pink ? BloomGameColors.bloom : BloomGameColors.violet)
              .withValues(alpha: (bucket / 8).clamp(0.02, 0.16)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in _motes) {
      var y = (m.y - progress * m.speed * 4) % 1.0;
      if (y < 0) y += 1.0;
      final x =
          (m.x + sin(progress * 2 * pi + m.phase) * m.sway).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        m.r,
        _paintFor(m.pink, m.alpha * strength),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DriftPainter old) =>
      old.progress != progress || old.strength != strength;
}

class _Mote {
  final double x;
  final double y;
  final double r;
  final double speed;
  final double sway;
  final double phase;
  final double alpha;
  final bool pink;

  const _Mote({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.sway,
    required this.phase,
    required this.alpha,
    required this.pink,
  });
}
