import 'dart:ui';
import 'package:flutter/material.dart';

/// A Flutter widget that animates the Frelsi Runic Wordmark
/// with a modern, clean stroke aesthetic and gradient accent.
class FrelsiWordmark extends StatefulWidget {
  const FrelsiWordmark({super.key});

  @override
  State<FrelsiWordmark> createState() => _FrelsiWordmarkState();
}

class _FrelsiWordmarkState extends State<FrelsiWordmark>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(320, 80),
          painter: RunicWordmarkPainter(progress: _controller.value),
        );
      },
    );
  }
}

class RunicWordmarkPainter extends CustomPainter {
  final double progress;

  RunicWordmarkPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint ironPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Gradient accent paint (purple → cyan) matching the new logo
    final Paint accentPaint = Paint()
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        colors: [Color(0xFF6C63FF), Color(0xFF03DAC6)],
      ).createShader(const Rect.fromLTWH(230, 10, 50, 60));

    double scale = size.width / 320;
    canvas.scale(scale);

    void drawAnimatedPath(Path path, Paint paint, double start, double end) {
      if (progress < start) return;
      double localProgress = ((progress - start) / (end - start)).clamp(
        0.0,
        1.0,
      );

      PathMetrics pathMetrics = path.computeMetrics();
      for (PathMetric pathMetric in pathMetrics) {
        Path extract = pathMetric.extractPath(
          0.0,
          pathMetric.length * localProgress,
        );
        canvas.drawPath(extract, paint);
      }
    }

    // F (Fehu) — clean diagonal arms
    final pathF = Path()
      ..moveTo(20, 12)
      ..lineTo(20, 68)
      ..moveTo(20, 22)
      ..lineTo(48, 8)
      ..moveTo(20, 40)
      ..lineTo(42, 30);
    drawAnimatedPath(pathF, ironPaint, 0.0, 0.20);

    // R — rounded bowl
    final pathR = Path()
      ..moveTo(65, 12)
      ..lineTo(65, 68)
      ..moveTo(65, 12)
      ..lineTo(85, 12)
      ..quadraticBezierTo(100, 12, 100, 28)
      ..quadraticBezierTo(100, 42, 85, 42)
      ..lineTo(65, 42)
      ..moveTo(85, 42)
      ..lineTo(105, 68);
    drawAnimatedPath(pathR, ironPaint, 0.15, 0.38);

    // E — clean horizontal arms
    final pathE = Path()
      ..moveTo(125, 12)
      ..lineTo(125, 68)
      ..moveTo(125, 12)
      ..lineTo(150, 12)
      ..moveTo(125, 40)
      ..lineTo(147, 40)
      ..moveTo(125, 68)
      ..lineTo(150, 68);
    drawAnimatedPath(pathE, ironPaint, 0.30, 0.52);

    // L — simple vertical + base
    final pathL = Path()
      ..moveTo(170, 12)
      ..lineTo(170, 68)
      ..lineTo(195, 68);
    drawAnimatedPath(pathL, ironPaint, 0.45, 0.62);

    // S (Sowilö) — lightning bolt with gradient accent
    final pathS = Path()
      ..moveTo(255, 12)
      ..lineTo(232, 32)
      ..lineTo(258, 48)
      ..lineTo(235, 68);
    drawAnimatedPath(pathS, accentPaint, 0.55, 0.82);

    // I — simple vertical
    final pathI = Path()
      ..moveTo(280, 12)
      ..lineTo(280, 68);
    drawAnimatedPath(pathI, ironPaint, 0.75, 1.0);
  }

  @override
  bool shouldRepaint(RunicWordmarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
