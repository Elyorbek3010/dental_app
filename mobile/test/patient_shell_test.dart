import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/models/patient_ticket.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/screens/patient_shell.dart';
import 'package:app/screens/profile_screen.dart';
import 'package:app/screens/reminders_screen.dart';
import 'package:app/screens/specialization_select_screen.dart';
import 'package:app/services/local_notification_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/reminder_service.dart';
import 'package:app/theme/app_theme.dart';

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

class FakeQueueService extends QueueService {
  @override
  Future<MyQueueTicket?> getMyTicket() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Patient UI & Navigation Tests', () {
    late ReminderService reminderService;
    late FakeLocalNotificationService fakeNotificationService;
    late FakeQueueService fakeQueueService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      fakeNotificationService = FakeLocalNotificationService();
      fakeQueueService = FakeQueueService();
      QueueService.instance = fakeQueueService;
      reminderService = ReminderService(
        notificationService: fakeNotificationService,
        initialPreferences: prefs,
      );
    });

    Widget createTestApp({Widget? child, int initialIndex = 0}) {
      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: child ??
            PatientShell(
              initialIndex: initialIndex,
              reminderService: reminderService,
              queueService: fakeQueueService,
            ),
      );
    }

    void setMobileDimensions(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('1. Patient shell loads with bottom navigation', (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(PatientShell), findsOneWidget);
      expect(find.byKey(const Key('patient_bottom_navigation_bar')), findsOneWidget);
      expect(find.text('Asosiy'), findsOneWidget);
      expect(find.text('Navbatim'), findsOneWidget);
      expect(find.text('Eslatmalar'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
    });

    testWidgets('2. Home empty state appears on initial load', (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Dental Queue'), findsOneWidget);
      expect(find.text('Assalomu alaykum!'), findsOneWidget);
      expect(find.text('Joriy navbat holati'), findsOneWidget);
      expect(find.text('Faol navbatingiz yo‘q'), findsOneWidget);
    });

    testWidgets('3. Bottom navigation switches to My Queue and displays empty state',
        (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Tap on 'Navbatim' destination
      await tester.tap(find.byKey(const Key('nav_my_queue')));
      await tester.pumpAndSettle();

      expect(find.byType(MyQueueScreen), findsOneWidget);
      expect(find.text('Mening navbatim'), findsOneWidget);
      expect(find.text('Faol navbatingiz yo‘q'), findsOneWidget);
      expect(find.text('Navbat imkoniyatlari:'), findsOneWidget);
    });

    testWidgets('4. Bottom navigation switches to Reminders screen and remains accessible',
        (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Tap on 'Eslatmalar' destination
      await tester.tap(find.byKey(const Key('nav_reminders')));
      await tester.pumpAndSettle();

      expect(find.byType(RemindersScreen), findsOneWidget);
      expect(find.text('Eslatmalarim'), findsOneWidget);
      expect(find.text('Hozircha eslatmalar yo‘q'), findsOneWidget);
    });

    testWidgets('5. Bottom navigation switches to Profile screen and loads placeholders',
        (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Tap on 'Profil' destination
      await tester.tap(find.byKey(const Key('nav_profile')));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Profil'), findsOneWidget);
      expect(find.text('Bemor hisobi'), findsOneWidget);
      expect(find.text('Hisob maʼlumotlari yuklanmagan'), findsOneWidget);
      expect(find.text('Telefon raqam'), findsOneWidget);
      expect(find.text('Biriktirilmagan'), findsOneWidget);
      expect(find.text('Tizimdan chiqish'), findsOneWidget);

      // Scroll to logout button if needed and tap
      await tester.ensureVisible(find.byKey(const Key('profile_logout_button')));
      await tester.tap(find.byKey(const Key('profile_logout_button')));
      await tester.pump();
      expect(find.text('Autentifikatsiya keyingi bosqichda ulanadi.'), findsOneWidget);
    });

    testWidgets('6. Join Queue CTA from Home navigates to SpecializationSelectScreen',
        (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Tap 'Navbatga yozilish' button on Home
      await tester.tap(find.byKey(const Key('home_join_queue_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify SpecializationSelectScreen appears
      expect(find.byType(SpecializationSelectScreen), findsOneWidget);
      expect(find.text('Mutaxassislikni tanlash'), findsOneWidget);

      // Verify back button pops back to Home
      await tester.tap(find.byTooltip('Ortga'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('7. Join Queue CTA from My Queue navigates to SpecializationSelectScreen',
        (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp(initialIndex: 1));
      await tester.pumpAndSettle();

      expect(find.byType(MyQueueScreen), findsOneWidget);

      // Tap 'Navbatga yozilish' CTA button
      await tester.tap(find.text('Navbatga yozilish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SpecializationSelectScreen), findsOneWidget);
      expect(find.text('Mutaxassislikni tanlash'), findsOneWidget);
    });

    testWidgets('8. Quick reminders button on Home switches to Reminders tab',
        (WidgetTester tester) async {
      setMobileDimensions(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('home_reminders_quick_button')));
      await tester.tap(find.byKey(const Key('home_reminders_quick_button')));
      await tester.pumpAndSettle();

      // Verifies tab changed to RemindersScreen
      expect(find.byType(RemindersScreen), findsOneWidget);
      expect(find.text('Eslatmalarim'), findsOneWidget);
    });
  });
}
