import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Semantic queue status chip with paired icon + text label.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    required this.label,
    this.isPaused = false,
    this.textKey,
  });

  final String status;
  final String label;
  final bool isPaused;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.dentalColors;

    final _StatusVisual visual = _resolveVisual(colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: visual.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: visual.fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 14, color: visual.fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              key: textKey,
              softWrap: true,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: visual.fg,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _StatusVisual _resolveVisual(DentalThemeTokens colors) {
    if (isPaused) {
      return _StatusVisual(
        fg: colors.warning,
        bg: colors.warningSoft,
        icon: Icons.pause_circle_outline_rounded,
      );
    }

    switch (status.toUpperCase()) {
      case 'CLOSING':
        return _StatusVisual(
          fg: colors.warning,
          bg: colors.warningSoft,
          icon: Icons.lock_clock_outlined,
        );
      case 'CALLED':
        return _StatusVisual(
          fg: colors.warning,
          bg: colors.warningSoft,
          icon: Icons.notifications_active_rounded,
        );
      case 'SERVING':
        return _StatusVisual(
          fg: colors.teal,
          bg: colors.tealSoft,
          icon: Icons.medical_services_outlined,
        );
      case 'COMPLETED':
        return _StatusVisual(
          fg: colors.success,
          bg: colors.successSoft,
          icon: Icons.check_circle_outline_rounded,
        );
      case 'SKIPPED':
        return _StatusVisual(
          fg: colors.error,
          bg: colors.errorSoft,
          icon: Icons.warning_amber_rounded,
        );
      case 'CANCELLED':
        return _StatusVisual(
          fg: colors.textSecondary,
          bg: colors.surfaceMuted,
          icon: Icons.cancel_outlined,
        );
      case 'WAITING':
      default:
        return _StatusVisual(
          fg: colors.blue,
          bg: colors.blueSoft,
          icon: Icons.schedule_rounded,
        );
    }
  }
}

class _StatusVisual {
  const _StatusVisual({
    required this.fg,
    required this.bg,
    required this.icon,
  });

  final Color fg;
  final Color bg;
  final IconData icon;
}
