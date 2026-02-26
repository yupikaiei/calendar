import 'dart:ui';
import 'package:flutter/material.dart';

/// A Flutter widget that animates the Frelsi Runic Wordmark
/// mimicking the "carved" strike effect from the splash screen.
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
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final Paint emberPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    // Scaling the paths based on the 320x80 viewBox
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

    // F (Fehu)
    final pathF = Path()
      ..moveTo(20, 10)
      ..lineTo(20, 70)
      ..moveTo(20, 25)
      ..lineTo(50, 5)
      ..moveTo(20, 45)
      ..lineTo(45, 25);
    drawAnimatedPath(pathF, ironPaint, 0.0, 0.3);

    // R (Raido)
    final pathR = Path()
      ..moveTo(70, 10)
      ..lineTo(70, 70)
      ..moveTo(70, 10)
      ..lineTo(90, 10)
      ..lineTo(105, 30)
      ..lineTo(85, 45)
      ..lineTo(70, 45)
      ..moveTo(85, 45)
      ..lineTo(110, 70);
    drawAnimatedPath(pathR, ironPaint, 0.2, 0.5);

    // E (Aggressive)
    final pathE = Path()
      ..moveTo(140, 10)
      ..lineTo(140, 70)
      ..moveTo(140, 10)
      ..lineTo(165, 25)
      ..moveTo(140, 40)
      ..lineTo(160, 40)
      ..moveTo(140, 55)
      ..lineTo(165, 70);
    drawAnimatedPath(pathE, ironPaint, 0.4, 0.7);

    // L (Laguz)
    final pathL = Path()
      ..moveTo(190, 10)
      ..lineTo(190, 70)
      ..lineTo(220, 70);
    drawAnimatedPath(pathL, ironPaint, 0.6, 0.8);

    // S (Sowilo - Ember)
    final pathS = Path()
      ..moveTo(265, 10)
      ..lineTo(240, 30)
      ..lineTo(270, 50)
      ..lineTo(245, 70);
    drawAnimatedPath(pathS, emberPaint, 0.7, 0.95);

    // I (Isa)
    final pathI = Path()
      ..moveTo(295, 10)
      ..lineTo(295, 70);
    drawAnimatedPath(pathI, ironPaint, 0.8, 1.0);
  }

  @override
  bool shouldRepaint(RunicWordmarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
