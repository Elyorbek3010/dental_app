import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/main.dart';
import 'package:app/models/patient_ticket.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/screens/patient_shell.dart';
import 'package:app/services/auth_controller.dart';
import 'package:app/services/auth_service.dart';
import 'package:app/services/locale_controller.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/secure_token_storage.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/empty_state_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeQueueService extends QueueService {
  @override
  Future<MyQueueTicket?> getMyTicket() async => null;

  @override
  Future<List<MyQueueTicket>> getMyTickets() async => [];
}

class InMemoryTokenStorage implements SecureTokenStorage {
  String? accessToken = 'valid_test_jwt';
  String? refreshToken = 'valid_test_refresh';

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

class FakeRealtimeService extends QueueRealtimeService {
  FakeRealtimeService() : super(channelFactory: (_) => throw UnimplementedError());

  final _testEventController = StreamController<QueueUpdatedEvent>.broadcast();

  @override
  Stream<QueueUpdatedEvent> get events => _testEventController.stream;

  int? connectedClinicId;
  bool isConnectedValue = false;

  @override
  bool get isConnected => isConnectedValue;

  @override
  int? get activeClinicId => connectedClinicId;

  @override
  void connect(int clinicId) {
    connectedClinicId = clinicId;
    isConnectedValue = true;
  }

  @override
  void disconnect() {
    connectedClinicId = null;
    isConnectedValue = false;
  }

  void emitQueueUpdate({int? clinicId, int? queueId, String type = 'queue_updated'}) {
    _testEventController.add(
      QueueUpdatedEvent(
        type: type,
        clinicId: clinicId ?? connectedClinicId,
        queueId: queueId,
      ),
    );
  }

  @override
  void dispose() {
    _testEventController.close();
    super.dispose();
  }
}

class TestPushNotificationService implements PushNotificationService {
  @override
  bool get isFirebaseAvailable => false;

  @override
  String baseUrl = 'http://10.0.2.2:8000';

  @override
  String? currentAccessToken = 'valid_test_jwt';

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
  }) async {
    ensureListeners();
  }

  @override
  Future<NotificationSettings> requestPermissions() async {
    throw UnimplementedError();
  }

  @override
  Future<String?> getDeviceToken() async => 'fake_token';

  @override
  Future<bool> registerDevice(
    String accessToken, {
    String? fcmToken,
    String? customBaseUrl,
  }) async =>
      true;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get queueEvents => _controller.stream;

  @override
  void notifyQueueEvent(Map<String, dynamic> data) {
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  @override
  void handleRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final eventType = PushNotificationService.parseQueueEventType(data, message.notification);
    if (eventType != null) {
      final payload = Map<String, dynamic>.from(data);
      payload['type'] ??= 'QUEUE_$eventType';
      notifyQueueEvent(payload);
    }
  }

  bool ensureListenersCalled = false;

  @override
  void ensureListeners() {
    ensureListenersCalled = true;
  }

  @override
  void setupInteractionListeners() {}

  @override
  Future<void> checkInitialMessage() async {}

  @override
  void setupTokenRefreshListener() {}

  @override
  void setupForegroundMessageListener() {}

  @override
  void dispose() {
    _controller.close();
  }
}

Widget createTestApp(Widget child, [Locale locale = const Locale('uz')]) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('uz'),
      Locale('ru'),
      Locale('en'),
    ],
    home: child,
  );
}

