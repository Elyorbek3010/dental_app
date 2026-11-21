import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/models/doctor.dart';
import 'package:app/models/doctor_queue.dart';
import 'package:app/models/patient_ticket.dart';
import 'package:app/models/specialization.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/reminder_service.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/models/reminder.dart';

class _StubCatalogService extends CatalogService {
  _StubCatalogService(this.queue);
  final DoctorQueue queue;

  @override
  Future<DoctorQueue> fetchDoctorQueue(int doctorId) async => queue;
}

class _NoopRealtimeService extends QueueRealtimeService {
  @override
  Future<void> connectForConsumer(Object consumer, int clinicId) async {}

  @override
  void disconnectConsumer(Object consumer) {}
}

class _StubQueueService extends QueueService {
  _StubQueueService(this.tickets);
  final List<MyQueueTicket> tickets;

  @override
  Future<List<MyQueueTicket>> getMyTickets({bool includeSkipped = false}) async =>
      tickets;
}

class _NoopPushService extends Fake implements PushNotificationService {
  @override
  bool get isFirebaseAvailable => false;

  @override
  Stream<Map<String, dynamic>> get queueEvents => const Stream.empty();

  @override
  void ensureListeners() {}
}

class _EmptyReminderService extends Fake implements ReminderService {
  @override
  Future<List<Reminder>> getReminders() async => <Reminder>[];
}

