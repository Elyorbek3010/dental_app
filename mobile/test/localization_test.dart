import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/models/doctor.dart';
import 'package:app/models/doctor_queue.dart';
import 'package:app/models/patient_ticket.dart';
import 'package:app/models/specialization.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/screens/login_screen.dart';
import 'package:app/screens/profile_screen.dart';
import 'package:app/screens/register_screen.dart';
import 'package:app/screens/reminders_screen.dart';
import 'package:app/services/auth_controller.dart';
import 'package:app/services/auth_service.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/local_notification_service.dart';
import 'package:app/services/locale_controller.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/reminder_service.dart';
import 'package:app/services/secure_token_storage.dart';

class InMemoryTokenStorage implements SecureTokenStorage {
  String? accessToken = 'mock_jwt_token';
  String? refreshToken = 'mock_refresh_token';

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> saveAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }
}

class FakePushNotificationService implements PushNotificationService {
  @override
  bool get isFirebaseAvailable => false;

  @override
  String baseUrl = 'http://10.0.2.2:8000';

  @override
  String? currentAccessToken;

  @override
  String? Function()? accessTokenProvider;

  @override
  void setAccessToken(String? token) {
    currentAccessToken = token;
  }

  @override
  void clearAccessToken() {
    currentAccessToken = null;
  }

  @override
  Future<void> initialize({
    String? customBaseUrl,
    String? Function()? tokenProvider,
  }) async {}

  @override
  Future<NotificationSettings> requestPermissions() async {
    throw UnimplementedError();
  }

  @override
  Future<String?> getDeviceToken() async => 'fake_fcm_token';

  @override
  Future<bool> registerDevice(
    String accessToken, {
    String? fcmToken,
    String? customBaseUrl,
  }) async =>
      true;

  final StreamController<Map<String, dynamic>> _queueEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get queueEvents => _queueEventController.stream;

  @override
  void notifyQueueEvent(Map<String, dynamic> data) {
    if (!_queueEventController.isClosed) {
      _queueEventController.add(data);
    }
  }

  @override
  void handleRemoteMessage(RemoteMessage message) {
    if (PushNotificationService.isQueueEvent(message.data)) {
      notifyQueueEvent(message.data);
    }
  }

  @override
  void setupInteractionListeners() {}

  @override
  Future<void> checkInitialMessage() async {}

  @override
  void setupTokenRefreshListener() {}

  @override
  void ensureListeners() {}

  @override
  void setupForegroundMessageListener() {}

  @override
  void dispose() {
    _queueEventController.close();
  }
}

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

