import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/secure_token_storage.dart';
import 'package:app/theme/app_theme.dart';

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

class TestPushNotificationService implements PushNotificationService {
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
  }) async {
    ensureListeners();
  }

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
    debugPrint('FCM foreground message received');
    final data = message.data;
    final eventType = PushNotificationService.parseQueueEventType(data, message.notification);
    if (eventType != null) {
      debugPrint('Queue event recognized: $eventType');
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

Widget localizedApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: const Locale('uz'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Backend Real FCM Payload Classification', () {
    test('Recognizes exact real backend data payloads', () {
      // 1. Exact backend payload for QUEUE_JOINED
      final joinedPayload = {
        'type': 'QUEUE_JOINED',
        'ticket_id': '101',
        'ticket_number': '12',
        'queue_id': '1',
      };
      expect(PushNotificationService.parseQueueEventType(joinedPayload), equals('JOINED'));
      expect(PushNotificationService.isQueueEvent(joinedPayload), isTrue);

      // 2. Exact backend payload for QUEUE_CALLED
      final calledPayload = {
        'type': 'QUEUE_CALLED',
        'ticket_id': '101',
        'room_number': '104',
        'queue_id': '1',
      };
      expect(PushNotificationService.parseQueueEventType(calledPayload), equals('CALLED'));
      expect(PushNotificationService.isQueueEvent(calledPayload), isTrue);

      // 3. Exact backend payload for QUEUE_MISSED_TURN
      final missedTurnPayload = {
        'type': 'QUEUE_MISSED_TURN',
        'ticket_id': '101',
        'queue_id': '1',
      };
      expect(PushNotificationService.parseQueueEventType(missedTurnPayload), equals('MISSED_TURN'));
      expect(PushNotificationService.isQueueEvent(missedTurnPayload), isTrue);

      // 4. Exact backend payload for QUEUE_PAUSED
      final pausedPayload = {
        'type': 'QUEUE_PAUSED',
        'queue_id': '1',
      };
      expect(PushNotificationService.parseQueueEventType(pausedPayload), equals('PAUSED'));
      expect(PushNotificationService.isQueueEvent(pausedPayload), isTrue);

      // 5. Exact backend payload for QUEUE_RESUMED
      final resumedPayload = {
        'type': 'QUEUE_RESUMED',
        'queue_id': '1',
      };
      expect(PushNotificationService.parseQueueEventType(resumedPayload), equals('RESUMED'));
      expect(PushNotificationService.isQueueEvent(resumedPayload), isTrue);

      // 6. Exact backend payload for QUEUE_COMPLETED
      final completedPayload = {
        'type': 'QUEUE_COMPLETED',
        'ticket_id': '101',
        'queue_id': '1',
      };
      expect(PushNotificationService.parseQueueEventType(completedPayload), equals('COMPLETED'));
      expect(PushNotificationService.isQueueEvent(completedPayload), isTrue);

      // 7. Exact backend payload for QUEUE_APPROACHING
      final approachingPayload = {
        'type': 'QUEUE_APPROACHING',
        'ticket_id': '101',
        'queue_id': '1',
      };
      expect(PushNotificationService.parseQueueEventType(approachingPayload), equals('APPROACHING'));
      expect(PushNotificationService.isQueueEvent(approachingPayload), isTrue);
    });

    test('Fallback to notification text when data payload is stripped by OEM battery managers', () {
      const calledNotif = RemoteNotification(
        title: 'Dental Queue',
        body: 'Navbatingiz keldi! Iltimos, 104-xonaga kiring.',
      );
      expect(PushNotificationService.parseQueueEventType({}, calledNotif), equals('CALLED'));

      const approachingNotif = RemoteNotification(
        title: 'Dental Queue',
        body: 'Navbatingiz yaqinlashmoqda. Oldingizda 3 kishi qoldi.',
      );
      expect(PushNotificationService.parseQueueEventType({}, approachingNotif), equals('APPROACHING'));

      const completedNotif = RemoteNotification(
        title: 'Dental Queue',
        body: 'Tashrifingiz yakunlandi. Bizni tanlaganingiz uchun rahmat. Tez orada ko‘rishguncha! 👋',
      );
      expect(PushNotificationService.parseQueueEventType({}, completedNotif), equals('COMPLETED'));
    });

    test('Non-queue payloads return null and isQueueEvent is false', () {
      expect(PushNotificationService.parseQueueEventType({}), isNull);
      expect(PushNotificationService.isQueueEvent({}), isFalse);
      expect(PushNotificationService.parseQueueEventType({'type': 'PROMOTIONAL_SALE'}), isNull);
    });
  });

  group('MyQueueScreen Real FCM Lifecycle Refresh', () {
    late TestPushNotificationService pushService;

    setUp(() {
      pushService = TestPushNotificationService();
    });

    tearDown(() {
      pushService.dispose();
    });

    final waitingTicketJson = {
      'id': 101,
      'queue_id': 1,
      'ticket_number': 12,
      'status': 'WAITING',
      'created_at': '2026-09-28T10:00:00Z',
      'checked_in_at': '2026-09-28T10:05:00Z',
      'check_in_method': 'QR',
      'people_ahead': 3,
      'doctor': {
        'id': 12,
        'full_name': 'Dr. Ziyoda Alimova',
        'room_number': '104',
      },
      'specialization': {
        'id': 2,
        'name': 'Ortodontiya',
      },
    };

    final calledTicketJson = {
      'id': 101,
      'queue_id': 1,
      'ticket_number': 12,
      'status': 'CALLED',
      'created_at': '2026-09-28T10:00:00Z',
      'checked_in_at': '2026-09-28T10:05:00Z',
      'check_in_method': 'QR',
      'people_ahead': 0,
      'doctor': {
        'id': 12,
        'full_name': 'Dr. Ziyoda Alimova',
        'room_number': '104',
      },
      'specialization': {
        'id': 2,
        'name': 'Ortodontiya',
      },
    };

    testWidgets('Real foreground RemoteMessage for QUEUE_CALLED causes automatic ticket refresh to CALLED UI',
        (WidgetTester tester) async {
      int fetchCount = 0;
      Map<String, dynamic>? currentBackendTicket = waitingTicketJson;

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          return http.Response(
            jsonEncode(currentBackendTicket != null ? [currentBackendTicket] : []),
            200,
          );
        }
        if (request.url.path == '/api/queues/my-ticket') {
          fetchCount++;
          if (currentBackendTicket != null) {
            return http.Response(jsonEncode(currentBackendTicket), 200);
          }
          return http.Response(jsonEncode({'detail': 'No active queue ticket found'}), 404);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(
          MyQueueScreen(
            queueService: queueService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure listeners was actively wired on initialization
      expect(pushService.ensureListenersCalled, isTrue);

      // Initial state: WAITING
      expect(fetchCount, equals(1));
      expect(find.text('№12'), findsOneWidget);
      expect(find.text('Kutilmoqda'), findsOneWidget);
      expect(find.byKey(const Key('called_banner')), findsNothing);

      // Backend advances state to CALLED
      currentBackendTicket = calledTicketJson;

      // Real RemoteMessage arrived in foreground with exact backend payload
      const realFcmMessage = RemoteMessage(
        data: {
          'type': 'QUEUE_CALLED',
          'ticket_id': '101',
          'room_number': '104',
          'queue_id': '1',
        },
        notification: RemoteNotification(
          title: 'Dental Queue',
          body: 'Navbatingiz keldi! Iltimos, 104-xonaga kiring.',
        ),
      );

      pushService.handleRemoteMessage(realFcmMessage);

      await tester.pump();
      await tester.pumpAndSettle();

      // Auto-refreshed via GET /api/queues/my-ticket
      expect(fetchCount, equals(2));

      // CALLED UI automatically displayed
      expect(find.byKey(const Key('called_banner')), findsOneWidget);
      expect(find.byKey(const Key('called_banner_title')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('called_banner')),
          matching: find.textContaining('Xona: 104'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Real foreground RemoteMessage for QUEUE_COMPLETED causes active ticket to disappear',
        (WidgetTester tester) async {
      int fetchCount = 0;
      Map<String, dynamic>? currentBackendTicket = calledTicketJson;

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          return http.Response(
            jsonEncode(currentBackendTicket != null ? [currentBackendTicket] : []),
            200,
          );
        }
        if (request.url.path == '/api/queues/my-ticket') {
          fetchCount++;
          if (currentBackendTicket != null) {
            return http.Response(jsonEncode(currentBackendTicket), 200);
          }
          return http.Response(jsonEncode({'detail': 'No active queue ticket found'}), 404);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(
          MyQueueScreen(
            queueService: queueService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetchCount, equals(1));
      expect(find.byKey(const Key('called_banner')), findsOneWidget);

      // Doctor completes appointment -> GET /my-ticket returns 404
      currentBackendTicket = null;

      // Real FCM message arrives with exact backend payload
      const realFcmMessage = RemoteMessage(
        data: {
          'type': 'QUEUE_COMPLETED',
          'ticket_id': '101',
          'queue_id': '1',
        },
        notification: RemoteNotification(
          title: 'Dental Queue',
          body: 'Tashrifingiz yakunlandi. Bizni tanlaganingiz uchun rahmat. Tez orada ko‘rishguncha! 👋',
        ),
      );

      pushService.handleRemoteMessage(realFcmMessage);

      await tester.pump();
      await tester.pumpAndSettle();

      expect(fetchCount, equals(2));
      expect(find.byKey(const Key('called_banner')), findsNothing);
      expect(find.text("Faol navbatingiz yo‘q"), findsOneWidget);
      expect(find.text('Navbatga yozilish'), findsOneWidget);
    });

    testWidgets('QUEUE_APPROACHING & QUEUE_MISSED_TURN refresh ticket data automatically',
        (WidgetTester tester) async {
      int fetchCount = 0;
      Map<String, dynamic> currentTicket = Map.from(waitingTicketJson)..['people_ahead'] = 4;

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          return http.Response(jsonEncode([currentTicket]), 200);
        }
        if (request.url.path == '/api/queues/my-ticket') {
          fetchCount++;
          return http.Response(jsonEncode(currentTicket), 200);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(
          MyQueueScreen(
            queueService: queueService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetchCount, equals(1));
      expect(find.text('Oldingizda 4 kishi bor'), findsOneWidget);

      // Simulate real APPROACHING RemoteMessage
      currentTicket = Map.from(waitingTicketJson)..['people_ahead'] = 3;
      pushService.handleRemoteMessage(const RemoteMessage(
        data: {
          'type': 'QUEUE_APPROACHING',
          'ticket_id': '101',
          'queue_id': '1',
        },
      ));

      await tester.pump();
      await tester.pumpAndSettle();

      expect(fetchCount, equals(2));
      expect(find.text('Oldingizda 3 kishi bor'), findsOneWidget);

      // Simulate real MISSED TURN RemoteMessage
      currentTicket = Map.from(waitingTicketJson)..['people_ahead'] = 7;
      pushService.handleRemoteMessage(const RemoteMessage(
        data: {
          'type': 'QUEUE_MISSED_TURN',
          'ticket_id': '101',
          'queue_id': '1',
        },
      ));

      await tester.pump();
      await tester.pumpAndSettle();

      expect(fetchCount, equals(3));
      expect(find.text('Oldingizda 7 kishi bor'), findsOneWidget);
    });

    testWidgets('QUEUE_PAUSED & QUEUE_RESUMED trigger ticket refresh automatically',
        (WidgetTester tester) async {
      int fetchCount = 0;

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          return http.Response(jsonEncode([waitingTicketJson]), 200);
        }
        if (request.url.path == '/api/queues/my-ticket') {
          fetchCount++;
          return http.Response(jsonEncode(waitingTicketJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(
          MyQueueScreen(
            queueService: queueService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetchCount, equals(1));

      // Real QUEUE_PAUSED message
      pushService.handleRemoteMessage(const RemoteMessage(
        data: {
          'type': 'QUEUE_PAUSED',
          'queue_id': '1',
        },
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(fetchCount, equals(2));

      // Real QUEUE_RESUMED message
      pushService.handleRemoteMessage(const RemoteMessage(
        data: {
          'type': 'QUEUE_RESUMED',
          'queue_id': '1',
        },
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(fetchCount, equals(3));
    });

    testWidgets('Non-queue FCM events do not trigger MyQueueScreen refresh',
        (WidgetTester tester) async {
      int fetchCount = 0;

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          return http.Response(jsonEncode([waitingTicketJson]), 200);
        }
        if (request.url.path == '/api/queues/my-ticket') {
          fetchCount++;
          return http.Response(jsonEncode(waitingTicketJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(
          MyQueueScreen(
            queueService: queueService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetchCount, equals(1));

      // Promotional or non-queue message
      const promoMessage = RemoteMessage(
        data: {'type': 'MARKETING_PROMO', 'promo_code': 'SPRING2026'},
      );
      pushService.handleRemoteMessage(promoMessage);

      await tester.pump();
      await tester.pumpAndSettle();

      // No refetch triggered
      expect(fetchCount, equals(1));
    });

    testWidgets('Manual pull-to-refresh remains functional as fallback',
        (WidgetTester tester) async {
      int fetchCount = 0;

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          return http.Response(jsonEncode([waitingTicketJson]), 200);
        }
        if (request.url.path == '/api/queues/my-ticket') {
          fetchCount++;
          return http.Response(jsonEncode(waitingTicketJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(
          MyQueueScreen(
            queueService: queueService,
            pushNotificationService: pushService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetchCount, equals(1));

      // Trigger manual pull-to-refresh
      await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(fetchCount, equals(2));
    });
  });
}