void main() {
  group('STEP 14 — Integration & Realtime Tests', () {
    testWidgets(
        'KNOWN ISSUE #1 RESOLVED: Reception check-in WebSocket event automatically updates MyQueueScreen to checked-in state without manual refresh',
        (WidgetTester tester) async {
      int requestCount = 0;
      bool isCheckedInOnBackend = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets' ||
            request.url.path == '/api/queues/my-ticket') {
          requestCount++;
          final ticketJson = {
            'id': 101,
            'queue_id': 5,
            'ticket_number': 14,
            'status': 'WAITING',
            'created_at': DateTime.now().toIso8601String(),
            'people_ahead': 2,
            'clinic_id': 1,
            'doctor': {
              'id': 3,
              'clinic_id': 1,
              'full_name': 'Dr. Zokirov',
              'room_number': '101',
            },
            'specialization': {
              'id': 1,
              'name': 'Terapiya',
            },
            'checked_in_at': isCheckedInOnBackend
                ? DateTime.now().toIso8601String()
                : null,
            'check_in_method': isCheckedInOnBackend ? 'RECEPTION' : null,
          };
          return http.Response(
            jsonEncode(
              request.url.path == '/api/queues/my-tickets'
                  ? [ticketJson]
                  : ticketJson,
            ),
            200,
          );
        }
        return http.Response('{"detail": "Not found"}', 404);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );
      final realtimeService = FakeRealtimeService();
      final pushService = TestPushNotificationService();

      await tester.pumpWidget(
        createTestApp(
          MyQueueScreen(
            queueService: queueService,
            realtimeService: realtimeService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially NOT checked in: QR check-in button should be visible
      expect(find.text('№14'), findsOneWidget);
      expect(find.byKey(const Key('qr_checkin_button')), findsOneWidget);
      expect(find.byKey(const Key('my_ticket_checkin_status_text')), findsOneWidget);
      expect(requestCount, 1);

      // Now receptionist checks patient in on PostgreSQL backend:
      isCheckedInOnBackend = true;

      // Backend publishes WebSocket update for queue_id 5 in clinic 1:
      realtimeService.emitQueueUpdate(clinicId: 1, queueId: 5);

      // Pump to process microtasks and HTTP response
      await tester.pump();
      await tester.pumpAndSettle();

      // VERIFY: MyQueueScreen silently refetched and automatically updated state!
      expect(requestCount, 2);
      expect(find.byKey(const Key('my_ticket_checkin_status_text')), findsOneWidget);
      expect(find.byKey(const Key('qr_checkin_button')), findsNothing);

      realtimeService.dispose();
      pushService.dispose();
    });

    testWidgets(
        'KNOWN ISSUE #2 RESOLVED: App resuming from background triggers silent ticket refresh',
        (WidgetTester tester) async {
      int requestCount = 0;
      String currentStatus = 'WAITING';

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets' ||
            request.url.path == '/api/queues/my-ticket') {
          requestCount++;
          final ticketJson = {
            'id': 102,
            'queue_id': 5,
            'ticket_number': 22,
            'status': currentStatus,
            'created_at': DateTime.now().toIso8601String(),
            'people_ahead': currentStatus == 'CALLED' ? 0 : 3,
            'clinic_id': 1,
            'doctor': {
              'id': 3,
              'clinic_id': 1,
              'full_name': 'Dr. Aliyev',
              'room_number': '105',
            },
            'specialization': {
              'id': 1,
              'name': 'Ortopediya',
            },
            'checked_in_at': DateTime.now().toIso8601String(),
            'check_in_method': 'RECEPTION',
          };
          return http.Response(
            jsonEncode(
              request.url.path == '/api/queues/my-tickets'
                  ? [ticketJson]
                  : ticketJson,
            ),
            200,
          );
        }
        return http.Response('{"detail": "Not found"}', 404);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );
      final realtimeService = FakeRealtimeService();
      final pushService = TestPushNotificationService();

      await tester.pumpWidget(
        createTestApp(
          MyQueueScreen(
            queueService: queueService,
            realtimeService: realtimeService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('№22'), findsOneWidget);
      expect(requestCount, 1);

      // Doctor calls patient while app was in background:
      currentStatus = 'CALLED';

      // Simulate Android lifecycle event: App resumes to foreground
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.pump();
      await tester.pumpAndSettle();

      // VERIFY: Resume automatically refetched ticket silently and updated screen to CALLED state
      expect(requestCount, 2);
      expect(find.byKey(const Key('called_banner')), findsOneWidget);

      realtimeService.dispose();
      pushService.dispose();
    });

    testWidgets(
        'Ticket Completion Transition: When doctor completes ticket, MyQueueScreen silently renders empty state',
        (WidgetTester tester) async {
      int requestCount = 0;
      bool isCompleted = false;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets' ||
            request.url.path == '/api/queues/my-ticket') {
          requestCount++;
          if (isCompleted) {
            if (request.url.path == '/api/queues/my-tickets') {
              return http.Response(jsonEncode([]), 200);
            }
            return http.Response(jsonEncode({'detail': 'No active queue ticket found'}), 404);
          }
          final ticketJson = {
            'id': 103,
            'queue_id': 5,
            'ticket_number': 35,
            'status': 'SERVING',
            'created_at': DateTime.now().toIso8601String(),
            'people_ahead': 0,
            'clinic_id': 1,
            'doctor': {
              'id': 3,
              'clinic_id': 1,
              'full_name': 'Dr. Karimov',
              'room_number': '102',
            },
            'specialization': {
              'id': 1,
              'name': 'Terapiya',
            },
            'checked_in_at': DateTime.now().toIso8601String(),
            'check_in_method': 'QR',
          };
          return http.Response(
            jsonEncode(
              request.url.path == '/api/queues/my-tickets'
                  ? [ticketJson]
                  : ticketJson,
            ),
            200,
          );
        }
        return http.Response('{"detail": "Not found"}', 404);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );
      final pushService = TestPushNotificationService();
      final realtimeService = FakeRealtimeService();

      await tester.pumpWidget(
        createTestApp(
          MyQueueScreen(
            queueService: queueService,
            realtimeService: realtimeService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('№35'), findsOneWidget);
      expect(find.byKey(const Key('serving_banner')), findsOneWidget);

      // Doctor completes appointment
      isCompleted = true;

      // Realtime event arrives
      realtimeService.emitQueueUpdate(clinicId: 1, queueId: 5);

      await tester.pump();
      await tester.pumpAndSettle();

      // Ticket is gone -> empty state automatically renders
      expect(find.text('Faol navbatingiz yo‘q'), findsOneWidget);
      expect(find.byType(EmptyStateCard), findsOneWidget);
      expect(find.byKey(const Key('my_queue_refresh_indicator_empty')), findsOneWidget);
      expect(requestCount, 2);

      realtimeService.dispose();
      pushService.dispose();
    });

    testWidgets(
        'LOCALIZATION REGRESSION: Patient remains authenticated through UZ -> RU -> EN -> UZ switches',
        (WidgetTester tester) async {
      final tokenStorage = InMemoryTokenStorage();
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 77,
              'phone': '+998901234567',
              'full_name': 'Rustam Karimov',
              'role': 'PATIENT',
              'clinic_id': 1,
              'is_active': true,
            }),
            200,
          );
        }
        if (request.url.path == '/api/queues/my-ticket') {
          return http.Response(jsonEncode({'detail': 'No active queue ticket found'}), 404);
        }
        return http.Response('{}', 200);
      });

      SharedPreferences.setMockInitialValues({'app_locale': 'uz'});
      final prefs = await SharedPreferences.getInstance();
      final localeController = LocaleController(preferences: prefs);

      final fakeRealtimeService = FakeRealtimeService();
      QueueRealtimeService.instance = fakeRealtimeService;

      final fakeQueueService = FakeQueueService();
      QueueService.instance = fakeQueueService;

      final pushService = TestPushNotificationService();
      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: pushService,
      );

      final authController = AuthController(authService: authService);

      await tester.pumpWidget(
        MyApp(
          authController: authController,
          localeController: localeController,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial State: Uzbek locale, session restored, PatientShell active
      expect(find.byType(PatientShell), findsOneWidget);
      expect(authController.isAuthenticated, isTrue);
      expect(find.text('Asosiy'), findsOneWidget);
      expect(find.text('Xavfsiz sessiya tekshirilmoqda...'), findsNothing);

      // 2. Switch to RU
      await localeController.setLanguageCode('ru');
      await tester.pumpAndSettle();
      expect(find.byType(PatientShell), findsOneWidget);
      expect(find.text('Главная'), findsOneWidget);
      expect(authController.isAuthenticated, isTrue);

      // 3. Switch to EN
      await localeController.setLanguageCode('en');
      await tester.pumpAndSettle();
      expect(find.byType(PatientShell), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(authController.isAuthenticated, isTrue);

      // 4. Switch back to UZ
      await localeController.setLanguageCode('uz');
      await tester.pumpAndSettle();
      expect(find.byType(PatientShell), findsOneWidget);
      expect(find.text('Asosiy'), findsOneWidget);
      expect(authController.isAuthenticated, isTrue);

      fakeRealtimeService.dispose();
      pushService.dispose();
    });
  });
}
