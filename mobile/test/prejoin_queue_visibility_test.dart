import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/models/doctor.dart';
import 'package:app/models/doctor_queue.dart';
import 'package:app/models/specialization.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/secure_token_storage.dart';
import 'package:app/theme/app_theme.dart';

/// In-memory fake TokenStorage for testing.
class InMemoryTokenStorage implements SecureTokenStorage {
  String? accessToken = 'fake-access-token';
  String? refreshToken = 'fake-refresh-token';

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

class FakeWebSocketChannel extends Fake implements WebSocketChannel {
  final StreamController<dynamic> _controller;
  FakeWebSocketChannel(this._controller);

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => FakeWebSocketSink();
}

class FakeWebSocketSink extends Fake implements WebSocketSink {
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
}

Widget wrapWithLocalization(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uz'),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testDoctor = Doctor(
    id: 10,
    clinicId: 1,
    specializationId: 1,
    fullName: 'Dr. Alisher Valiyev',
    roomNumber: '101',
    isActive: true,
  );

  const testSpec = Specialization(
    id: 1,
    clinicId: 1,
    name: 'Terapiya',
  );

  group('DoctorQueue Model Parsing Tests', () {
    test('DoctorQueue.fromJson correctly parses pre-join preview fields', () {
      final json = {
        'id': 123,
        'queue_id': 123,
        'doctor_id': 10,
        'queue_date': '2026-09-29',
        'is_paused': false,
        'is_active': true,
        'waiting_count': 4,
        'called_count': 1,
        'serving_count': 2,
        'estimated_position_if_joined': 7,
      };

      final queue = DoctorQueue.fromJson(json);
      expect(queue.id, 123);
      expect(queue.queueId, 123);
      expect(queue.doctorId, 10);
      expect(queue.queueDate, '2026-09-29');
      expect(queue.isPaused, isFalse);
      expect(queue.isActive, isTrue);
      expect(queue.waitingCount, 4);
      expect(queue.calledCount, 1);
      expect(queue.servingCount, 2);
      expect(queue.estimatedPositionIfJoined, 7);

      final output = queue.toJson();
      expect(output['waiting_count'], 4);
      expect(output['called_count'], 1);
      expect(output['serving_count'], 2);
      expect(output['estimated_position_if_joined'], 7);
      expect(output['queue_id'], 123);
    });

    test('DoctorQueue fallback defaults when metrics are missing', () {
      final json = {
        'id': 456,
        'doctor_id': 10,
        'queue_date': '2026-09-29',
        'is_paused': false,
        'is_active': true,
      };

      final queue = DoctorQueue.fromJson(json);
      expect(queue.id, 456);
      expect(queue.queueId, 456);
      expect(queue.waitingCount, 0);
      expect(queue.calledCount, 0);
      expect(queue.servingCount, 0);
      expect(queue.estimatedPositionIfJoined, 1);
    });
  });

