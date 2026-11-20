import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/auth_controller.dart';
import '../services/locale_controller.dart';
import '../services/push_notification_service.dart';
import '../services/queue_realtime_service.dart';
import '../services/queue_service.dart';
import '../services/reminder_service.dart';
import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'my_queue_screen.dart';
import 'profile_screen.dart';
import 'reminders_screen.dart';

/// The root patient application shell featuring bottom navigation across:
/// 1. Home
/// 2. My Queue
/// 3. Reminders
/// 4. Profile
class PatientShell extends StatefulWidget {
  const PatientShell({
    super.key,
    this.initialIndex = 0,
    this.reminderService,
    this.authController,
    this.queueService,
    this.pushNotificationService,
    this.realtimeService,
    this.localeController,
    this.themeController,
  });

  final int initialIndex;
  final ReminderService? reminderService;
  final AuthController? authController;
  final QueueService? queueService;
  final PushNotificationService? pushNotificationService;
  final QueueRealtimeService? realtimeService;
  final LocaleController? localeController;
  final ThemeController? themeController;

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabSelected(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final screens = <Widget>[
      HomeScreen(
        isActiveTab: _currentIndex == 0,
        onNavigateToQueue: () => _onTabSelected(1),
        onNavigateToReminders: () => _onTabSelected(2),
        queueService: widget.queueService,
        reminderService: widget.reminderService,
        pushNotificationService: widget.pushNotificationService,
        realtimeService: widget.realtimeService,
      ),
      MyQueueScreen(
        isActiveTab: _currentIndex == 1,
        queueService: widget.queueService,
        pushNotificationService: widget.pushNotificationService,
        realtimeService: widget.realtimeService,
      ),
      RemindersScreen(reminderService: widget.reminderService),
      ProfileScreen(
        authController: widget.authController,
        localeController: widget.localeController,
        themeController: widget.themeController,
      ),
    ];

    final colors = context.dentalColors;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: colors.border),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: NavigationBar(
          key: const Key('patient_bottom_navigation_bar'),
          height: 68,
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabSelected,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              key: const Key('nav_home'),
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: l10n.navHome,
            ),
            NavigationDestination(
              key: const Key('nav_my_queue'),
              icon: const Icon(Icons.confirmation_number_outlined),
              selectedIcon: const Icon(Icons.confirmation_number_rounded),
              label: l10n.navMyQueue,
            ),
            NavigationDestination(
              key: const Key('nav_reminders'),
              icon: const Icon(Icons.alarm_outlined),
              selectedIcon: const Icon(Icons.alarm_rounded),
              label: l10n.navReminders,
            ),
            NavigationDestination(
              key: const Key('nav_profile'),
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person_rounded),
              label: l10n.navProfile,
            ),
          ],
        ),
      ),
    );
  }
}
