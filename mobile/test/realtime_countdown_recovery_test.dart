import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  Future<String?> getAccessToken() async => 'test_jwt';

  @override
  Future<String?> getRefreshToken() async => 'test_refresh';

  @override
  Future<void> clearTokens() async {}
}

class _RecordingWebSocketSink extends Fake implements WebSocketSink {
  final List<dynamic> sent = <dynamic>[];
  int closeCount = 0;

  @override
  void add(dynamic data) {
    sent.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closeCount++;
  }
}

class _ControlledWebSocketChannel extends Fake implements WebSocketChannel {
  _ControlledWebSocketChannel(this.controller)
      : _sink = _RecordingWebSocketSink();

  final StreamController<dynamic> controller;
  final _RecordingWebSocketSink _sink;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  _RecordingWebSocketSink get sink => _sink;
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

  void emitEvent(Map<String, dynamic> event) {
    if (!_ctrl.isClosed) _ctrl.add(event);
  }

  @override
  void dispose() {
    _ctrl.close();
  }
}

Map<String, dynamic> _buildTicketJson({
  required int id,
  required int queueId,
  required int ticketNumber,
  required String status,
  required DateTime createdAt,
  required String doctorName,
  required String roomNumber,
  required String specializationName,
  DateTime? calledAt,
  DateTime? callDeadlineAt,
  DateTime? checkedInAt,
  DateTime? serverTime,
  bool isQueuePaused = false,
}) {
  return <String, dynamic>{
    'id': id,
    'queue_id': queueId,
    'ticket_number': ticketNumber,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'people_ahead': status == 'WAITING' ? 1 : 0,
    'clinic_id': 1,
    'called_at': calledAt?.toIso8601String(),
    'call_deadline_at': callDeadlineAt?.toIso8601String(),
    'checked_in_at': checkedInAt?.toIso8601String(),
    'check_in_method': checkedInAt != null ? 'QR' : null,
    'paused_remaining_seconds': null,
    'is_queue_paused': isQueuePaused,
    'server_time': serverTime?.toIso8601String(),
    'doctor': <String, dynamic>{
      'id': queueId,
      'full_name': doctorName,
      'room_number': roomNumber,
      'clinic_id': 1,
    },
    'specialization': <String, dynamic>{
      'id': queueId,
      'name': specializationName,
    },
  };
}