Widget createLocalizedTestApp({
  required Widget child,
  Locale locale = const Locale('uz'),
  LocaleController? localeController,
}) {
  if (localeController != null) {
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) {
        return MaterialApp(
          locale: localeController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: child,
        );
      },
    );
  }

  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleDoctor = Doctor(
    id: 12,
    clinicId: 1,
    specializationId: 2,
    fullName: 'Dr. Ziyoda Alimova',
    roomNumber: '104',
    isActive: true,
  );

  const sampleSpecialization = Specialization(
    id: 2,
    clinicId: 1,
    name: 'Ortodontiya',
  );

  const sampleQueue = DoctorQueue(
    id: 45,
    doctorId: 12,
    queueDate: '2026-09-28',
    isPaused: false,
    isActive: true,
  );

  group('LocaleController Tests', () {
    test('1. Loads saved locale from SharedPreferences if present', () async {
      SharedPreferences.setMockInitialValues({
        LocaleController.languageKey: 'ru',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(preferences: prefs);

      await controller.initialize();

      expect(controller.locale, const Locale('ru'));
      expect(controller.languageCode, 'ru');
    });

    test('2. Inspects device locale when no saved preference exists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(preferences: prefs);

      await controller.initialize(deviceLocale: const Locale('en', 'US'));

      expect(controller.locale, const Locale('en'));
      expect(controller.languageCode, 'en');
    });

    test('3. Falls back to Uzbek when device locale is unsupported', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(preferences: prefs);

      await controller.initialize(deviceLocale: const Locale('de', 'DE'));

      expect(controller.locale, const Locale('uz'));
      expect(controller.languageCode, 'uz');
    });

    test('4. setLocale updates current locale, notifies, and persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = LocaleController(preferences: prefs);
      await controller.initialize();

      bool notified = false;
      controller.addListener(() => notified = true);

      await controller.setLocale(const Locale('ru'));

      expect(controller.locale, const Locale('ru'));
      expect(notified, isTrue);
      expect(prefs.getString(LocaleController.languageKey), 'ru');

      await controller.setLanguageCode('en');
      expect(controller.locale, const Locale('en'));
      expect(prefs.getString(LocaleController.languageKey), 'en');
    });
  });

  group('ARB Translations & Plural Formatting', () {
    test('peopleAhead plural formatting in Uzbek', () async {
      final l10nUz = await AppLocalizations.delegate.load(const Locale('uz'));

      expect(l10nUz.peopleAhead(0), 'Oldingizda hech kim yo‘q');
      expect(l10nUz.peopleAhead(1), 'Oldingizda 1 kishi bor');
      expect(l10nUz.peopleAhead(2), 'Oldingizda 2 kishi bor');
      expect(l10nUz.peopleAhead(5), 'Oldingizda 5 kishi bor');
    });

    test('peopleAhead plural formatting in Russian', () async {
      final l10nRu = await AppLocalizations.delegate.load(const Locale('ru'));

      expect(l10nRu.peopleAhead(0), 'Перед вами никого нет');
      expect(l10nRu.peopleAhead(1), 'Перед вами 1 человек');
      expect(l10nRu.peopleAhead(2), 'Перед вами 2 человека');
      expect(l10nRu.peopleAhead(5), 'Перед вами 5 человек');
    });

    test('peopleAhead plural formatting in English', () async {
      final l10nEn = await AppLocalizations.delegate.load(const Locale('en'));

      expect(l10nEn.peopleAhead(0), 'No one ahead of you');
      expect(l10nEn.peopleAhead(1), '1 person ahead of you');
      expect(l10nEn.peopleAhead(2), '2 people ahead of you');
      expect(l10nEn.peopleAhead(5), '5 people ahead of you');
    });
  });

  group('Queue Status Localization', () {
    test('Translates all backend queue statuses correctly in UZ, RU, EN', () async {
      final l10nUz = await AppLocalizations.delegate.load(const Locale('uz'));
      final l10nRu = await AppLocalizations.delegate.load(const Locale('ru'));
      final l10nEn = await AppLocalizations.delegate.load(const Locale('en'));

      MyQueueTicket makeMyTicket(String status) => MyQueueTicket(
            id: 1,
            queueId: 45,
            ticketNumber: 3,
            status: status,
            createdAt: DateTime.now(),
            peopleAhead: 0,
            doctor: const MyTicketDoctor(id: 12, fullName: 'Dr. Test'),
            specialization: const MyTicketSpecialization(id: 2, name: 'Dental'),
          );

      QueueTicket makeQueueTicket(String status) => QueueTicket(
            id: 1,
            queueId: 45,
            ticketNumber: 3,
            queuePosition: 1,
            patientName: 'Test Patient',
            source: 'ONLINE',
            status: status,
            createdAt: DateTime.now(),
          );

      final statuses = [
        'WAITING',
        'CALLED',
        'SERVING',
        'COMPLETED',
        'SKIPPED',
        'CANCELLED',
      ];

      final expectedUz = [
        'Kutilmoqda',
        'Navbatingiz keldi',
        'Qabul davom etmoqda',
        'Yakunlandi',
        'O‘tkazib yuborildi',
        'Bekor qilingan',
      ];

      final expectedRu = [
        'Ожидание',
        'Ваша очередь',
        'Идет прием',
        'Завершен',
        'Пропущен',
        'Отменен',
      ];

      final expectedEn = [
        'Waiting',
        'Your turn',
        'In progress',
        'Completed',
        'Skipped',
        'Cancelled',
      ];

      for (int i = 0; i < statuses.length; i++) {
        final myTicket = makeMyTicket(statuses[i]);
        expect(myTicket.localizedStatus(l10nUz), expectedUz[i]);
        expect(myTicket.localizedStatus(l10nRu), expectedRu[i]);
        expect(myTicket.localizedStatus(l10nEn), expectedEn[i]);

        final queueTicket = makeQueueTicket(statuses[i]);
        expect(queueTicket.localizedStatus(l10nUz), expectedUz[i]);
        expect(queueTicket.localizedStatus(l10nRu), expectedRu[i]);
        expect(queueTicket.localizedStatus(l10nEn), expectedEn[i]);
      }
    });
  });

  group('UI Screen Localization Widget Tests', () {
    late AuthController authController;

    setUp(() {
      final mockAuthClient = MockClient((request) async => http.Response('{}', 200));
      final authService = AuthService(
        httpClient: mockAuthClient,
        tokenStorage: InMemoryTokenStorage(),
        pushService: FakePushNotificationService(),
      );
      authController = AuthController(authService: authService);
    });

    testWidgets('LoginScreen renders correctly in Russian and English', (tester) async {
      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('ru'),
          child: LoginScreen(authController: authController),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Войти'), findsOneWidget);
      expect(find.text('Номер телефона'), findsOneWidget);
      expect(find.text('Пароль'), findsOneWidget);

      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('en'),
          child: LoginScreen(authController: authController),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Log In'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('RegisterScreen renders correctly in Russian and English', (tester) async {
      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('ru'),
          child: RegisterScreen(authController: authController),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Создание аккаунта пациента'), findsOneWidget);
      expect(find.text('Имя и фамилия'), findsOneWidget);
      expect(find.text('Зарегистрироваться'), findsOneWidget);

      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('en'),
          child: RegisterScreen(authController: authController),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Patient Account'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Register'), findsNWidgets(2));
    });

    testWidgets('RemindersScreen renders correctly in Russian and English', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final reminderService = ReminderService(
        notificationService: FakeLocalNotificationService(),
        initialPreferences: prefs,
      );

      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('ru'),
          child: RemindersScreen(reminderService: reminderService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Мои напоминания'), findsOneWidget);
      expect(find.text('Пока нет напоминаний'), findsOneWidget);

      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('en'),
          child: RemindersScreen(reminderService: reminderService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Reminders'), findsOneWidget);
      expect(find.text('No reminders yet'), findsOneWidget);
    });

    testWidgets('DoctorQueueScreen renders correctly in Russian and English', (tester) async {
      final mockCatalogClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleQueue.toJson()), 200);
      });
      final catalogService = CatalogService(
        httpClient: mockCatalogClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('ru'),
          child: DoctorQueueScreen(
            doctor: sampleDoctor,
            specialization: sampleSpecialization,
            catalogService: catalogService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Информация об очереди'), findsWidgets);
      expect(find.text('Занять очередь'), findsOneWidget);

      await tester.pumpWidget(
        createLocalizedTestApp(
          locale: const Locale('en'),
          child: DoctorQueueScreen(
            doctor: sampleDoctor,
            specialization: sampleSpecialization,
            catalogService: catalogService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Queue Details'), findsOneWidget);
      expect(find.text('Join Queue'), findsOneWidget);
    });

    testWidgets('ProfileScreen language selector updates locale immediately', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localeController = LocaleController(preferences: prefs);
      await localeController.initialize(deviceLocale: const Locale('uz'));

      await tester.pumpWidget(
        createLocalizedTestApp(
          localeController: localeController,
          child: ProfileScreen(
            localeController: localeController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially in Uzbek
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Ilova tili'), findsOneWidget);
      expect(find.text('O‘zbekcha'), findsOneWidget);

      // Tap Russian
      await tester.tap(find.text('Русский'));
      await tester.pumpAndSettle();

      // UI should immediately rebuild in Russian
      expect(localeController.languageCode, 'ru');
      expect(find.text('Профиль'), findsOneWidget);
      expect(find.text('Язык приложения'), findsOneWidget);

      // Tap English
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      // UI should immediately rebuild in English
      expect(localeController.languageCode, 'en');
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('App Language'), findsOneWidget);
    });
  });

  group('Backend Dynamic Multilingual Headers (CatalogService & QueueService)', () {
    test('CatalogService includes Accept-Language header matching LocaleController', () async {
      SharedPreferences.setMockInitialValues({
        LocaleController.languageKey: 'uz',
      });
      final prefs = await SharedPreferences.getInstance();
      final localeController = LocaleController(preferences: prefs);
      await localeController.initialize(); // uz

      final recordedHeaders = <String>[];
      final mockClient = MockClient((request) async {
        recordedHeaders.add(request.headers['Accept-Language'] ?? 'missing');
        if (request.url.path.endsWith('/specializations')) {
          final jsonStr = jsonEncode([
            {'id': 1, 'clinic_id': 1, 'name': 'Ortodontiya'},
          ]);
          return http.Response.bytes(
            utf8.encode(jsonStr),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('[]', 200);
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
        localeController: localeController,
      );

      // Default: uz
      await catalogService.fetchSpecializations();
      expect(recordedHeaders.last, 'uz');

      // Change to ru
      await localeController.setLanguageCode('ru');
      await catalogService.fetchSpecializations();
      expect(recordedHeaders.last, 'ru');

      // Change to en
      await localeController.setLanguageCode('en');
      await catalogService.fetchSpecializations();
      expect(recordedHeaders.last, 'en');
    });

    test('QueueService includes Accept-Language header matching LocaleController', () async {
      SharedPreferences.setMockInitialValues({
        LocaleController.languageKey: 'ru',
      });
      final prefs = await SharedPreferences.getInstance();
      final localeController = LocaleController(preferences: prefs);
      await localeController.initialize();

      final recordedHeaders = <String>[];
      final mockClient = MockClient((request) async {
        recordedHeaders.add(request.headers['Accept-Language'] ?? 'missing');
        final jsonStr = jsonEncode({
          'id': 100,
          'queue_id': 45,
          'ticket_number': 5,
          'status': 'WAITING',
          'created_at': DateTime.now().toIso8601String(),
          'people_ahead': 2,
          'doctor': {'id': 1, 'full_name': 'Dr. Test'},
          'specialization': {'id': 1, 'name': 'Ортодонтия'},
        });
        return http.Response.bytes(
          utf8.encode(jsonStr),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
        localeController: localeController,
      );

      final ticket = await queueService.getMyTicket();
      expect(recordedHeaders.last, 'ru');
      expect(ticket, isNotNull);
      expect(ticket!.specialization.name, 'Ортодонтия');

      await localeController.setLanguageCode('en');
      await queueService.getMyTicket();
      expect(recordedHeaders.last, 'en');
    });
  });
}

