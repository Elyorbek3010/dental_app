import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/main.dart';
import 'package:app/models/patient_ticket.dart';
import 'package:app/screens/patient_shell.dart';
import 'package:app/services/local_notification_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/reminder_service.dart';

class FakeLocalNotificationService implements LocalNotificationService {
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
  }) async =>
      true;

  @override
  Future<bool> cancelNotification(int id) async => true;

  @override
  Future<bool> cancelAllNotifications() async => true;

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async => [];
}

class FakeQueueService extends QueueService {
  @override
  Future<MyQueueTicket?> getMyTicket() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MyApp renders PatientShell successfully', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeNotificationService = FakeLocalNotificationService();
    final fakeQueueService = FakeQueueService();
    QueueService.instance = fakeQueueService;
    final reminderService = ReminderService(
      notificationService: fakeNotificationService,
      initialPreferences: prefs,
    );

    await tester.pumpWidget(
      MyApp(
        home: PatientShell(
          reminderService: reminderService,
          queueService: fakeQueueService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PatientShell), findsOneWidget);
    expect(find.text('Dental Queue'), findsOneWidget);
    expect(find.byKey(const Key('patient_bottom_navigation_bar')), findsOneWidget);
  });
}
