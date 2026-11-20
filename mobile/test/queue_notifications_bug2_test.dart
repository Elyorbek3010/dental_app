import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/models/doctor.dart';
import 'package:app/models/specialization.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/screens/patient_shell.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/secure_token_storage.dart';
import 'package:app/theme/app_theme.dart';

class InMemoryTokenStorage implements SecureTokenStorage {
  String? accessToken = 'bug2_jwt';
  String? refreshToken = 'bug2_refresh';

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

class FakeWebSocketSink extends Fake implements WebSocketSink {
  bool closed = false;
  final List<dynamic> sentMessages = [];

  @override
  void add(dynamic data) {
    sentMessages.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }
}

class FakeWebSocketChannel extends Fake implements WebSocketChannel {
  FakeWebSocketChannel(this._controller) : fakeSink = FakeWebSocketSink();

  final StreamController<dynamic> _controller;
  final FakeWebSocketSink fakeSink;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => fakeSink;
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
  void setAccessToken(String? token) => currentAccessToken = token;

  @override
  void clearAccessToken() => currentAccessToken = null;

  @override
  Future<void> initialize({
    String? customBaseUrl,
    String? Function()? tokenProvider,
  }) async {}

  @override
  Future<NotificationSettings> requestPermissions() async =>
      throw UnimplementedError();

  @override
  Future<String?> getDeviceToken() async => 'fake_fcm_token';

  @override
  Future<bool> registerDevice(
    String accessToken, {
    String? fcmToken,
    String? customBaseUrl,
  }) async =>
      true;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get queueEvents => _controller.stream;

