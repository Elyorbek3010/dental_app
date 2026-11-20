import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Clean Premium Dental tooth emblem rendered crisply via vector paths.
class DentalLogo extends StatelessWidget {
  const DentalLogo({
    super.key,
    this.size = 44,
    this.withBadge = true,
  });

  final double size;
  final bool withBadge;

  @override
  Widget build(BuildContext context) {
    final colors = context.dentalColors;
    final logoPaint = CustomPaint(
      size: Size.square(size * (withBadge ? 0.56 : 1.0)),
      painter: _DentalToothPainter(
        primaryColor: withBadge ? Colors.white : colors.teal,
        shineColor: withBadge ? colors.tealSoft : colors.blueSoft,
      ),
    );

    if (!withBadge) {
      return logoPaint;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.teal, colors.blue],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: colors.teal.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: logoPaint,
    );
  }
}

class _DentalToothPainter extends CustomPainter {
  const _DentalToothPainter({
    required this.primaryColor,
    required this.shineColor,
  });

  final Color primaryColor;
  final Color shineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.50, h * 0.14)
      ..cubicTo(w * 0.34, h * 0.06, w * 0.14, h * 0.16, w * 0.16, h * 0.38)
      ..cubicTo(w * 0.17, h * 0.54, w * 0.25, h * 0.72, w * 0.31, h * 0.86)
      ..cubicTo(w * 0.34, h * 0.93, w * 0.42, h * 0.90, w * 0.44, h * 0.78)
      ..cubicTo(w * 0.46, h * 0.67, w * 0.54, h * 0.67, w * 0.56, h * 0.78)
      ..cubicTo(w * 0.58, h * 0.90, w * 0.66, h * 0.93, w * 0.69, h * 0.86)
      ..cubicTo(w * 0.75, h * 0.72, w * 0.83, h * 0.54, w * 0.84, h * 0.38)
      ..cubicTo(w * 0.86, h * 0.16, w * 0.66, h * 0.06, w * 0.50, h * 0.14)
      ..close();

    final fillPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final highlightPaint = Paint()
      ..color = shineColor.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round;

    final highlightPath = Path()
      ..moveTo(w * 0.32, h * 0.28)
      ..quadraticBezierTo(w * 0.30, h * 0.37, w * 0.34, h * 0.45);
    canvas.drawPath(highlightPath, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _DentalToothPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.shineColor != shineColor;
  }
}