Widget _wrapApp(Widget child) {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
  });

  group('QueueRealtimeService ping/pong timeout & reconnect', () {
    test('8-9: stays connected when pong arrives and disconnects cleanly on pong timeout',
        () async {
      final channels = <_ControlledWebSocketChannel>[];
      final connectionStates = <bool>[];
      final reconnectedClinics = <int>[];

      final service = QueueRealtimeService(
        keepaliveInterval: const Duration(milliseconds: 300),
        pongTimeout: const Duration(milliseconds: 150),
        channelFactory: (_) {
          final ctrl = StreamController<dynamic>.broadcast();
          final ch = _ControlledWebSocketChannel(ctrl);
          channels.add(ch);
          return ch;
        },
      );

      final connSub = service.connectionStates.listen(connectionStates.add);
      final reconnSub = service.onReconnected.listen(reconnectedClinics.add);

      service.connect(1);
      expect(channels.length, 1);
      channels.first.controller.add(jsonEncode({'type': 'connected', 'clinic_id': 1}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.isConnectionConfirmed, isTrue);

      // First keepalive ping at ~300ms -> reply with pong within timeout -> stays open
      await Future<void>.delayed(const Duration(milliseconds: 330));
      expect(channels.first.sink.sent.length, 1);
      expect(jsonDecode(channels.first.sink.sent.first as String)['type'], 'ping');
      channels.first.controller.add(jsonEncode({'type': 'pong'}));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(channels.length, 1);
      expect(channels.first.sink.closeCount, 0);

      // Second keepalive ping at ~600ms -> NO pong for >150ms -> stalled socket disconnected
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(channels.first.sink.closeCount, greaterThanOrEqualTo(1));
      expect(connectionStates, contains(false));

      // Reconnect timer fires after 1s -> new channel opens (keepalive won't fire for 300ms)
      await Future<void>.delayed(const Duration(milliseconds: 950));
      expect(channels.length, 2);
      channels.last.controller.add(jsonEncode({'type': 'connected', 'clinic_id': 1}));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reconnectedClinics, [1]);
      expect(service.isConnectionConfirmed, isTrue);

      await connSub.cancel();
      await reconnSub.cancel();
      service.dispose();
      for (final ch in channels) {
        await ch.controller.close();
      }
    });
  });

  group('MyQueueScreen multi-ticket realtime & countdown recovery', () {
    testWidgets(
      '1-4: Doctor A CALLED then Doctor B CALLED render independent deadlines, then Doctor A auto-skips to SKIPPED',
      (tester) async {
        var fakeNow = DateTime.utc(2026, 11, 20, 15, 0, 0);
        final pushService = _TestPushService();
        final wsCtrl = StreamController<dynamic>.broadcast();
        final realtimeService = QueueRealtimeService(
          channelFactory: (_) => _ControlledWebSocketChannel(wsCtrl),
        );

        var ticket566 = _buildTicketJson(
          id: 566,
          queueId: 265,
          ticketNumber: 5,
          status: 'CALLED',
          createdAt: fakeNow,
          doctorName: 'Dr. Endo',
          roomNumber: '101',
          specializationName: 'Endodontist',
          checkedInAt: fakeNow,
          calledAt: fakeNow,
          callDeadlineAt: fakeNow.add(const Duration(seconds: 15)),
        );
        var ticket565 = _buildTicketJson(
          id: 565,
          queueId: 264,
          ticketNumber: 8,
          status: 'WAITING',
          createdAt: fakeNow,
          doctorName: 'Dr. Ortho',
          roomNumber: '100',
          specializationName: 'Ortodont',
          checkedInAt: fakeNow,
        );

        var backendTickets = [ticket566, ticket565];

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/queues/my-tickets') {
            return http.Response(jsonEncode(backendTickets), 200);
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          _wrapApp(
            MyQueueScreen(
              queueService: QueueService(
                httpClient: mockClient,
                tokenStorage: _InMemoryTokenStorage(),
              ),
              pushNotificationService: pushService,
              realtimeService: realtimeService,
              nowProvider: () => fakeNow,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const Key('specialist_ticket_section_566')), findsOneWidget);
        expect(find.byKey(const Key('specialist_ticket_section_565')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('specialist_ticket_section_566')),
            matching: find.text('Remaining time: 00:15'),
          ),
          findsOneWidget,
        );

        // Doctor B (queue 264) becomes CALLED 5s later with 90s deadline
        fakeNow = fakeNow.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));

        ticket565 = _buildTicketJson(
          id: 565,
          queueId: 264,
          ticketNumber: 8,
          status: 'CALLED',
          createdAt: fakeNow,
          doctorName: 'Dr. Ortho',
          roomNumber: '100',
          specializationName: 'Ortodont',
          checkedInAt: fakeNow,
          calledAt: fakeNow,
          callDeadlineAt: fakeNow.add(const Duration(seconds: 90)),
        );
        backendTickets = [ticket566, ticket565];

        wsCtrl.add(jsonEncode({
          'type': 'queue_updated',
          'clinic_id': 1,
          'queue_id': 264,
        }));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Both tickets are CALLED simultaneously with independent countdowns
        expect(
          find.descendant(
            of: find.byKey(const Key('specialist_ticket_section_566')),
            matching: find.text('Remaining time: 00:10'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('specialist_ticket_section_565')),
            matching: find.text('Remaining time: 01:30'),
          ),
          findsOneWidget,
        );

        // Doctor A automatically skips on backend -> WS triggers refresh ->
        // Doctor A transitions to SKIPPED cleanly while Doctor B keeps counting down
        ticket566 = _buildTicketJson(
          id: 566,
          queueId: 265,
          ticketNumber: 5,
          status: 'SKIPPED',
          createdAt: fakeNow,
          doctorName: 'Dr. Endo',
          roomNumber: '101',
          specializationName: 'Endodontist',
          checkedInAt: fakeNow,
          calledAt: fakeNow,
        );
        backendTickets = [ticket565, ticket566];

        wsCtrl.add(jsonEncode({
          'type': 'queue_updated',
          'clinic_id': 1,
          'queue_id': 265,
        }));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.descendant(
            of: find.byKey(const Key('specialist_ticket_section_566')),
            matching: find.byKey(const Key('skipped_banner')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('specialist_ticket_section_566')),
            matching: find.byKey(const Key('called_countdown_badge')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('specialist_ticket_section_565')),
            matching: find.byKey(const Key('called_banner')),
          ),
          findsOneWidget,
        );

        pushService.dispose();
        await wsCtrl.close();
        realtimeService.dispose();
      },
    );

    testWidgets(
      '5-7: Countdown hitting 00:00 while WS disconnected recovers SKIPPED via bounded retries and stops at limit',
      (tester) async {
        var fakeNow = DateTime.utc(2026, 11, 20, 15, 0, 0);
        Future<void> advanceSeconds(int seconds) async {
          for (var i = 0; i < seconds; i++) {
            fakeNow = fakeNow.add(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
          }
        }

        final pushService = _TestPushService();
        final wsCtrl = StreamController<dynamic>.broadcast();
        final realtimeService = QueueRealtimeService(
          channelFactory: (_) => _ControlledWebSocketChannel(wsCtrl),
        );

        var fetchCount = 0;
        var ticket566 = _buildTicketJson(
          id: 566,
          queueId: 265,
          ticketNumber: 5,
          status: 'CALLED',
          createdAt: fakeNow,
          doctorName: 'Dr. Endo',
          roomNumber: '101',
          specializationName: 'Endodontist',
          calledAt: fakeNow,
          callDeadlineAt: fakeNow.add(const Duration(seconds: 3)),
        );
        var returnSkipped = false;

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/queues/my-tickets') {
            fetchCount++;
            if (returnSkipped) {
              return http.Response(
                jsonEncode([
                  _buildTicketJson(
                    id: 566,
                    queueId: 265,
                    ticketNumber: 5,
                    status: 'SKIPPED',
                    createdAt: fakeNow,
                    doctorName: 'Dr. Endo',
                    roomNumber: '101',
                    specializationName: 'Endodontist',
                  ),
                ]),
                200,
              );
            }
            return http.Response(jsonEncode([ticket566]), 200);
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          _wrapApp(
            MyQueueScreen(
              queueService: QueueService(
                httpClient: mockClient,
                tokenStorage: _InMemoryTokenStorage(),
              ),
              pushNotificationService: pushService,
              realtimeService: realtimeService,
              nowProvider: () => fakeNow,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(fetchCount, 1);

        // Close WS stream silently (no WS update will arrive)
        await wsCtrl.close();

        // Advance 3s -> countdown reaches 00:00, NEVER mutates status locally
        await advanceSeconds(3);
        expect(find.text('Remaining time: 00:00'), findsOneWidget);
        expect(find.byKey(const Key('called_banner')), findsOneWidget);
        expect(find.byKey(const Key('skipped_banner')), findsNothing);
        expect(fetchCount, 1);

        // +2s grace delay -> Retry #1 triggers while backend still returns CALLED
        await advanceSeconds(2);
        expect(fetchCount, 2);
        expect(find.byKey(const Key('called_banner')), findsOneWidget);

        // Backend transitions to SKIPPED before Retry #2 (+3s later) -> recovers SKIPPED
        returnSkipped = true;
        await advanceSeconds(3);
        expect(fetchCount, 3);
        expect(find.byKey(const Key('skipped_banner')), findsOneWidget);
        expect(find.byKey(const Key('called_countdown_badge')), findsNothing);

        // Further ticks do not poll infinitely
        await advanceSeconds(15);
        expect(fetchCount, 3);

        pushService.dispose();
        realtimeService.dispose();
      },
    );

    testWidgets(
      '7b: Expiration recovery stops after bounded retry limit (max 3 attempts) if backend stays CALLED',
      (tester) async {
        var fakeNow = DateTime.utc(2026, 11, 20, 15, 0, 0);
        Future<void> advanceSeconds(int seconds) async {
          for (var i = 0; i < seconds; i++) {
            fakeNow = fakeNow.add(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
          }
        }

        final pushService = _TestPushService();
        final wsCtrl = StreamController<dynamic>.broadcast();
        final realtimeService = QueueRealtimeService(
          channelFactory: (_) => _ControlledWebSocketChannel(wsCtrl),
        );

        var fetchCount = 0;
        final stuckCalled = _buildTicketJson(
          id: 700,
          queueId: 270,
          ticketNumber: 1,
          status: 'CALLED',
          createdAt: fakeNow,
          doctorName: 'Dr. Limit',
          roomNumber: '105',
          specializationName: 'Surgeon',
          calledAt: fakeNow,
          callDeadlineAt: fakeNow.add(const Duration(seconds: 2)),
        );

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/queues/my-tickets') {
            fetchCount++;
            return http.Response(jsonEncode([stuckCalled]), 200);
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          _wrapApp(
            MyQueueScreen(
              queueService: QueueService(
                httpClient: mockClient,
                tokenStorage: _InMemoryTokenStorage(),
              ),
              pushNotificationService: pushService,
              realtimeService: realtimeService,
              nowProvider: () => fakeNow,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(fetchCount, 1);

        // Reach 00:00 at T=2, then +2s (attempt 1), +3s (attempt 2), +5s (attempt 3)
        await advanceSeconds(2);
        await advanceSeconds(2);
        expect(fetchCount, 2);
        await advanceSeconds(3);
        expect(fetchCount, 3);
        await advanceSeconds(5);
        expect(fetchCount, 4);

        // Advance another 30s -> must NOT keep polling past bounded limit
        await advanceSeconds(30);
        expect(fetchCount, 4);

        pushService.dispose();
        await wsCtrl.close();
        realtimeService.dispose();
      },
    );

    testWidgets(
      '10-11: Out-of-order stale HTTP response never overwrites newer CALLED data and rapid WS+FCM bursts coalesce cleanly',
      (tester) async {
        final now = DateTime.utc(2026, 11, 20, 15, 0, 0);
        final pushService = _TestPushService();
        final wsCtrl = StreamController<dynamic>.broadcast();
        final realtimeService = QueueRealtimeService(
          channelFactory: (_) => _ControlledWebSocketChannel(wsCtrl),
        );

        final waitingTicket = _buildTicketJson(
          id: 566,
          queueId: 265,
          ticketNumber: 5,
          status: 'WAITING',
          createdAt: now,
          doctorName: 'Dr. Endo',
          roomNumber: '101',
          specializationName: 'Endodontist',
        );
        final calledTicket = _buildTicketJson(
          id: 566,
          queueId: 265,
          ticketNumber: 5,
          status: 'CALLED',
          createdAt: now,
          doctorName: 'Dr. Endo',
          roomNumber: '101',
          specializationName: 'Endodontist',
          calledAt: now,
          callDeadlineAt: now.add(const Duration(seconds: 120)),
        );

        final slowInitialCompleter = Completer<http.Response>();
        final slowSilentCompleter = Completer<http.Response>();
        var requestNum = 0;

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/queues/my-tickets') {
            requestNum++;
            if (requestNum == 1) {
              // Slow initial load returning stale WAITING later
              return slowInitialCompleter.future;
            }
            if (requestNum == 2) {
              // Returns fresh CALLED immediately
              return http.Response(jsonEncode([calledTicket]), 200);
            }
            if (requestNum == 3) {
              return slowSilentCompleter.future;
            }
            return http.Response(jsonEncode([calledTicket]), 200);
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          _wrapApp(
            MyQueueScreen(
              queueService: QueueService(
                httpClient: mockClient,
                tokenStorage: _InMemoryTokenStorage(),
              ),
              pushNotificationService: pushService,
              realtimeService: realtimeService,
              nowProvider: () => now,
            ),
          ),
        );
        await tester.pump();

        // While initial load #1 is pending, WS delivers fresh update -> #2 resolves CALLED
        wsCtrl.add(jsonEncode({
          'type': 'queue_updated',
          'clinic_id': 1,
          'queue_id': 265,
        }));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const Key('called_banner')), findsOneWidget);

        // Now stale response #1 finally completes with WAITING -> must be ignored!
        slowInitialCompleter.complete(http.Response(jsonEncode([waitingTicket]), 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const Key('called_banner')), findsOneWidget);

        // Now send a rapid burst of 5 WS + FCM events while #3 is in-flight ->
        // must coalesce into only #3 + 1 trailing #4 (not 5 concurrent requests)
        wsCtrl.add(jsonEncode({'type': 'display_updated', 'clinic_id': 1, 'queue_id': 265}));
        wsCtrl.add(jsonEncode({'type': 'queue_updated', 'clinic_id': 1, 'queue_id': 265}));
        wsCtrl.add(jsonEncode({'type': 'queue_updated', 'clinic_id': 1, 'queue_id': 265}));
        pushService.emitEvent({'type': 'QUEUE_CALLED', 'ticket_id': '566', 'queue_id': '265'});
        pushService.emitEvent({'type': 'QUEUE_CALLED', 'ticket_id': '566', 'queue_id': '265'});
        await tester.pump();

        expect(requestNum, 3);

        // Finish #3 -> exactly 1 trailing coalesced request (#4) fires
        slowSilentCompleter.complete(http.Response(jsonEncode([calledTicket]), 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(requestNum, 4);

        pushService.dispose();
        await wsCtrl.close();
        realtimeService.dispose();
      },
    );

    testWidgets(
      '12-13: Temporary network failure preserves tickets, shows warning banner, recovers on reconnect/resume, and cleans up on dispose',
      (tester) async {
        final now = DateTime.utc(2026, 11, 20, 15, 0, 0);
        final pushService = _TestPushService();
        final channels = <_ControlledWebSocketChannel>[];
        final realtimeService = QueueRealtimeService(
          channelFactory: (_) {
            final ch = _ControlledWebSocketChannel(StreamController<dynamic>.broadcast());
            channels.add(ch);
            return ch;
          },
        );

        var networkDown = false;
        var currentStatus = 'WAITING';
        var fetchCount = 0;

        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/queues/my-tickets') {
            fetchCount++;
            if (networkDown) {
              throw const SocketException('Connection refused');
            }
            return http.Response(
              jsonEncode([
                _buildTicketJson(
                  id: 566,
                  queueId: 265,
                  ticketNumber: 5,
                  status: currentStatus,
                  createdAt: now,
                  doctorName: 'Dr. Endo',
                  roomNumber: '101',
                  specializationName: 'Endodontist',
                ),
              ]),
              200,
            );
          }
          return http.Response('Not Found', 404);
        });

        await tester.pumpWidget(
          _wrapApp(
            MyQueueScreen(
              queueService: QueueService(
                httpClient: mockClient,
                tokenStorage: _InMemoryTokenStorage(),
              ),
              pushNotificationService: pushService,
              realtimeService: realtimeService,
              nowProvider: () => now,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Confirm initial WS handshake
        channels.first.controller.add(jsonEncode({'type': 'connected', 'clinic_id': 1}));
        await tester.pump();
        expect(find.text('№5'), findsOneWidget);
        expect(find.byKey(const Key('my_queue_connection_warning')), findsNothing);

        // Drop WS & simulate backend unreachable during refresh
        networkDown = true;
        currentStatus = 'CALLED';
        await channels.first.controller.close();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Ticket stays preserved, warning is shown, and no false CALLED transition occurred
        expect(find.text('№5'), findsOneWidget);
        expect(find.byKey(const Key('called_banner')), findsNothing);
        expect(find.byKey(const Key('my_queue_connection_warning')), findsOneWidget);

        // Network returns & WS reconnects after 1s -> auto-refresh updates to CALLED and clears warning
        networkDown = false;
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));
        expect(channels.length, greaterThanOrEqualTo(2));
        channels.last.controller.add(jsonEncode({'type': 'connected', 'clinic_id': 1}));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(fetchCount, greaterThanOrEqualTo(2));
        expect(find.byKey(const Key('called_banner')), findsOneWidget);
        expect(find.byKey(const Key('my_queue_connection_warning')), findsNothing);

        // Dispose screen cleanly -> disconnects consumer and cancels timers without errors
        await tester.pumpWidget(_wrapApp(const Scaffold(body: Text('Done'))));
        await tester.pumpAndSettle();

        pushService.dispose();
        for (final ch in channels) {
          await ch.controller.close();
        }
        realtimeService.dispose();
      },
    );
  });
}
