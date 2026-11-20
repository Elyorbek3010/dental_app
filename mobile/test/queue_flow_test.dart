import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/services/catalog_service.dart';
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

/// Wraps [child] in a MaterialApp with UZ AppLocalizations delegates.
/// Use this for widget tests that render screens using context.l10n.
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

  final sampleJoinedTicketJson = {
    'id': 99,
    'queue_id': 45,
    'patient_id': 7,
    'ticket_number': 3,
    'queue_position': 3,
    'patient_name': 'Ali Valiyev',
    'patient_phone': '+998901234567',
    'source': 'ONLINE',
    'status': 'WAITING',
    'created_at': '2026-09-28T09:00:00.000Z',
    'checked_in_at': null,
    'check_in_method': null,
    'missed_turns': 0,
  };

  final sampleMyTicketJson = {
    'id': 99,
    'queue_id': 45,
    'ticket_number': 3,
    'status': 'WAITING',
    'created_at': '2026-09-28T09:00:00.000Z',
    'people_ahead': 2,
    'checked_in_at': null,
    'check_in_method': null,
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

  group('Queue Models and Mapping Tests', () {
    test('QueueTicket parses from real backend response and maps status to Uzbek', () {
      final ticket = QueueTicket.fromJson(sampleJoinedTicketJson);
      expect(ticket.id, 99);
      expect(ticket.queueId, 45);
      expect(ticket.ticketNumber, 3);
      expect(ticket.queuePosition, 3);
      expect(ticket.patientName, 'Ali Valiyev');
      expect(ticket.source, 'ONLINE');
      expect(ticket.status, 'WAITING');
      expect(ticket.statusLabel, 'Kutilmoqda');
      expect(ticket.isCheckedIn, isFalse);
    });

    test('MyQueueTicket parses from real backend response', () {
      final myTicket = MyQueueTicket.fromJson(sampleMyTicketJson);
      expect(myTicket.id, 99);
      expect(myTicket.queueId, 45);
      expect(myTicket.ticketNumber, 3);
      expect(myTicket.status, 'WAITING');
      expect(myTicket.statusLabel, 'Kutilmoqda');
      expect(myTicket.peopleAhead, 2);
      expect(myTicket.doctor.fullName, 'Dr. Ziyoda Alimova');
      expect(myTicket.doctor.roomNumber, '104');
      expect(myTicket.specialization.name, 'Ortodontiya');
      expect(myTicket.isCheckedIn, isFalse);
    });

    test('Status label translations cover all backend statuses accurately', () {
      const statuses = {
        'WAITING': 'Kutilmoqda',
        'CALLED': 'Navbatingiz keldi',
        'SERVING': 'Qabul davom etmoqda',
        'COMPLETED': 'Yakunlandi',
        'SKIPPED': "O‘tkazib yuborildi",
        'CANCELLED': 'Bekor qilingan',
      };

      for (final entry in statuses.entries) {
        final ticket = MyQueueTicket.fromJson({
          ...sampleMyTicketJson,
          'status': entry.key,
        });
        expect(ticket.statusLabel, entry.value);
      }
    });

    test('QueueStatus parses from backend schema', () {
      final status = QueueStatus.fromJson({
        'queue_id': 45,
        'doctor_id': 12,
        'is_paused': false,
        'waiting_count': 5,
      });
      expect(status.queueId, 45);
      expect(status.doctorId, 12);
      expect(status.isPaused, isFalse);
      expect(status.waitingCount, 5);
    });
  });

  group('QueueService API Tests', () {
    test('joinQueue successfully returns QueueTicket on 201', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/queues/45/join') &&
            request.method == 'POST') {
          return http.Response(jsonEncode(sampleJoinedTicketJson), 201);
        }
        return http.Response('Not Found', 404);
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final ticket = await service.joinQueue(45);
      expect(ticket.ticketNumber, 3);
      expect(ticket.status, 'WAITING');
      expect(ticket.queuePosition, 3);
    });

    test('joinQueue throws QueueConflictException with isAlreadyActive on 409 duplicate', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Patient already has an active ticket in this queue',
          }),
          409,
        );
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      expect(
        () => service.joinQueue(45),
        throwsA(isA<QueueConflictException>()
            .having((e) => e.isAlreadyActive, 'isAlreadyActive', isTrue)
            .having(
              (e) => e.message,
              'message',
              'Sizda allaqachon ushbu navbatda faol talon mavjud.',
            )),
      );
    });

    test('getMyTicket returns MyQueueTicket on 200', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/queues/my-ticket')) {
          return http.Response(jsonEncode(sampleMyTicketJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final ticket = await service.getMyTicket();
      expect(ticket, isNotNull);
      expect(ticket!.ticketNumber, 3);
      expect(ticket.peopleAhead, 2);
      expect(ticket.doctor.fullName, 'Dr. Ziyoda Alimova');
    });

    test('getMyTicket returns null on 404 (no active ticket)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'No active queue ticket found'}),
          404,
        );
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final ticket = await service.getMyTicket();
      expect(ticket, isNull);
    });
  });

  group('DoctorQueueScreen Join UI Tests', () {
    testWidgets('DoctorQueueScreen shows active queue and enables Join button',
        (WidgetTester tester) async {
      final mockCatalogClient = MockClient((request) async {
        if (request.url.path.contains('/api/catalog/doctors/12/queue')) {
          return http.Response(jsonEncode(sampleQueue.toJson()), 200);
        }
        return http.Response('Not Found', 404);
      });

      final catalogService = CatalogService(
        httpClient: mockCatalogClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: DoctorQueueScreen(
            doctor: sampleDoctor,
            specialization: sampleSpecialization,
            catalogService: catalogService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Bugungi navbat holati'), findsOneWidget);
      expect(find.text("Navbatga qo‘shilish"), findsOneWidget);
      // Verify internal queue ID is NOT displayed
      expect(find.text('#45'), findsNothing);
      expect(find.text('Navbat ID'), findsNothing);
    });

    testWidgets('Pressing Join calls queue join API and shows double-tap protection',
        (WidgetTester tester) async {
      int joinCallCount = 0;

      final mockCatalogClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleQueue.toJson()), 200);
      });

      final mockQueueClient = MockClient((request) async {
        if (request.url.path.contains('/api/queues/45/join')) {
          joinCallCount++;
          // Delay response slightly to verify loading state
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(jsonEncode(sampleJoinedTicketJson), 201);
        }
        if (request.url.path.contains('/api/queues/my-ticket')) {
          return http.Response(jsonEncode(sampleMyTicketJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final catalogService = CatalogService(
        httpClient: mockCatalogClient,
        tokenStorage: InMemoryTokenStorage(),
      );
      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: DoctorQueueScreen(
            doctor: sampleDoctor,
            specialization: sampleSpecialization,
            catalogService: catalogService,
            queueService: queueService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final joinButtonFinder = find.byKey(const Key('doctor_queue_join_button'));
      expect(joinButtonFinder, findsOneWidget);

      // Tap join button
      await tester.tap(joinButtonFinder);
      await tester.pump(); // Start request

      // Verify loading state is shown and button text changes
      expect(find.text('Yuklanmoqda...'), findsOneWidget);

      // Attempt double tap while loading
      await tester.tap(joinButtonFinder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Only one join call was made
      expect(joinCallCount, 1);
    });

    testWidgets('Duplicate join (409) displays alert dialog with navigation option',
        (WidgetTester tester) async {
      final mockCatalogClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleQueue.toJson()), 200);
      });

      final mockQueueClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Patient already has an active ticket in this queue',
          }),
          409,
        );
      });

      final catalogService = CatalogService(
        httpClient: mockCatalogClient,
        tokenStorage: InMemoryTokenStorage(),
      );
      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: DoctorQueueScreen(
            doctor: sampleDoctor,
            specialization: sampleSpecialization,
            catalogService: catalogService,
            queueService: queueService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('doctor_queue_join_button')));
      await tester.pumpAndSettle();

      expect(find.text('Faol navbat mavjud'), findsOneWidget);
      expect(
        find.text('Sizda allaqachon ushbu navbatda faol talon mavjud.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('conflict_dialog_go_to_ticket')), findsOneWidget);
    });
  });

  group('MyQueueScreen Real Ticket UI Tests', () {
    testWidgets('MyQueueScreen displays empty state when patient has no active ticket',
        (WidgetTester tester) async {
      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([]), 200);
        }
        if (request.url.path.contains('/api/queues/my-ticket')) {
          return http.Response(jsonEncode({'detail': 'No active queue ticket found'}), 404);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("Faol navbatingiz yo‘q"), findsOneWidget);
      expect(find.text('Navbatga yozilish'), findsOneWidget);
      expect(find.text('Navbat imkoniyatlari:'), findsOneWidget);
    });

    testWidgets('MyQueueScreen renders real active ticket from backend correctly',
        (WidgetTester tester) async {
      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([sampleMyTicketJson]), 200);
        }
        if (request.url.path.contains('/api/queues/my-ticket')) {
          return http.Response(jsonEncode(sampleMyTicketJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );

      await tester.pumpAndSettle();

      // Primary patient identity №{ticket_number}
      expect(find.text('№3'), findsOneWidget);

      // Status badge with Uzbek label
      expect(find.text('Kutilmoqda'), findsOneWidget);

      // People ahead directly from backend
      expect(find.text('Oldingizda 2 kishi bor'), findsOneWidget);

      // Doctor, Specialization, Room details
      expect(find.text('Dr. Ziyoda Alimova'), findsOneWidget);
      expect(find.text('Ortodontiya'), findsOneWidget);
      expect(find.text('Xona: 104'), findsOneWidget);

      // Check-in status display
      expect(find.text("Klinikada ro‘yxatdan o‘tilmagan"), findsOneWidget);

      // Verify internal IDs (99, 45, 7) are NOT rendered in the patient UI
      expect(find.text('#99'), findsNothing);
      expect(find.text('#45'), findsNothing);
      expect(find.text('Queue ID'), findsNothing);
      expect(find.text('Ticket ID'), findsNothing);
    });

    testWidgets('MyQueueScreen renders checked-in state when ticket is checked in',
        (WidgetTester tester) async {
      final checkedInJson = {
        ...sampleMyTicketJson,
        'checked_in_at': '2026-09-28T09:15:00.000Z',
        'check_in_method': 'QR',
      };

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([checkedInJson]), 200);
        }
        return http.Response(jsonEncode(checkedInJson), 200);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(MyQueueScreen(queueService: queueService)),
      );

      await tester.pumpAndSettle();

      // checkedInStatusTitle in uz = "Klinikada ro'yxatdan o'tilgan"
      expect(find.text("Klinikada ro‘yxatdan o‘tilgan"), findsOneWidget);
    });

    testWidgets('MyQueueScreen pull-to-refresh fetches updated ticket state',
        (WidgetTester tester) async {
      int fetchCount = 0;

      final mockQueueClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          final ticketJson = fetchCount == 1
              ? sampleMyTicketJson
              : {...sampleMyTicketJson, 'people_ahead': 1};
          return http.Response(jsonEncode([ticketJson]), 200);
        }
        if (request.url.path.contains('/api/queues/my-ticket')) {
          fetchCount++;
          if (fetchCount == 1) {
            return http.Response(jsonEncode(sampleMyTicketJson), 200);
          } else {
            // Second fetch: people_ahead updated to 1
            return http.Response(
              jsonEncode({
                ...sampleMyTicketJson,
                'people_ahead': 1,
              }),
              200,
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockQueueClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Oldingizda 2 kishi bor'), findsOneWidget);
      expect(fetchCount, 1);

      // Trigger pull to refresh
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0.0, 300.0),
        1000.0,
      );
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      expect(find.text('Oldingizda 1 kishi bor'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // QR Check-in Service Tests
  // ---------------------------------------------------------------------------

  group('QueueService QR Check-in Tests', () {
    test('checkInWithQr sends token and returns QueueTicket on 200', () async {
      final checkedInJson = {
        'id': 99,
        'queue_id': 45,
        'patient_id': 7,
        'ticket_number': 3,
        'queue_position': 3,
        'patient_name': 'Ali Valiyev',
        'patient_phone': '+998901234567',
        'source': 'ONLINE',
        'status': 'WAITING',
        'created_at': '2026-09-28T09:00:00.000Z',
        'checked_in_at': '2026-09-28T09:15:00.000Z',
        'check_in_method': 'QR',
        'missed_turns': 0,
      };

      String? sentToken;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/queues/check-in/qr') &&
            request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentToken = body['token'] as String?;
          return http.Response(jsonEncode(checkedInJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final ticket = await service.checkInWithQr('test_qr_token_value');
      expect(ticket.checkInMethod, 'QR');
      expect(ticket.checkedInAt, isNotNull);
      expect(sentToken, 'test_qr_token_value');
    });

    test('checkInWithQr throws QueueException on 400 (invalid token)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Invalid or expired check-in QR code'}),
          400,
        );
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      expect(
        () => service.checkInWithQr('bad_token'),
        throwsA(isA<QueueException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('checkInWithQr throws QueueConflictException on 409 (already checked in)',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Ticket is already checked in'}),
          409,
        );
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      expect(
        () => service.checkInWithQr('some_token'),
        throwsA(isA<QueueConflictException>()),
      );
    });

    test('checkInWithQr throws QueueException on 404 (no waiting ticket for clinic)',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'No active waiting ticket found for this clinic'}),
          404,
        );
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      expect(
        () => service.checkInWithQr('some_token'),
        throwsA(isA<QueueException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Cancellation Service Tests
  // ---------------------------------------------------------------------------

  group('QueueService Cancellation Tests', () {
    test('cancelTicket cancels own ticket and returns QueueTicket with CANCELLED status',
        () async {
      final cancelledJson = {
        'id': 99,
        'queue_id': 45,
        'patient_id': 7,
        'ticket_number': 3,
        'queue_position': 3,
        'patient_name': 'Ali Valiyev',
        'patient_phone': '+998901234567',
        'source': 'ONLINE',
        'status': 'CANCELLED',
        'created_at': '2026-09-28T09:00:00.000Z',
        'checked_in_at': null,
        'check_in_method': null,
        'missed_turns': 0,
      };

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/queues/my-ticket/cancel') &&
            request.method == 'PATCH') {
          return http.Response(jsonEncode(cancelledJson), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final ticket = await service.cancelTicket();
      expect(ticket.status, 'CANCELLED');
    });

    test('cancelTicket throws QueueException on 403 (own-ticket protection)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': "Cannot cancel another patient's ticket"}),
          403,
        );
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      expect(
        () => service.cancelTicket(),
        throwsA(isA<QueueException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('cancelTicket throws QueueException on 404 (no cancellable ticket)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'No active ticket found to cancel'}),
          404,
        );
      });

      final service = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      expect(
        () => service.cancelTicket(),
        throwsA(isA<QueueException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Lifecycle UI Tests  (CALLED / SERVING / internal IDs hidden)
  // ---------------------------------------------------------------------------

  group('MyQueueScreen Lifecycle & Localization UI Tests', () {
    testWidgets('CALLED status shows prominent called banner and cancel button',
        (WidgetTester tester) async {
      final calledTicketJson = {
        ...sampleMyTicketJson,
        'status': 'CALLED',
      };

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([calledTicketJson]), 200);
        }
        return http.Response(jsonEncode(calledTicketJson), 200);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );
      await tester.pumpAndSettle();

      // Called banner should be visible with Uzbek text
      expect(find.byKey(const Key('called_banner')), findsOneWidget);
      expect(find.text('Navbatingiz keldi'), findsWidgets);

      // Cancel button should be visible for CALLED status
      expect(find.byKey(const Key('cancel_ticket_button')), findsOneWidget);

      // Internal ticket/queue IDs must not be shown
      expect(find.text('99'), findsNothing);
      expect(find.text('45'), findsNothing);
    });

    testWidgets('SERVING status shows serving banner and hides cancel button',
        (WidgetTester tester) async {
      final servingTicketJson = {
        ...sampleMyTicketJson,
        'status': 'SERVING',
      };

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([servingTicketJson]), 200);
        }
        return http.Response(jsonEncode(servingTicketJson), 200);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );
      await tester.pumpAndSettle();

      // Serving banner should appear
      expect(find.byKey(const Key('serving_banner')), findsOneWidget);
      expect(find.text('Qabul davom etmoqda'), findsWidgets);

      // Cancel button must NOT appear for SERVING
      expect(find.byKey(const Key('cancel_ticket_button')), findsNothing);
    });

    testWidgets('Cancel confirmation dialog appears and resolves correctly on "No"',
        (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([sampleMyTicketJson]), 200);
        }
        return http.Response(jsonEncode(sampleMyTicketJson), 200);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(MyQueueScreen(queueService: queueService)),
      );
      await tester.pumpAndSettle();

      // Scroll to cancel button (it may be below the fold)
      await tester.ensureVisible(find.byKey(const Key('cancel_ticket_button')));
      await tester.pumpAndSettle();

      // Tap cancel button
      await tester.tap(find.byKey(const Key('cancel_ticket_button')));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.byKey(const Key('cancel_confirm_dialog')), findsOneWidget);
      expect(find.text('Talonni bekor qilasizmi?'), findsOneWidget);

      // Tap "No, Keep"
      await tester.tap(find.byKey(const Key('cancel_confirm_no_button')));
      await tester.pumpAndSettle();

      // Dialog dismissed; ticket still shown
      expect(find.text('№3'), findsOneWidget);
    });

    testWidgets('Cancel + successful API removes ticket and shows empty state',
        (WidgetTester tester) async {
      int fetchCount = 0;

      final mockClient = MockClient((request) async {
        if ((request.url.path.contains('/my-ticket/cancel') ||
                request.url.path == '/api/queues/45/tickets/99/cancel') &&
            request.method == 'PATCH') {
          return http.Response(
            jsonEncode({...sampleMyTicketJson, 'status': 'CANCELLED',
              'id': 99, 'queue_id': 45, 'patient_id': 7,
              'ticket_number': 3, 'queue_position': 3,
              'patient_name': 'Ali', 'patient_phone': null,
              'source': 'ONLINE', 'created_at': '2026-09-28T09:00:00.000Z',
              'missed_turns': 0}),
            200,
          );
        }
        if (request.url.path == '/api/queues/my-tickets') {
          fetchCount++;
          return http.Response(
            jsonEncode(fetchCount <= 1 ? [sampleMyTicketJson] : []),
            200,
          );
        }
        if (request.url.path.contains('/api/queues/my-ticket')) {
          fetchCount++;
          if (fetchCount <= 1) {
            return http.Response(jsonEncode(sampleMyTicketJson), 200);
          }
          // After cancel, no active ticket
          return http.Response(
            jsonEncode({'detail': 'No active queue ticket found'}),
            404,
          );
        }
        return http.Response('Not Found', 404);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        localizedApp(MyQueueScreen(queueService: queueService)),
      );
      await tester.pumpAndSettle();
      expect(find.text('№3'), findsOneWidget);

      // Scroll to cancel button and tap
      await tester.ensureVisible(find.byKey(const Key('cancel_ticket_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel_ticket_button')));
      await tester.pumpAndSettle();

      // Confirm cancel
      await tester.tap(find.byKey(const Key('cancel_confirm_yes_button')));
      await tester.pumpAndSettle();

      // Empty state should now show
      expect(find.text("Faol navbatingiz yo‘q"), findsOneWidget);
    });

    testWidgets('Internal ticket/queue IDs and tokens are never shown to patient',
        (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([sampleMyTicketJson]), 200);
        }
        return http.Response(jsonEncode(sampleMyTicketJson), 200);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ID: 99'), findsNothing);
      expect(find.text('ID: 45'), findsNothing);
      expect(find.text('patient_id'), findsNothing);
      expect(find.text('queue_id'), findsNothing);
      expect(find.text('7'), findsNothing);
    });

    testWidgets('WAITING ticket shows QR check-in button (not yet checked in)',
        (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([sampleMyTicketJson]), 200);
        }
        return http.Response(jsonEncode(sampleMyTicketJson), 200);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );
      await tester.pumpAndSettle();

      // QR check-in button should appear for WAITING + not checked in
      expect(find.byKey(const Key('qr_checkin_button')), findsOneWidget);
    });

    testWidgets('WAITING + already checked in hides QR check-in buttons',
        (WidgetTester tester) async {
      final checkedInJson = {
        ...sampleMyTicketJson,
        'checked_in_at': '2026-09-28T09:15:00.000Z',
        'check_in_method': 'QR',
      };

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/queues/my-tickets') {
          return http.Response(jsonEncode([checkedInJson]), 200);
        }
        return http.Response(jsonEncode(checkedInJson), 200);
      });

      final queueService = QueueService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MyQueueScreen(queueService: queueService),
        ),
      );
      await tester.pumpAndSettle();

      // Already checked in → QR buttons should be hidden
      expect(find.byKey(const Key('qr_checkin_button')), findsNothing);
    });
  });
}