void main() {
  final doctor = Doctor(
    id: 1,
    clinicId: 1,
    specializationId: 1,
    fullName: 'Dr. Farrux Nightshift',
    roomNumber: '101',
    isActive: true,
  );
  final specialization = Specialization(
    id: 1,
    clinicId: 1,
    name: 'Терапевтическая стоматология',
  );

  DoctorQueue makeQueue({required String shiftStatus, bool isPaused = false}) {
    return DoctorQueue.fromJson({
      'id': 42,
      'queue_id': 42,
      'doctor_id': 1,
      'queue_date': '2026-11-21',
      'is_paused': isPaused,
      'is_active': true,
      'shift_status': shiftStatus,
      'waiting_count': 4,
      'called_count': 1,
      'serving_count': 1,
      'estimated_position_if_joined': 7,
    });
  }

  Future<void> pumpResponsive(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required Locale locale,
    required ThemeData theme,
    required Widget child,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          theme: theme,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('ru'), Locale('uz')],
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'DoctorQueueScreen Russian & Uzbek CLOSING layout never collapses text vertically or overlaps across widths and scales',
    (tester) async {
      final locales = [const Locale('ru'), const Locale('uz'), const Locale('en')];
      final widths = [320.0, 360.0, 390.0, 412.0, 480.0];
      final scales = [1.0, 1.3, 1.5];
      final themes = [AppTheme.lightTheme, AppTheme.darkTheme];

      for (final locale in locales) {
        for (final width in widths) {
          for (final scale in scales) {
            final theme = themes[(width.toInt() + scales.indexOf(scale)) % 2];
            await pumpResponsive(
              tester,
              size: Size(width, 800),
              textScale: scale,
              locale: locale,
              theme: theme,
              child: DoctorQueueScreen(
                doctor: doctor,
                specialization: specialization,
                catalogService: _StubCatalogService(makeQueue(shiftStatus: 'CLOSING')),
                realtimeService: _NoopRealtimeService(),
              ),
            );

            expect(
              tester.takeException(),
              isNull,
              reason: 'Unexpected layout error at locale=$locale width=$width scale=$scale',
            );

            final headerFinder = find.byKey(const Key('doctor_queue_today_header'));
            final chipFinder = find.byKey(const Key('doctor_queue_status_chip'));
            final bannerFinder = find.byKey(const Key('doctor_queue_notice_banner'));
            final buttonFinder = find.byKey(const Key('doctor_queue_join_button'));

            expect(headerFinder, findsOneWidget);
            expect(chipFinder, findsOneWidget);
            expect(bannerFinder, findsOneWidget);
            expect(buttonFinder, findsOneWidget);

            final headerRect = tester.getRect(headerFinder);
            final chipRect = tester.getRect(chipFinder);
            final bannerRect = tester.getRect(bannerFinder);
            final buttonRect = tester.getRect(buttonFinder);

            // Heading must always get usable horizontal width (never 15px 1-char vertical strip)
            expect(
              headerRect.width,
              greaterThanOrEqualTo(150.0),
              reason: 'Heading too narrow at locale=$locale width=$width scale=$scale',
            );
            // Heading must stay reasonably compact vertically (never stacked one letter per line)
            expect(
              headerRect.height,
              lessThanOrEqualTo(115.0 * scale),
              reason: 'Heading unexpectedly tall at locale=$locale width=$width scale=$scale',
            );
            // No overlap between heading, status chip, and warning banner
            expect(headerRect.overlaps(chipRect), isFalse);
            expect(headerRect.overlaps(bannerRect), isFalse);
            expect(chipRect.overlaps(bannerRect), isFalse);
            expect(bannerRect.top, greaterThanOrEqualTo(chipRect.bottom - 0.5));
            // Bottom action button remains inside the viewport
            expect(buttonRect.bottom, lessThanOrEqualTo(800.0));
          }
        }
      }
    },
  );

  testWidgets(
    'DoctorQueueScreen handles multi-window 280px narrow configuration in Russian dark mode',
    (tester) async {
      await pumpResponsive(
        tester,
        size: const Size(280, 640),
        textScale: 1.3,
        locale: const Locale('ru'),
        theme: AppTheme.darkTheme,
        child: DoctorQueueScreen(
          doctor: doctor,
          specialization: specialization,
          catalogService: _StubCatalogService(makeQueue(shiftStatus: 'CLOSING')),
          realtimeService: _NoopRealtimeService(),
        ),
      );

      expect(tester.takeException(), isNull);
      final headerRect = tester.getRect(find.byKey(const Key('doctor_queue_today_header')));
      final chipRect = tester.getRect(find.byKey(const Key('doctor_queue_status_chip')));
      expect(headerRect.width, greaterThanOrEqualTo(170.0));
      expect(chipRect.top, greaterThanOrEqualTo(headerRect.bottom));
    },
  );

  testWidgets(
    'Related HomeScreen and MyQueueScreen status badges do not overflow at 320px 1.5x Russian',
    (tester) async {
      final ticket = MyQueueTicket.fromJson({
        'id': 11,
        'queue_id': 42,
        'ticket_number': 7,
        'queue_position': 3,
        'status': 'WAITING',
        'created_at': '2026-11-21T03:00:00Z',
        'people_ahead': 2,
        'doctor': {'id': 1, 'full_name': 'Dr. Farrux Nightshift', 'room_number': '101', 'clinic_id': 1},
        'specialization': {'id': 1, 'name': 'Терапевтическая стоматология'},
        'is_queue_paused': true,
      });

      await pumpResponsive(
        tester,
        size: const Size(320, 740),
        textScale: 1.5,
        locale: const Locale('ru'),
        theme: AppTheme.lightTheme,
        child: HomeScreen(
          queueService: _StubQueueService([ticket]),
          reminderService: _EmptyReminderService(),
          pushNotificationService: _NoopPushService(),
          realtimeService: _NoopRealtimeService(),
          onNavigateToQueue: () {},
          onNavigateToReminders: () {},
        ),
      );
      expect(tester.takeException(), isNull);

      await pumpResponsive(
        tester,
        size: const Size(320, 740),
        textScale: 1.5,
        locale: const Locale('ru'),
        theme: AppTheme.darkTheme,
        child: MyQueueScreen(
          queueService: _StubQueueService([ticket]),
          pushNotificationService: _NoopPushService(),
          realtimeService: _NoopRealtimeService(),
          isActiveTab: true,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
