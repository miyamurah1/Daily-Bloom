import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Drifting cherry-blossom petals behind auth screens. One looping
/// controller, ~12 petals on phones, all math — no assets, no packages.
/// Pure decoration: remove this wrapper and nothing else changes.
///
/// Perf notes (mobile 60fps):
/// - Positions derive from controller progress (deterministic) — no
///   mutation inside the builder, no `Random()` per frame.
/// - Paints are cached statics; `shouldRepaint` only on progress change.
/// - Respects reduced-motion (renders child only) and pauses offscreen
///   via [TickerMode] from ancestors.
class PetalRain extends StatefulWidget {
  final Widget child;
  final int petalCount;

  const PetalRain({super.key, required this.child, this.petalCount = 12});

  @override
  State<PetalRain> createState() => _PetalRainState();
}

class _Petal {
  final double x; // 0..1 across
  final double y; // 0..1 down (wraps past 1.15)
  final double size;
  final double fall; // fraction of height per loop
  final double sway; // horizontal amplitude (fraction of width)
  final double phase;
  final Color color;

  const _Petal({
    required this.x,
    required this.y,
    required this.size,
    required this.fall,
    required this.sway,
    required this.phase,
    required this.color,
  });
}

class _PetalRainState extends State<PetalRain>
    with SingleTickerProviderStateMixin {
  static const _petalColors = [
    Color(0xFFF4B9C6),
    Color(0xFFF9E0E6),
    Color(0xFFEC7E99),
    Color(0xFFFBE3E8),
  ];

  late final AnimationController _ctrl;
  late final List<_Petal> _petals;

  @override
  void initState() {
    super.initState();
    final rnd = Random(20260923);
    // Cap petals on mobile: callers pass 10-16; clamp to 12 max so a
    // low-end phone never paints 16 rotating ovals at 60fps.
    final count = widget.petalCount.clamp(0, 12);
    _petals = List.generate(
      count,
      (_) => _Petal(
        x: rnd.nextDouble(),
        y: rnd.nextDouble() * 1.15 - 0.1,
        size: 5 + rnd.nextDouble() * 8,
        fall: 0.05 + rnd.nextDouble() * 0.07,
        sway: 0.015 + rnd.nextDouble() * 0.025,
        phase: rnd.nextDouble() * 2 * pi,
        color: _petalColors[rnd.nextInt(_petalColors.length)],
      ),
    );
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq != null && mq.disableAnimations) return widget.child;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => CustomPaint(
                painter: _PetalPainter(_petals, _ctrl.value),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _PetalPainter extends CustomPainter {
  final List<_Petal> petals;
  final double progress;
  const _PetalPainter(this.petals, this.progress);

  // Cached paints — one per petal colour + one highlight. Creating a
  // Paint per petal per frame was the old hotspot.
  static final Map<Color, Paint> _fillCache = {};
  static final Paint _highlight =
      Paint()..color = Colors.white.withValues(alpha: 0.45);

  static Paint _fillFor(Color c) => _fillCache.putIfAbsent(
      c, () => Paint()..color = c.withValues(alpha: 0.70));

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in petals) {
      // Deterministic drift: y loops with progress, x sways by sine.
      // No state mutation — same progress always paints same frame.
      var y = (p.y + progress * p.fall * 4) % 1.25;
      if (y < 0) y += 1.25;
      final dx = (p.x + p.sway * sin(progress * 2 * pi + p.phase)) * size.width;
      final dy = (y - 0.1) * size.height;
      final rot = progress * 2 * pi * 0.6 + p.phase;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rot);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: p.size, height: p.size * 1.3),
          _fillFor(p.color));
      canvas.restore();
      // Highlight dot without a second save/restore: tiny circle at the
      // petal centre, slightly offset up (cheap, one draw call).
      canvas.drawCircle(
          Offset(dx, dy - p.size * 0.3), p.size * 0.28, _highlight);
    }
  }

  @override
  bool shouldRepaint(covariant _PetalPainter old) =>
      old.progress != progress || !identical(old.petals, petals);
}
