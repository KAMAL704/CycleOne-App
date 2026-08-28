import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A lightweight animated backdrop shared by every route. It stays behind
/// the page content so cards and dialogs remain readable while the app feels
/// alive even when no ESP hardware is connected.
class CinematicBackground extends StatefulWidget {
  const CinematicBackground({super.key, required this.child});

  final Widget child;

  @override
  State<CinematicBackground> createState() => _CinematicBackgroundState();
}

class _CinematicBackgroundState extends State<CinematicBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) =>
              CustomPaint(painter: _CinematicPainter(_controller.value)),
        ),
      ),
      widget.child,
    ],
  );
}

class _CinematicPainter extends CustomPainter {
  const _CinematicPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF1F8F3),
    );

    final t = progress * math.pi * 2;
    _blob(
      canvas,
      size,
      Offset(
        size.width * (.16 + .04 * math.sin(t)),
        size.height * (.15 + .04 * math.cos(t)),
      ),
      size.width * .62,
      const Color(0xFF8DE5B4),
    );
    _blob(
      canvas,
      size,
      Offset(
        size.width * (.92 + .04 * math.cos(t * .8)),
        size.height * (.42 + .08 * math.sin(t * .8)),
      ),
      size.width * .70,
      const Color(0xFF9ED6EF),
    );
    _blob(
      canvas,
      size,
      Offset(
        size.width * (.48 + .08 * math.sin(t * .65)),
        size.height * (1.02 + .04 * math.cos(t)),
      ),
      size.width * .74,
      const Color(0xFFC9A7EE),
    );

    final linePaint = Paint()
      ..color = Colors.white.withAlpha(55)
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width + size.height; x += 44) {
      canvas.drawLine(
        Offset(x + (progress * 44), 0),
        Offset(x + size.height + (progress * 44), size.height),
        linePaint,
      );
    }

    final dotPaint = Paint()..color = const Color(0xFF167A4A).withAlpha(22);
    for (var index = 0; index < 20; index++) {
      final x =
          (size.width * ((index * 37) % 100) / 100) + 8 * math.sin(t + index);
      final y =
          (size.height * ((index * 61) % 100) / 100) +
          8 * math.cos(t * .7 + index);
      canvas.drawCircle(Offset(x, y), 1.5 + (index % 3), dotPaint);
    }
  }

  void _blob(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    Color color,
  ) {
    final shader = RadialGradient(
      colors: [color.withAlpha(82), color.withAlpha(18), Colors.transparent],
      stops: const [0, .48, 1],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _CinematicPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