  group('DoctorQueueScreen Pre-Join UI Tests', () {
    testWidgets('Renders waiting, called, serving counts and estimated position',
        (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors/10/queue') {
          return http.Response(
            jsonEncode({
              'id': 100,
              'queue_id': 100,
              'doctor_id': 10,
              'queue_date': '2026-09-29',
              'is_paused': false,
              'is_active': true,
              'waiting_count': 4,
              'called_count': 0,
              'serving_count': 1,
              'estimated_position_if_joined': 6,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header and doctor info
      expect(find.text('Dr. Alisher Valiyev'), findsOneWidget);
      expect(find.text('Bugungi navbat holati'), findsOneWidget);

      // Serving count = 1
      expect(find.byKey(const Key('prejoin_serving_count')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Waiting count = 4
      expect(find.byKey(const Key('prejoin_waiting_count')), findsOneWidget);
      expect(find.text('4'), findsOneWidget);

      // Called count = 0
      expect(find.byKey(const Key('prejoin_called_count')), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      // Estimated position = #6
      expect(find.byKey(const Key('prejoin_estimated_position')), findsOneWidget);
      expect(find.text('#6'), findsOneWidget);

      // Join button is enabled
      final joinButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('doctor_queue_join_button')),
      );
      expect(joinButton.enabled, isTrue);
    });

    testWidgets('Renders paused state clearly and disables Join button',
        (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors/10/queue') {
          return http.Response(
            jsonEncode({
              'id': 100,
              'queue_id': 100,
              'doctor_id': 10,
              'queue_date': '2026-09-29',
              'is_paused': true,
              'is_active': true,
              'waiting_count': 2,
              'called_count': 0,
              'serving_count': 0,
              'estimated_position_if_joined': 3,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Shows paused badge
      expect(find.text('Pauza'), findsOneWidget);

      // Join button is disabled
      final joinButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('doctor_queue_join_button')),
      );
      expect(joinButton.enabled, isFalse);
    });

    testWidgets('Renders no-queue state when doctor queue has not been opened (404)',
        (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'No active queue for this doctor today'}),
          404,
        );
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bugun navbat mavjud emas'), findsOneWidget);
      expect(find.byKey(const Key('doctor_queue_join_button')), findsNothing);
    });

    testWidgets('Renders inactive queue state when is_active is false',
        (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 100,
            'queue_id': 100,
            'doctor_id': 10,
            'queue_date': '2026-09-29',
            'is_paused': false,
            'is_active': false,
            'waiting_count': 0,
            'called_count': 0,
            'serving_count': 0,
            'estimated_position_if_joined': 1,
          }),
          200,
        );
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Navbat mavjud emas'), findsOneWidget);
      expect(find.byKey(const Key('doctor_queue_join_button')), findsNothing);
    });
  });

  group('DoctorQueueScreen Real-Time WebSocket Updates Tests', () {
    testWidgets('queue_updated event for current queue triggers silent refetch and updates UI',
        (tester) async {
      int fetchCount = 0;
      int currentWaiting = 4;
      int currentEstimated = 5;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors/10/queue') {
          fetchCount++;
          return http.Response(
            jsonEncode({
              'id': 100,
              'queue_id': 100,
              'doctor_id': 10,
              'queue_date': '2026-09-29',
              'is_paused': false,
              'is_active': true,
              'waiting_count': currentWaiting,
              'called_count': 0,
              'serving_count': 1,
              'estimated_position_if_joined': currentEstimated,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final wsController = StreamController<dynamic>();
      final realtimeService = QueueRealtimeService(
        channelFactory: (uri) => FakeWebSocketChannel(wsController),
      );

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
            realtimeService: realtimeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetchCount, 1);
      expect(find.text('4'), findsOneWidget); // waiting
      expect(find.text('#5'), findsOneWidget); // estimated position

      // Reception changes queue: Waiting drops from 4 to 3
      currentWaiting = 3;
      currentEstimated = 4;

      // Send queue_updated event for current queue (queue_id: 100)
      wsController.add(jsonEncode({
        'type': 'queue_updated',
        'clinic_id': 1,
        'queue_id': 100,
      }));
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);

      wsController.close();
      realtimeService.dispose();
    });

    testWidgets('queue_updated event for an unrelated queue is ignored',
        (tester) async {
      int fetchCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors/10/queue') {
          fetchCount++;
          return http.Response(
            jsonEncode({
              'id': 100,
              'queue_id': 100,
              'doctor_id': 10,
              'queue_date': '2026-09-29',
              'is_paused': false,
              'is_active': true,
              'waiting_count': 4,
              'called_count': 0,
              'serving_count': 1,
              'estimated_position_if_joined': 5,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final wsController = StreamController<dynamic>();
      final realtimeService = QueueRealtimeService(
        channelFactory: (uri) => FakeWebSocketChannel(wsController),
      );

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
            realtimeService: realtimeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetchCount, 1);

      // Send queue_updated event for Doctor B's queue (queue_id: 200, different queue!)
      wsController.add(jsonEncode({
        'type': 'queue_updated',
        'clinic_id': 1,
        'queue_id': 200,
      }));
      await tester.pumpAndSettle();

      // fetchCount must NOT increase!
      expect(fetchCount, 1);

      wsController.close();
      realtimeService.dispose();
    });

    testWidgets('WebSocket failure does not crash UI and pull-to-refresh works',
        (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors/10/queue') {
          return http.Response(
            jsonEncode({
              'id': 100,
              'queue_id': 100,
              'doctor_id': 10,
              'queue_date': '2026-09-29',
              'is_paused': false,
              'is_active': true,
              'waiting_count': 1,
              'called_count': 0,
              'serving_count': 0,
              'estimated_position_if_joined': 2,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      // Realtime service that fails immediately
      final failingRealtimeService = QueueRealtimeService(
        channelFactory: (uri) => throw Exception('WebSocket connection failed'),
      );

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
            realtimeService: failingRealtimeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // UI loads normally despite WebSocket error
      expect(find.text('Dr. Alisher Valiyev'), findsOneWidget);
      expect(find.text('Bugungi navbat holati'), findsOneWidget);
      expect(find.byKey(const Key('doctor_queue_join_button')), findsOneWidget);

      // Pull-to-refresh fallback functions smoothly
      await tester.fling(find.byType(SingleChildScrollView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prejoin_waiting_count')), findsOneWidget);

      failingRealtimeService.dispose();
    });

    testWidgets('Disposing DoctorQueueScreen cancels subscriptions and disconnects cleanly',
        (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 100,
            'queue_id': 100,
            'doctor_id': 10,
            'queue_date': '2026-09-29',
            'is_paused': false,
            'is_active': true,
            'waiting_count': 0,
            'called_count': 0,
            'serving_count': 0,
            'estimated_position_if_joined': 1,
          }),
          200,
        );
      });

      final catalogService = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final realtimeService = QueueRealtimeService();

      await tester.pumpWidget(
        wrapWithLocalization(
          DoctorQueueScreen(
            doctor: testDoctor,
            specialization: testSpec,
            catalogService: catalogService,
            realtimeService: realtimeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Replace widget to trigger dispose
      await tester.pumpWidget(
        wrapWithLocalization(const Scaffold(body: Text('New Screen'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Screen'), findsOneWidget);
      expect(find.byType(DoctorQueueScreen), findsNothing);

      realtimeService.dispose();
    });
  });
}
