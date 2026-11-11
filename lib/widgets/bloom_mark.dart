import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/sakura_theme.dart';

/// Brand mark — a five-petal sakura bloom drawn from the active theme.
///
/// Replaces the bundled Flutter icon asset so the logo stays crisp at any
/// size, follows theme colours (Edo / Midnight), and costs no image decode.
class BloomMark extends StatelessWidget {
  const BloomMark({super.key, this.size = 48, this.color});

  final double size;

  /// Overrides the theme primary (used on tinted/coloured backgrounds).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BloomPainter(
          petal: color ?? SakuraColors.primary,
          petalDark: color == null ? SakuraColors.primaryDark : color!,
          center: color == null ? SakuraColors.heatPeak : Colors.white,
        ),
      ),
    );
  }
}

class _BloomPainter extends CustomPainter {
  _BloomPainter({
    required this.petal,
    required this.petalDark,
    required this.center,
  });

  final Color petal;
  final Color petalDark;
  final Color center;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    // Petal length leaves a little breathing room inside the box.
    final r = side * 0.47;
    final w = side * 0.20;

    // Teardrop petal with a soft notch at the tip — reads as sakura, not
    // a generic five-petal flower, even at 40px.
    final petalPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(-w * 0.72, -r * 0.34, -w * 0.90, -r * 0.82, -w * 0.40, -r)
      ..quadraticBezierTo(0, -r * 0.72, w * 0.40, -r)
      ..cubicTo(w * 0.90, -r * 0.82, w * 0.72, -r * 0.34, 0, 0)
      ..close();

    final shader = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [petal, petalDark],
    ).createShader(Rect.fromCircle(center: c, radius: r));

    final fill = Paint()..shader = shader;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.012
      ..color = petalDark.withValues(alpha: 0.35);

    for (var i = 0; i < 5; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * 2 * math.pi / 5);
      canvas.drawPath(petalPath, fill);
      canvas.drawPath(petalPath, edge);
      canvas.restore();
    }

    // Soft core so the petals read as one flower, not a spiky star.
    canvas.drawCircle(
      c,
      side * 0.115,
      Paint()..color = SakuraColors.background.withValues(alpha: 0.92),
    );
    canvas.drawCircle(c, side * 0.078, Paint()..color = center);
    canvas.drawCircle(
      c,
      side * 0.034,
      Paint()..color = center.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _BloomPainter old) =>
      old.petal != petal || old.petalDark != petalDark || old.center != center;
}
