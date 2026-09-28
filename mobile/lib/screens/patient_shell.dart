import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/auth_controller.dart';
import '../services/push_notification_service.dart';
import '../services/queue_service.dart';
import '../services/reminder_service.dart';
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
  });

  final int initialIndex;
  final ReminderService? reminderService;
  final AuthController? authController;
  final QueueService? queueService;
  final PushNotificationService? pushNotificationService;

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
        onNavigateToQueue: () => _onTabSelected(1),
        onNavigateToReminders: () => _onTabSelected(2),
      ),
      MyQueueScreen(
        queueService: widget.queueService,
        pushNotificationService: widget.pushNotificationService,
      ),
      RemindersScreen(reminderService: widget.reminderService),
      ProfileScreen(authController: widget.authController),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('patient_bottom_navigation_bar'),
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: [
          NavigationDestination(
            key: const Key('nav_home'),
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            key: const Key('nav_my_queue'),
            icon: const Icon(Icons.confirmation_number_outlined),
            selectedIcon: const Icon(Icons.confirmation_number),
            label: l10n.navMyQueue,
          ),
          NavigationDestination(
            key: const Key('nav_reminders'),
            icon: const Icon(Icons.alarm_outlined),
            selectedIcon: const Icon(Icons.alarm),
            label: l10n.navReminders,
          ),
          NavigationDestination(
            key: const Key('nav_profile'),
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.navProfile,
          ),
        ],
      ),
    );
  }
}
