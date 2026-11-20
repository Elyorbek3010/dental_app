import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/main.dart';
import 'package:app/models/doctor.dart';
import 'package:app/models/doctor_queue.dart';
import 'package:app/models/patient_ticket.dart';
import 'package:app/models/reminder.dart';
import 'package:app/models/specialization.dart';
import 'package:app/models/user.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/screens/patient_shell.dart';
import 'package:app/screens/profile_screen.dart';
import 'package:app/services/auth_controller.dart';
import 'package:app/services/auth_service.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/locale_controller.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/reminder_service.dart';
import 'package:app/services/theme_controller.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/circular_countdown.dart';
import 'package:app/widgets/dental_logo.dart';
import 'package:app/widgets/dental_surfaces.dart';
import 'package:app/widgets/status_chip.dart';

class _TestQueueService extends QueueService {
  _TestQueueService(this.tickets);

  final List<MyQueueTicket> tickets;

  @override
  Future<List<MyQueueTicket>> getMyTickets() async => tickets;
}

class _TestCatalogService extends CatalogService {
  @override
  Future<List<Specialization>> fetchSpecializations({int clinicId = 1}) async => const [
        Specialization(id: 1, clinicId: 1, name: 'Terapiya'),
        Specialization(id: 2, clinicId: 1, name: 'Ortodontiya'),
      ];

  @override
  Future<DoctorQueue?> fetchDoctorQueue(int doctorId) async => DoctorQueue(
        id: 10,
        doctorId: doctorId,
        queueDate: '2026-11-20',
        isActive: true,
        isPaused: false,
        waitingCount: 4,
        calledCount: 1,
        servingCount: 1,
        estimatedPositionIfJoined: 5,
      );
}

class _TestReminderService extends ReminderService {
  @override
  Future<List<Reminder>> getReminders() async => [];
}

class _TestPushService implements PushNotificationService {
  @override
  Stream<Map<String, dynamic>> get queueEvents => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestRealtimeService extends QueueRealtimeService {
  @override
  void connectForConsumer(Object consumer, int clinicId) {}

  @override
  void disconnectConsumer(Object consumer) {}
}

class _TestAuthController extends AuthController {
  _TestAuthController() : super(authService: AuthService());

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;

