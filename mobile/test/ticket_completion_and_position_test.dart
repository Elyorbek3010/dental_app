import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/models/doctor.dart';
import 'package:app/models/reminder.dart';
import 'package:app/models/specialization.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/reminder_service.dart';
import 'package:app/services/secure_token_storage.dart';
import 'package:app/theme/app_theme.dart';

class _InMemoryTokenStorage implements SecureTokenStorage {
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> saveAccessToken(String accessToken) async {}

  @override
  Future<String?> getAccessToken() async => 'test_jwt';

  @override
  Future<String?> getRefreshToken() async => 'test_refresh';

  @override
  Future<void> clearTokens() async {}
}

class _FakeWebSocketSink extends Fake implements WebSocketSink {
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
}

class _FakeWebSocketChannel extends Fake implements WebSocketChannel {
  _FakeWebSocketChannel(this._controller) : _sink = _FakeWebSocketSink();
  final StreamController<dynamic> _controller;
  final _FakeWebSocketSink _sink;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _sink;
}

class _FakePushService extends Fake implements PushNotificationService {
  final StreamController<Map<String, dynamic>> _ctrl =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  bool get isFirebaseAvailable => false;

  @override
  Stream<Map<String, dynamic>> get queueEvents => _ctrl.stream;

  @override
  void ensureListeners() {}

  void emit(Map<String, dynamic> event) {
    if (!_ctrl.isClosed) _ctrl.add(event);
  }

  @override
  void dispose() {
    _ctrl.close();
  }
}

class _EmptyReminderService extends Fake implements ReminderService {
  @override
  Future<List<Reminder>> getReminders() async => <Reminder>[];
}

Widget _wrapApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Completed Ticket Clearance & Position Consistency', () {
    testWidgets(
      'HomeScreen clears completed ticket on push event and tab activation',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        bool completed = false;
        final wsController = StreamController<dynamic>.broadcast();
        final realtime = QueueRealtimeService(
          channelFactory: (_) => _FakeWebSocketChannel(wsController),
        );
        final push = _FakePushService();
        addTearDown(() async {
          await wsController.close();
          realtime.dispose();
          push.dispose();
        });

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/catalog/specializations') {
            return http.Response(
              jsonEncode([
                {'id': 1, 'clinic_id': 1, 'name': 'Therapy'},
              ]),
              200,
            );
          }
          if (request.url.path == '/api/queues/my-tickets') {
            if (completed) {
              // Also verify client defensively strips unexpected COMPLETED ticket
              return http.Response(
                jsonEncode([
                  {
                    'id': 50,
                    'queue_id': 10,
                    'ticket_number': 7,
                    'queue_position': 7,
                    'status': 'COMPLETED',
                    'created_at': DateTime.now().toUtc().toIso8601String(),
                    'people_ahead': 0,
                    'doctor': {
                      'id': 2,
                      'full_name': 'Dr. Aziza Karimova',
                      'room_number': '101',
                      'clinic_id': 1,
                    },
                    'specialization': {'id': 1, 'name': 'Therapy'},
                  },
                ]),
                200,
              );
            }
            return http.Response(
              jsonEncode([
                {
                  'id': 50,
                  'queue_id': 10,
                  'ticket_number': 7,
                  'queue_position': 7,
                  'status': 'SERVING',
                  'created_at': DateTime.now().toUtc().toIso8601String(),
                  'people_ahead': 0,
                  'doctor': {
                    'id': 2,
                    'full_name': 'Dr. Aziza Karimova',
                    'room_number': '101',
                    'clinic_id': 1,
                  },
                  'specialization': {'id': 1, 'name': 'Therapy'},
                },
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        final queueSvc = QueueService(
          httpClient: mockClient,
          tokenStorage: _InMemoryTokenStorage(),
        );
        final catalogSvc = CatalogService(
          httpClient: mockClient,
          tokenStorage: _InMemoryTokenStorage(),
        );

        await tester.pumpWidget(
          _wrapApp(
            HomeScreen(
              isActiveTab: true,
              queueService: queueSvc,
              catalogService: catalogSvc,
              reminderService: _EmptyReminderService(),
              pushNotificationService: push,
              realtimeService: realtime,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('№7'), findsOneWidget);
        expect(find.text('Dr. Aziza Karimova'), findsOneWidget);

        // Session completes -> push notification arrives -> completed ticket must disappear
        completed = true;
        push.emit({'type': 'QUEUE_COMPLETED', 'ticket_id': '50', 'queue_id': '10'});
        await tester.pumpAndSettle();

        expect(find.text('№7'), findsNothing);
        expect(find.text('No active queue'), findsOneWidget);
      },
    );

    testWidgets(
      'MyQueueScreen defensively hides COMPLETED ticket even if stale payload includes it',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final wsController = StreamController<dynamic>.broadcast();
        final realtime = QueueRealtimeService(
          channelFactory: (_) => _FakeWebSocketChannel(wsController),
        );
        final push = _FakePushService();
        addTearDown(() async {
          await wsController.close();
          realtime.dispose();
          push.dispose();
        });

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/queues/my-tickets') {
            return http.Response(
              jsonEncode([
                {
                  'id': 50,
                  'queue_id': 10,
                  'ticket_number': 7,
                  'queue_position': 7,
                  'status': 'COMPLETED',
                  'created_at': DateTime.now().toUtc().toIso8601String(),
                  'people_ahead': 0,
                  'doctor': {
                    'id': 2,
                    'full_name': 'Dr. Aziza Karimova',
                    'room_number': '101',
                    'clinic_id': 1,
                  },
                  'specialization': {'id': 1, 'name': 'Therapy'},
                },
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        final queueSvc = QueueService(
          httpClient: mockClient,
          tokenStorage: _InMemoryTokenStorage(),
        );

        await tester.pumpWidget(
          _wrapApp(
            MyQueueScreen(
              queueService: queueSvc,
              pushNotificationService: push,
              realtimeService: realtime,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('№7'), findsNothing);
        expect(find.byKey(const Key('my_queue_refresh_indicator_empty')), findsOneWidget);
      },
    );

    testWidgets(
      'DoctorQueueScreen displays consistent estimated queue position and active people ahead',
      (tester) async {
        const doctor = Doctor(
          id: 10,
          clinicId: 1,
          specializationId: 1,
          fullName: 'Dr. Alisher Valiyev',
          roomNumber: '101',
          isActive: true,
        );
        const spec = Specialization(id: 1, clinicId: 1, name: 'Therapy');

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/catalog/doctors/10/queue') {
            return http.Response(
              jsonEncode({
                'id': 100,
                'queue_id': 100,
                'doctor_id': 10,
                'queue_date': '2026-11-20',
                'is_paused': false,
                'is_active': true,
                'waiting_count': 1,
                'called_count': 0,
                'serving_count': 1,
                'estimated_position_if_joined': 5,
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        final catalogSvc = CatalogService(
          httpClient: mockClient,
          tokenStorage: _InMemoryTokenStorage(),
        );

        await tester.pumpWidget(
          _wrapApp(
            DoctorQueueScreen(
              doctor: doctor,
              specialization: spec,
              catalogService: catalogSvc,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('prejoin_estimated_position')), findsOneWidget);
        expect(find.text('#5'), findsOneWidget);
        expect(find.byKey(const Key('prejoin_people_ahead_text')), findsOneWidget);
        expect(find.text('2 people ahead of you'), findsOneWidget);
      },
    );
  });
}
