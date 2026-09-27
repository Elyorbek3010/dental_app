import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/screens/reminders_screen.dart';
import 'package:app/services/local_notification_service.dart';
import 'package:app/services/reminder_service.dart';

class FakeLocalNotificationService implements LocalNotificationService {
  final List<int> scheduledIds = [];
  final List<int> cancelledIds = [];

  @override
  bool get isInitialized => true;

  @override
  Future<bool> initialize({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async =>
      true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    scheduledIds.add(id);
    return true;
  }

  @override
  Future<bool> cancelNotification(int id) async {
    cancelledIds.add(id);
    return true;
  }

  @override
  Future<bool> cancelAllNotifications() async {
    cancelledIds.clear();
    return true;
  }

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemindersScreen Widget Tests', () {
    late ReminderService service;
    late FakeLocalNotificationService fakeNotificationService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      fakeNotificationService = FakeLocalNotificationService();
      service = ReminderService(
        notificationService: fakeNotificationService,
        initialPreferences: prefs,
      );
    });

    testWidgets('Shows empty state when no reminders exist', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RemindersScreen(reminderService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Eslatmalarim'), findsOneWidget);
      expect(find.text('Hozircha eslatmalar yo‘q'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('Renders reminder cards when reminders exist', (WidgetTester tester) async {
      final futureDate = DateTime.now().add(const Duration(days: 3));
      await service.createReminder(
        scheduledAt: futureDate,
        note: 'Tish tozalash',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RemindersScreen(reminderService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tish tozalash'), findsOneWidget);
      expect(find.text('Kutilmoqda'), findsOneWidget);
      expect(find.text('Tahrirlash'), findsOneWidget);
      expect(find.text('O‘chirish'), findsOneWidget);
    });

    testWidgets('Tapping delete button shows confirmation dialog and cancels on bekor qilish',
        (WidgetTester tester) async {
      final futureDate = DateTime.now().add(const Duration(days: 4));
      await service.createReminder(
        scheduledAt: futureDate,
        note: 'Doktor ko‘rigi',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RemindersScreen(reminderService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Doktor ko‘rigi'), findsOneWidget);

      // Tap delete button on the reminder card
      await tester.tap(find.text('O‘chirish'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog is displayed
      expect(find.text('Eslatmani o‘chirish'), findsOneWidget);
      expect(find.text('Bekor qilish'), findsOneWidget);

      // Tap cancel
      await tester.tap(find.text('Bekor qilish'));
      await tester.pumpAndSettle();

      // Reminder is not deleted
      expect(find.text('Doktor ko‘rigi'), findsOneWidget);
    });
  });
}
