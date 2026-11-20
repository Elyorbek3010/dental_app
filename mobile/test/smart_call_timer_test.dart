import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/models/patient_ticket.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/queue_service.dart';
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

class _TestPushService extends Fake implements PushNotificationService {
  final StreamController<Map<String, dynamic>> _ctrl =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  bool get isFirebaseAvailable => false;

  @override
  Stream<Map<String, dynamic>> get queueEvents => _ctrl.stream;

  @override
  void ensureListeners() {}

  @override
  void dispose() {
    _ctrl.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('en'),
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

  setUp(() {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
  });

  test('MyQueueTicket parses Smart Call deadline and paused countdown fields', () {
    final now = DateTime.now().toUtc();
    final deadline = now.add(const Duration(seconds: 75));
    final ticket = MyQueueTicket.fromJson({
      'id': 11,
      'queue_id': 5,
      'ticket_number': 7,
      'status': 'CALLED',
      'created_at': now.toIso8601String(),
      'people_ahead': 0,
      'clinic_id': 1,
      'called_at': now.toIso8601String(),
      'call_deadline_at': deadline.toIso8601String(),
      'paused_remaining_seconds': null,
      'is_queue_paused': false,
      'server_time': now.toIso8601String(),
      'doctor': {
        'id': 2,
        'full_name': 'Dr. Timer',
        'room_number': '101',
        'clinic_id': 1,
      },
      'specialization': {'id': 1, 'name': 'Therapy'},
    });

    expect(ticket.isCalled, isTrue);
    expect(ticket.callDeadlineAt, isNotNull);
    expect(ticket.isQueuePaused, isFalse);
    expect(ticket.serverTime, isNotNull);
  });

  testWidgets(
    'MyQueueScreen shows live MM:SS countdown when CALLED, freezes on Pause, and stops on SERVING',
    (tester) async {
      final pushService = _TestPushService();
      final wsController = StreamController<dynamic>.broadcast();
      final realtimeService = QueueRealtimeService(
        channelFactory: (_) => _FakeWebSocketChannel(wsController),
      );

      final now = DateTime.now().toUtc();
      Map<String, dynamic> backendTicket = {
        'id': 101,
        'queue_id': 10,
        'ticket_number': 4,
        'status': 'CALLED',
        'created_at': now.toIso8601String(),
        'people_ahead': 0,
        'clinic_id': 1,
        'called_at': now.toIso8601String(),
        'call_deadline_at': now.add(const Duration(seconds: 65)).toIso8601String(),
        'paused_remaining_seconds': null,
        'is_queue_paused': false,
        'server_time': now.toIso8601String(),
        'doctor': {
          'id': 2,
          'full_name': 'Dr. Timer',
          'room_number': '101',
          'clinic_id': 1,
        },
        'specialization': {'id': 1, 'name': 'Therapy'},
      };

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([backendTicket]), 200);
        }
        if (request.url.path == '/api/queues/my-ticket') {
          return http.Response(jsonEncode(backendTicket), 200);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: _InMemoryTokenStorage(),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('called_banner')), findsOneWidget);
      expect(find.byKey(const Key('called_countdown_badge')), findsOneWidget);
      expect(find.textContaining('Remaining time:'), findsOneWidget);

      // Simulate paused queue state via WebSocket update
      backendTicket = Map<String, dynamic>.from(backendTicket)
        ..['call_deadline_at'] = null
        ..['paused_remaining_seconds'] = 42
        ..['is_queue_paused'] = true;

      wsController.add(jsonEncode({
        'type': 'queue_updated',
        'clinic_id': 1,
        'queue_id': 10,
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Remaining time: 00:42 (Paused)'), findsOneWidget);

      // Simulate Reception moving ticket to SERVING -> countdown stops & badge disappears
      backendTicket = Map<String, dynamic>.from(backendTicket)
        ..['status'] = 'SERVING'
        ..['call_deadline_at'] = null
        ..['paused_remaining_seconds'] = null
        ..['is_queue_paused'] = false;

      wsController.add(jsonEncode({
        'type': 'queue_updated',
        'clinic_id': 1,
        'queue_id': 10,
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('called_countdown_badge')), findsNothing);
      expect(find.byKey(const Key('serving_banner')), findsOneWidget);

      pushService.dispose();
      await wsController.close();
      realtimeService.dispose();
    },
  );
}
