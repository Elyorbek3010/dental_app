import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact circular progress countdown indicator with MM:SS tabular text.
class CircularCountdown extends StatelessWidget {
  const CircularCountdown({
    super.key,
    required this.remainingSeconds,
    this.totalSeconds = 120,
    this.isPaused = false,
    this.size = 64,
  });

  final int remainingSeconds;
  final int totalSeconds;
  final bool isPaused;
  final double size;

  static String formatMmSs(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final mins = safe ~/ 60;
    final secs = safe % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dentalColors;
    final maxSec = math.max(1, math.max(totalSeconds, remainingSeconds));
    final progress = (remainingSeconds / maxSec).clamp(0.0, 1.0);
    final isUrgent = !isPaused && remainingSeconds <= 15;

    final Color activeColor = isPaused
        ? colors.warning
        : (isUrgent ? colors.error : colors.teal);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(
              progress: progress,
              trackColor: colors.border,
              activeColor: activeColor,
              strokeWidth: 5,
            ),
          ),
          Text(
            formatMmSs(remainingSeconds),
            style: TextStyle(
              fontSize: size * 0.23,
              fontWeight: FontWeight.w800,
              color: activeColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.activeColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color activeColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.activeColor != activeColor;
  }
}