  @override
  PatientUser? get currentUser => PatientUser(
        id: 7,
        fullName: 'Malika Karimova',
        phone: '+998901112233',
        role: 'PATIENT',
        isActive: true,
      );
}

void main() {
  group('ThemeController & Clean Premium Dental Redesign', () {
    test('defaults to ThemeMode.system and persists light/dark/system selections', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final controller = ThemeController(preferences: prefs);
      await controller.initialize();
      expect(controller.themeMode, ThemeMode.system);

      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, ThemeMode.dark);
      expect(prefs.getString(ThemeController.themeKey), 'dark');

      final reloadedDark = ThemeController(preferences: prefs);
      await reloadedDark.initialize();
      expect(reloadedDark.themeMode, ThemeMode.dark);

      await reloadedDark.setThemeMode(ThemeMode.light);
      expect(prefs.getString(ThemeController.themeKey), 'light');

      await reloadedDark.setThemeMode(ThemeMode.system);
      expect(prefs.getString(ThemeController.themeKey), 'system');
    });

    testWidgets('MyApp switches Light <-> Dark atomically in 1 frame with zero murky-grey intermediate state',
        (tester) async {
      SharedPreferences.setMockInitialValues({'patient_app_theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();

      final localeCtrl = LocaleController(preferences: prefs);
      await localeCtrl.initialize();

      final themeCtrl = ThemeController(preferences: prefs);
      await themeCtrl.initialize();

      await tester.pumpWidget(
        MyApp(
          localeController: localeCtrl,
          themeController: themeCtrl,
          home: PatientShell(
            initialIndex: 3,
            authController: _TestAuthController(),
            queueService: _TestQueueService([]),
            reminderService: _TestReminderService(),
            pushNotificationService: _TestPushService(),
            realtimeService: _TestRealtimeService(),
            localeController: localeCtrl,
            themeController: themeCtrl,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Dark and inspect first frame immediately (no 200ms lerp grey transition)
      await tester.ensureVisible(find.byKey(const Key('theme_option_dark')));
      await tester.tap(find.byKey(const Key('theme_option_dark')));
      await tester.pump();

      final darkCtx = tester.element(find.byType(ProfileScreen));
      expect(Theme.of(darkCtx).brightness, Brightness.dark);
      expect(Theme.of(darkCtx).scaffoldBackgroundColor, DentalThemeTokens.dark.background);
      expect(darkCtx.dentalColors.surface, DentalThemeTokens.dark.surface);

      // Switch back to Light and verify immediate atomic update
      await tester.tap(find.byKey(const Key('theme_option_light')));
      await tester.pump();

      final lightCtx = tester.element(find.byType(ProfileScreen));
      expect(Theme.of(lightCtx).brightness, Brightness.light);
      expect(Theme.of(lightCtx).scaffoldBackgroundColor, DentalThemeTokens.light.background);
      expect(lightCtx.dentalColors.surface, DentalThemeTokens.light.surface);
    });

    testWidgets('Theme switching preserves active MyQueueScreen countdown & ticket state without reset',
        (tester) async {
      SharedPreferences.setMockInitialValues({'patient_app_theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();

      final localeCtrl = LocaleController(preferences: prefs);
      await localeCtrl.initialize();
      await localeCtrl.setLanguageCode('en');

      final themeCtrl = ThemeController(preferences: prefs);
      await themeCtrl.initialize();

      final now = DateTime.utc(2026, 11, 20, 12, 0, 0);
      final calledTicket = MyQueueTicket(
        id: 101,
        queueId: 55,
        ticketNumber: 12,
        status: 'CALLED',
        peopleAhead: 0,
        createdAt: now.subtract(const Duration(minutes: 15)),
        doctor: const MyTicketDoctor(
          id: 9,
          fullName: 'Dr. Sardorbek Alimov',
          roomNumber: '204',
        ),
        specialization: const MyTicketSpecialization(id: 3, name: 'Endodontist'),
        callDeadlineAt: now.add(const Duration(seconds: 95)),
      );

      await tester.pumpWidget(
        MyApp(
          localeController: localeCtrl,
          themeController: themeCtrl,
          home: MyQueueScreen(
            queueService: _TestQueueService([calledTicket]),
            pushNotificationService: _TestPushService(),
            realtimeService: _TestRealtimeService(),
            nowProvider: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('№12'), findsOneWidget);
      expect(find.text('01:35'), findsOneWidget);
      expect(find.byKey(const Key('called_countdown_badge')), findsOneWidget);

      await themeCtrl.setThemeMode(ThemeMode.dark);
      await tester.pump();

      expect(find.text('№12'), findsOneWidget);
      expect(find.text('01:35'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(MyQueueScreen))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('DentalLogo, StatusChip, CircularCountdown, and TicketPassCard render cleanly in Light & Dark themes',
        (tester) async {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  const DentalLogo(size: 48),
                  const StatusChip(status: 'CALLED', label: 'Called'),
                  const StatusChip(status: 'SKIPPED', label: 'Skipped'),
                  const CircularCountdown(remainingSeconds: 75, totalSeconds: 120),
                  TicketPassCard(
                    topSection: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Stub Top'),
                    ),
                    bottomSection: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Stub Bottom'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(DentalLogo), findsOneWidget);
        expect(find.byType(StatusChip), findsNWidgets(2));
        expect(find.byType(TicketPassCard), findsOneWidget);
        expect(find.text('01:15'), findsOneWidget);
      }
    });

    testWidgets('Home, MyQueue CALLED, and DoctorQueue render with zero overflow at 412x892',
        (tester) async {
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026, 11, 20, 14, 0, 0);
      final calledTicket = MyQueueTicket(
        id: 101,
        queueId: 55,
        ticketNumber: 5,
        status: 'CALLED',
        peopleAhead: 0,
        createdAt: now.subtract(const Duration(minutes: 12)),
        doctor: const MyTicketDoctor(
          id: 1,
          fullName: 'Dr. Azizbek Rahimov',
          roomNumber: '102',
        ),
        specialization: const MyTicketSpecialization(id: 3, name: 'Endodontist'),
        callDeadlineAt: now.add(const Duration(seconds: 95)),
      );

      final catalog = _TestCatalogService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uz'),
          home: HomeScreen(
            queueService: _TestQueueService([calledTicket]),
            catalogService: catalog,
            reminderService: _TestReminderService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uz'),
          home: MyQueueScreen(
            queueService: _TestQueueService([calledTicket]),
            pushNotificationService: _TestPushService(),
            realtimeService: _TestRealtimeService(),
            nowProvider: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uz'),
          home: DoctorQueueScreen(
            doctor: const Doctor(
              id: 1,
              clinicId: 1,
              specializationId: 1,
              fullName: 'Dr. Azizbek Rahimov',
              roomNumber: '102',
              isActive: true,
            ),
            specialization: const Specialization(id: 1, clinicId: 1, name: 'Terapiya'),
            catalogService: catalog,
            queueService: _TestQueueService([]),
            realtimeService: _TestRealtimeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prejoin_estimated_position')), findsOneWidget);
    });
  });
}
