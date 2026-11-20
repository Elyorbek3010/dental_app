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
  Future<String?> getAccessToken() async => 'bug6_jwt';

  @override
  Future<String?> getRefreshToken() async => 'bug6_refresh';

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

  void emitRemoteEvent(Map<String, dynamic> data) {
    if (!_ctrl.isClosed) _ctrl.add(data);
  }

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

  test('QueueService.getMyTickets parses multiple specialist tickets and checkInWithQr passes ticket_id', () async {
    final now = DateTime.now().toUtc();
    int? capturedQrTicketId;

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/queues/my-tickets') {
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'queue_id': 10,
              'ticket_number': 5,
              'status': 'WAITING',
              'created_at': now.toIso8601String(),
              'people_ahead': 2,
              'clinic_id': 1,
              'doctor': {'id': 1, 'full_name': 'Dr. Ortho', 'room_number': '101', 'clinic_id': 1},
              'specialization': {'id': 1, 'name': 'Orthodontist'},
            },
            {
              'id': 2,
              'queue_id': 11,
              'ticket_number': 12,
              'status': 'CALLED',
              'created_at': now.toIso8601String(),
              'people_ahead': 0,
              'clinic_id': 1,
              'called_at': now.toIso8601String(),
              'call_deadline_at': now.add(const Duration(seconds: 48)).toIso8601String(),
              'server_time': now.toIso8601String(),
              'doctor': {'id': 2, 'full_name': 'Dr. Surgeon', 'room_number': '202', 'clinic_id': 1},
              'specialization': {'id': 2, 'name': 'Surgeon'},
            },
          ]),
          200,
        );
      }
      if (request.url.path == '/api/queues/check-in/qr') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedQrTicketId = body['ticket_id'] as int?;
        return http.Response(
          jsonEncode({
            'id': 1,
            'queue_id': 10,
            'ticket_number': 5,
            'queue_position': 3,
            'patient_name': 'Test',
            'source': 'ONLINE',
            'status': 'WAITING',
            'created_at': now.toIso8601String(),
            'checked_in_at': now.toIso8601String(),
            'check_in_method': 'QR',
            'missed_turns': 0,
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });

    final service = QueueService(
      httpClient: mockClient,
      tokenStorage: _InMemoryTokenStorage(),
    );

    final list = await service.getMyTickets();
    expect(list.length, 2);
    expect(list[0].specialization.name, 'Orthodontist');
    expect(list[0].peopleAhead, 2);
    expect(list[1].specialization.name, 'Surgeon');
    expect(list[1].isCalled, isTrue);

    await service.checkInWithQr('qr_tok', ticketId: 1);
    expect(capturedQrTicketId, 1);
  });

  testWidgets(
    'MyQueueScreen renders multiple specialist cards with independent countdowns, targeted cancel, WS, FCM, resume & empty state',
    (tester) async {
      final pushService = _TestPushService();
      final wsController = StreamController<dynamic>.broadcast();
      final realtimeService = QueueRealtimeService(
        channelFactory: (_) => _FakeWebSocketChannel(wsController),
      );

      final now = DateTime.now().toUtc();
      Map<String, dynamic> orthoTicket = {
        'id': 101,
        'queue_id': 10,
        'ticket_number': 5,
        'status': 'CALLED',
        'created_at': now.toIso8601String(),
        'people_ahead': 0,
        'clinic_id': 1,
        'called_at': now.toIso8601String(),
        'call_deadline_at': now.add(const Duration(seconds: 95)).toIso8601String(),
        'paused_remaining_seconds': null,
        'is_queue_paused': false,
        'server_time': now.toIso8601String(),
        'doctor': {'id': 1, 'full_name': 'Dr. Ortho', 'room_number': '101', 'clinic_id': 1},
        'specialization': {'id': 1, 'name': 'Orthodontist'},
      };

      Map<String, dynamic> surgeonTicket = {
        'id': 102,
        'queue_id': 11,
        'ticket_number': 12,
        'status': 'CALLED',
        'created_at': now.toIso8601String(),
        'people_ahead': 0,
        'clinic_id': 1,
        'called_at': now.toIso8601String(),
        'call_deadline_at': now.add(const Duration(seconds: 48)).toIso8601String(),
        'paused_remaining_seconds': null,
        'is_queue_paused': false,
        'server_time': now.toIso8601String(),
        'doctor': {'id': 2, 'full_name': 'Dr. Surgeon', 'room_number': '202', 'clinic_id': 1},
        'specialization': {'id': 2, 'name': 'Surgeon'},
      };

      List<Map<String, dynamic>> backendTickets = [orthoTicket, surgeonTicket];
      String? cancelledPath;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode(backendTickets), 200);
        }
        if (request.url.path == '/api/queues/10/tickets/101/cancel' &&
            request.method == 'PATCH') {
          cancelledPath = request.url.path;
          backendTickets = [surgeonTicket];
          return http.Response(
            jsonEncode({
              'id': 101,
              'queue_id': 10,
              'ticket_number': 5,
              'queue_position': 1,
              'patient_name': 'P1',
              'source': 'ONLINE',
              'status': 'CANCELLED',
              'created_at': now.toIso8601String(),
              'missed_turns': 0,
            }),
            200,
          );
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

      // Both specialist cards render independently
      expect(find.byKey(const Key('specialist_ticket_section_101')), findsOneWidget);
      expect(find.byKey(const Key('specialist_ticket_section_102')), findsOneWidget);
      expect(find.text('Orthodontist'), findsOneWidget);
      expect(find.text('Surgeon'), findsOneWidget);
      expect(find.text('№5'), findsOneWidget);
      expect(find.text('№12'), findsOneWidget);
      expect(find.byKey(const Key('join_another_queue_button')), findsOneWidget);

      // Pause ONLY Orthodontist queue via WebSocket event -> Surgeon countdown stays unpaused
      orthoTicket = Map<String, dynamic>.from(orthoTicket)
        ..['call_deadline_at'] = null
        ..['paused_remaining_seconds'] = 90
        ..['is_queue_paused'] = true;
      backendTickets = [orthoTicket, surgeonTicket];

      wsController.add(jsonEncode({'type': 'queue_updated', 'clinic_id': 1, 'queue_id': 10}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.descendant(
          of: find.byKey(const Key('specialist_ticket_section_101')),
          matching: find.text('Remaining time: 01:30 (Paused)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('specialist_ticket_section_102')),
          matching: find.textContaining('(Paused)'),
        ),
        findsNothing,
      );

      // Cancel ONLY Orthodontist ticket #101 -> targets /api/queues/10/tickets/101/cancel & keeps #102
      final cancelBtn101 = find.descendant(
        of: find.byKey(const Key('specialist_ticket_section_101')),
        matching: find.byKey(const Key('cancel_ticket_button')),
      );
      await tester.ensureVisible(cancelBtn101);
      await tester.tap(cancelBtn101);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancel_confirm_yes_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel_confirm_yes_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(cancelledPath, '/api/queues/10/tickets/101/cancel');
      expect(find.byKey(const Key('specialist_ticket_section_101')), findsNothing);
      expect(find.byKey(const Key('specialist_ticket_section_102')), findsOneWidget);

      // App resume + FCM refresh updates #102 to COMPLETED -> empty state renders cleanly
      backendTickets = [];
      pushService.emitRemoteEvent(const RemoteMessage(
        data: {'type': 'QUEUE_COMPLETED', 'ticket_id': '102', 'queue_id': '11'},
      ).data);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('my_queue_refresh_indicator_empty')), findsOneWidget);

      pushService.dispose();
      await wsController.close();
      realtimeService.dispose();
    },
  );
}