  @override
  void notifyQueueEvent(Map<String, dynamic> data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  @override
  void handleRemoteMessage(RemoteMessage message) {
    final eventType =
        PushNotificationService.parseQueueEventType(message.data, message.notification);
    if (eventType != null) {
      final payload = Map<String, dynamic>.from(message.data);
      payload['type'] ??= 'QUEUE_$eventType';
      payload['event_type'] = eventType;
      notifyQueueEvent(payload);
    }
  }

  @override
  void ensureListeners() {}

  @override
  void setupInteractionListeners() {}

  @override
  Future<void> checkInitialMessage() async {}

  @override
  void setupTokenRefreshListener() {}

  @override
  void setupForegroundMessageListener() {}

  @override
  void dispose() => _controller.close();
}

Widget wrapApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: const Locale('uz'),
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Bug #2 — PushNotificationService SKIPPED / RESTORED recognition', () {
    test('Recognizes QUEUE_SKIPPED and QUEUE_RESTORED distinctly from QUEUE_MISSED_TURN', () {
      expect(
        PushNotificationService.parseQueueEventType({'type': 'QUEUE_SKIPPED', 'ticket_id': '10'}),
        equals('SKIPPED'),
      );
      expect(
        PushNotificationService.parseQueueEventType({'type': 'QUEUE_RESTORED', 'ticket_id': '10'}),
        equals('RESTORED'),
      );
      expect(
        PushNotificationService.parseQueueEventType({'type': 'QUEUE_MISSED_TURN', 'ticket_id': '10'}),
        equals('MISSED_TURN'),
      );

      // OEM body fallback classification
      const skippedNotif = RemoteNotification(
        title: 'Dental Queue',
        body: 'Taloningiz №5 navbatdan vaqtincha chetlatildi (Skipped). Qayta tiklash uchun qabulxonaga murojaat qiling.',
      );
      expect(PushNotificationService.parseQueueEventType({}, skippedNotif), equals('SKIPPED'));

      const restoredNotif = RemoteNotification(
        title: 'Dental Queue',
        body: 'Taloningiz №5 navbatga qayta tiklandi va navbat oxiriga qo‘shildi.',
      );
      expect(PushNotificationService.parseQueueEventType({}, restoredNotif), equals('RESTORED'));
    });
  });

  group('Bug #2 — MyQueueScreen SKIPPED/RESTORED & Realtime Lifecycle', () {
    final baseTicket = {
      'id': 101,
      'queue_id': 10,
      'ticket_number': 5,
      'status': 'WAITING',
      'created_at': '2026-11-20T09:00:00Z',
      'checked_in_at': '2026-11-20T09:05:00Z',
      'check_in_method': 'QR',
      'people_ahead': 2,
      'clinic_id': 1,
      'doctor': {
        'id': 1,
        'clinic_id': 1,
        'full_name': 'Dr. Test',
        'room_number': '101',
      },
      'specialization': {
        'id': 1,
        'name': 'Terapiya',
      },
    };

    testWidgets(
      'MyQueueScreen requests include_skipped=true, renders SKIPPED state, deduplicates foreground feedback, and restores to WAITING',
      (tester) async {
        final pushService = TestPushNotificationService();
        final wsController = StreamController<dynamic>.broadcast();
        final realtimeService = QueueRealtimeService(
          channelFactory: (_) => FakeWebSocketChannel(wsController),
        );

        String? capturedIncludeSkipped;
        Map<String, dynamic> backendTicket = Map<String, dynamic>.from(baseTicket);

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/queues/my-tickets') {
            capturedIncludeSkipped = request.url.queryParameters['include_skipped'];
            return http.Response(jsonEncode([backendTicket]), 200);
          }
          if (request.url.path == '/api/queues/my-ticket') {
            capturedIncludeSkipped = request.url.queryParameters['include_skipped'];
            return http.Response(jsonEncode(backendTicket), 200);
          }
          return http.Response('Not Found', 404);
        });

        final queueService = QueueService(
          httpClient: mockClient,
          tokenStorage: InMemoryTokenStorage(),
        );

        await tester.pumpWidget(
          wrapApp(
            MyQueueScreen(
              queueService: queueService,
              pushNotificationService: pushService,
              realtimeService: realtimeService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(capturedIncludeSkipped, equals('true'));
        expect(find.text('Kutilmoqda'), findsOneWidget);
        expect(find.byKey(const Key('skipped_banner')), findsNothing);

        // Backend marks ticket SKIPPED and sends QUEUE_SKIPPED push + WS update
        backendTicket = Map<String, dynamic>.from(baseTicket)
          ..['status'] = 'SKIPPED'
          ..['people_ahead'] = 0;

        pushService.handleRemoteMessage(const RemoteMessage(
          data: {'type': 'QUEUE_SKIPPED', 'ticket_id': '101', 'queue_id': '10'},
        ));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('skipped_banner')), findsOneWidget);
        expect(find.byKey(const Key('checkin_card')), findsNothing);
        expect(find.byKey(const Key('foreground_notif_skipped')), findsOneWidget);

        // Duplicate QUEUE_SKIPPED within 5s does not crash or emit duplicate alerts
        pushService.handleRemoteMessage(const RemoteMessage(
          data: {'type': 'QUEUE_SKIPPED', 'ticket_id': '101', 'queue_id': '10'},
        ));
        await tester.pump();

        // Backend restores ticket to WAITING at end of queue (people_ahead = 6)
        backendTicket = Map<String, dynamic>.from(baseTicket)
          ..['status'] = 'WAITING'
          ..['people_ahead'] = 6;

        wsController.add(jsonEncode({
          'type': 'queue_updated',
          'clinic_id': 1,
          'queue_id': 10,
        }));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('skipped_banner')), findsNothing);
        expect(find.text('Kutilmoqda'), findsOneWidget);
        expect(find.text('Oldingizda 6 kishi bor'), findsOneWidget);

        pushService.dispose();
        await wsController.close();
        realtimeService.dispose();
      },
    );

    testWidgets(
      'Joining via DoctorQueueScreen does not disconnect MyQueueScreen realtime updates',
      (tester) async {
        final wsController = StreamController<dynamic>.broadcast();
        int channelCreateCount = 0;
        final createdChannels = <FakeWebSocketChannel>[];

        final realtimeService = QueueRealtimeService(
          channelFactory: (_) {
            channelCreateCount++;
            final ch = FakeWebSocketChannel(wsController);
            createdChannels.add(ch);
            return ch;
          },
        );

        int peopleAhead = 2;

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/catalog/doctors/1/queue') {
            return http.Response(
              jsonEncode({
                'id': 10,
                'queue_id': 10,
                'doctor_id': 1,
                'queue_date': '2026-11-20',
                'is_paused': false,
                'is_active': true,
                'waiting_count': 2,
                'called_count': 0,
                'serving_count': 0,
                'estimated_position_if_joined': 3,
              }),
              200,
            );
          }
          if (request.url.path == '/api/queues/10/join' && request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'id': 101,
                'queue_id': 10,
                'patient_id': 1,
                'ticket_number': 5,
                'queue_position': 3,
                'patient_name': 'Bug2 Patient',
                'source': 'ONLINE',
                'status': 'WAITING',
                'created_at': '2026-11-20T09:00:00Z',
                'missed_turns': 0,
              }),
              201,
            );
          }
          if (request.url.path == '/api/queues/my-tickets') {
            return http.Response(
              jsonEncode([Map<String, dynamic>.from(baseTicket)..['people_ahead'] = peopleAhead]),
              200,
            );
          }
          if (request.url.path == '/api/queues/my-ticket') {
            return http.Response(
              jsonEncode(Map<String, dynamic>.from(baseTicket)..['people_ahead'] = peopleAhead),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        final tokenStorage = InMemoryTokenStorage();
        final catalogService = CatalogService(httpClient: mockClient, tokenStorage: tokenStorage);
        final queueService = QueueService(httpClient: mockClient, tokenStorage: tokenStorage);
        final pushService = TestPushNotificationService();
        PushNotificationService.instance.setAccessToken('bug2_jwt');

        await tester.pumpWidget(
          wrapApp(
            DoctorQueueScreen(
              doctor: const Doctor(
                id: 1,
                clinicId: 1,
                specializationId: 1,
                fullName: 'Dr. Test',
                roomNumber: '101',
                isActive: true,
              ),
              specialization: const Specialization(
                id: 1,
                clinicId: 1,
                name: 'Terapiya',
              ),
              catalogService: catalogService,
              queueService: queueService,
              realtimeService: realtimeService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(realtimeService.isConnected, isTrue);

        // Tap Join -> pushes PatientShell(MyQueueScreen) and disposes DoctorQueueScreen
        await tester.tap(find.byKey(const Key('doctor_queue_join_button')));
        await tester.pumpAndSettle();

        expect(find.byType(PatientShell), findsOneWidget);
        expect(realtimeService.isConnected, isTrue);
        expect(createdChannels.last.fakeSink.closed, isFalse);

        // Now Reception updates queue -> WebSocket event arrives on the surviving connection!
        peopleAhead = 1;
        wsController.add(jsonEncode({
          'type': 'queue_updated',
          'clinic_id': 1,
          'queue_id': 10,
        }));
        await tester.pumpAndSettle();

        expect(find.text('Oldingizda 1 kishi bor'), findsOneWidget);
        expect(channelCreateCount, equals(1));

        // Simulate resume forcing a fresh reconnect and restoring latest state
        peopleAhead = 0;
        realtimeService.ensureConnected(1, forceReconnect: true);
        expect(channelCreateCount, equals(2));
        wsController.add(jsonEncode({
          'type': 'queue_updated',
          'clinic_id': 1,
          'queue_id': 10,
        }));
        await tester.pumpAndSettle();
        expect(find.text('Oldingizda hech kim yo‘q'), findsOneWidget);

        pushService.dispose();
        await wsController.close();
        realtimeService.dispose();
      },
    );
  });
}
