import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Subtle architectural dental-wave background accent for hero sections.
class DentalWaveBackdrop extends StatelessWidget {
  const DentalWaveBackdrop({
    super.key,
    this.height = 170,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.dentalColors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.border),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DentalWavePainter(
                  primaryTint: colors.tealSoft.withValues(alpha: 0.72),
                  secondaryTint: colors.blueSoft.withValues(alpha: 0.55),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _DentalWavePainter extends CustomPainter {
  const _DentalWavePainter({
    required this.primaryTint,
    required this.secondaryTint,
  });

  final Color primaryTint;
  final Color secondaryTint;

  @override
  void paint(Canvas canvas, Size size) {
    final topArc = Path()
      ..moveTo(size.width * 0.42, 0)
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.42,
        size.width,
        size.height * 0.28,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(
      topArc,
      Paint()
        ..color = primaryTint
        ..style = PaintingStyle.fill,
    );

    final lowerRipple = Path()
      ..moveTo(size.width * 0.55, size.height)
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.62,
        size.width,
        size.height * 0.78,
      )
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      lowerRipple,
      Paint()
        ..color = secondaryTint
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _DentalWavePainter oldDelegate) {
    return oldDelegate.primaryTint != primaryTint ||
        oldDelegate.secondaryTint != secondaryTint;
  }
}

/// Perforated clinical ticket card with left/right semi-circular cutouts.
class TicketPassCard extends StatelessWidget {
  const TicketPassCard({
    super.key,
    required this.topSection,
    required this.bottomSection,
    this.accentColor,
  });

  final Widget topSection;
  final Widget bottomSection;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.dentalColors;
    final resolvedAccent = accentColor ?? colors.teal;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 4,
            color: resolvedAccent,
          ),
          topSection,
          _TicketPerforationDivider(
            lineColor: colors.border,
            notchColor: colors.background,
          ),
          bottomSection,
        ],
      ),
    );
  }
}

class _TicketPerforationDivider extends StatelessWidget {
  const _TicketPerforationDivider({
    required this.lineColor,
    required this.notchColor,
  });

  final Color lineColor;
  final Color notchColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: CustomPaint(
        painter: _PerforationPainter(
          lineColor: lineColor,
          notchColor: notchColor,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  const _PerforationPainter({
    required this.lineColor,
    required this.notchColor,
  });

  final Color lineColor;
  final Color notchColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const notchRadius = 9.0;

    final dashPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 5.0;
    double x = notchRadius + 6;
    while (x < size.width - notchRadius - 6) {
      canvas.drawLine(
        Offset(x, cy),
        Offset((x + dashWidth).clamp(0, size.width - notchRadius - 6), cy),
        dashPaint,
      );
      x += dashWidth + dashSpace;
    }

    final notchPaint = Paint()
      ..color = notchColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(0, cy), notchRadius, notchPaint);
    canvas.drawCircle(Offset(size.width, cy), notchRadius, notchPaint);
  }

  @override
  bool shouldRepaint(covariant _PerforationPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.notchColor != notchColor;
  }
}

/// Editorial asymmetric Bento action card.
class BentoActionCard extends StatelessWidget {
  const BentoActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accentColor,
    this.accentSoftColor,
    this.badgeText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? accentColor;
  final Color? accentSoftColor;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final colors = context.dentalColors;
    final fg = accentColor ?? colors.teal;
    final bg = accentSoftColor ?? colors.tealSoft;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: fg, size: 22),
                  ),
                  if (badgeText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badgeText!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: fg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: colors.textMuted,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Crisp geometric monogram emblem for doctors without fabricating photos.
class DoctorMonogramBadge extends StatelessWidget {
  const DoctorMonogramBadge({
    super.key,
    required this.fullName,
    this.size = 52,
  });

  final String fullName;
  final double size;

  String _initials() {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dentalColors;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.blueSoft,
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: colors.blue.withValues(alpha: 0.25)),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: colors.blue,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}
