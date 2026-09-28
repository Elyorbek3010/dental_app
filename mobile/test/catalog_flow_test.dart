import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/models/doctor.dart';
import 'package:app/models/doctor_queue.dart';
import 'package:app/models/specialization.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/screens/doctor_select_screen.dart';
import 'package:app/screens/specialization_select_screen.dart';
import 'package:app/services/catalog_service.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Catalog Models and Service Tests', () {
    test('Specialization fromJson and toJson use real backend schema', () {
      final json = {
        'id': 1,
        'clinic_id': 1,
        'name': 'Ortodontiya',
      };
      final spec = Specialization.fromJson(json);
      expect(spec.id, 1);
      expect(spec.clinicId, 1);
      expect(spec.name, 'Ortodontiya');
      expect(spec.toJson(), equals(json));
    });

    test('Doctor fromJson and toJson use real backend schema', () {
      final json = {
        'id': 12,
        'clinic_id': 1,
        'specialization_id': 2,
        'full_name': 'Dr. Ziyoda Alimova',
        'room_number': '104',
        'is_active': true,
      };
      final doc = Doctor.fromJson(json);
      expect(doc.id, 12);
      expect(doc.fullName, 'Dr. Ziyoda Alimova');
      expect(doc.roomNumber, '104');
      expect(doc.isActive, isTrue);
      expect(doc.toJson(), equals(json));
    });

    test('DoctorQueue fromJson and toJson use real backend schema', () {
      final json = {
        'id': 34,
        'doctor_id': 12,
        'queue_date': '2026-09-28',
        'is_paused': false,
        'is_active': true,
      };
      final q = DoctorQueue.fromJson(json);
      expect(q.id, 34);
      expect(q.doctorId, 12);
      expect(q.queueDate, '2026-09-28');
      expect(q.isPaused, isFalse);
      expect(q.isActive, isTrue);
      expect(q.toJson(), equals(json));
    });

    test('CatalogService fetchDoctorQueue returns null on 404 (no queue today)', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors/99/queue') {
          return http.Response(
            jsonEncode({'detail': 'No active queue for this doctor today'}),
            404,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: InMemoryTokenStorage(),
      );

      final queue = await service.fetchDoctorQueue(99);
      expect(queue, isNull);
    });
  });

  group('Catalog UI Flow Widget Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      tokenStorage = InMemoryTokenStorage();
    });

    Widget wrapWithTheme(Widget child) {
      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
      );
    }

    void setMobileDimensions(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('1. Specialization screen loads and renders backend specializations',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/specializations') {
          expect(request.url.queryParameters['clinic_id'], '1');
          return http.Response(
            jsonEncode([
              {'id': 1, 'clinic_id': 1, 'name': 'Terapiya'},
              {'id': 2, 'clinic_id': 1, 'name': 'Jarrohlik'},
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          SpecializationSelectScreen(catalogService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mutaxassislikni tanlash'), findsOneWidget);
      expect(find.text('Terapiya'), findsOneWidget);
      expect(find.text('Jarrohlik'), findsOneWidget);
    });

    testWidgets('2. Specialization empty state renders when none available',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/specializations') {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          SpecializationSelectScreen(catalogService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mutaxassisliklar topilmadi'), findsOneWidget);
    });

    testWidgets('3. Specialization API failure displays retry button and recovers on retry',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      var shouldFail = true;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/specializations') {
          if (shouldFail) {
            return http.Response(jsonEncode({'detail': 'Server error'}), 500);
          }
          return http.Response(
            jsonEncode([
              {'id': 3, 'clinic_id': 1, 'name': 'Ortopediya'},
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          SpecializationSelectScreen(catalogService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('specialization_retry_button')), findsOneWidget);

      // Now fix mock and tap retry
      shouldFail = false;
      await tester.tap(find.byKey(const Key('specialization_retry_button')));
      await tester.pumpAndSettle();

      expect(find.text('Ortopediya'), findsOneWidget);
    });

    testWidgets('4. Selecting specialization opens DoctorSelectScreen and shows filtered doctors',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/specializations') {
          return http.Response(
            jsonEncode([
              {'id': 1, 'clinic_id': 1, 'name': 'Terapiya'},
            ]),
            200,
          );
        }
        if (request.url.path == '/api/catalog/doctors') {
          expect(request.url.queryParameters['specialization_id'], '1');
          return http.Response(
            jsonEncode([
              {
                'id': 101,
                'clinic_id': 1,
                'specialization_id': 1,
                'full_name': 'Dr. Aziz Rahimov',
                'room_number': '201',
                'is_active': true,
              },
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          SpecializationSelectScreen(catalogService: service),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Terapiya
      await tester.tap(find.text('Terapiya'));
      await tester.pumpAndSettle();

      // Doctor screen opens
      expect(find.byType(DoctorSelectScreen), findsOneWidget);
      expect(find.text('Shifokorni tanlash'), findsOneWidget);
      expect(find.text('Dr. Aziz Rahimov'), findsOneWidget);
      expect(find.text('201-xona'), findsOneWidget);
    });

    testWidgets('5. Doctor empty state appears when specialization has no doctors',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors') {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          DoctorSelectScreen(
            specialization: const Specialization(
              id: 2,
              clinicId: 1,
              name: 'Bolalar stomatologiyasi',
            ),
            catalogService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shifokorlar topilmadi'), findsOneWidget);
      expect(
        find.text(
          'Bolalar stomatologiyasi mutaxassisligi bo‘yicha hozirda faol shifokorlar mavjud emas.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('6. Selecting doctor opens DoctorQueueScreen and renders today active queue',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors') {
          return http.Response(
            jsonEncode([
              {
                'id': 50,
                'clinic_id': 1,
                'specialization_id': 1,
                'full_name': 'Dr. Kamol Boboyev',
                'room_number': '105',
                'is_active': true,
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/api/catalog/doctors/50/queue') {
          return http.Response(
            jsonEncode({
              'id': 700,
              'doctor_id': 50,
              'queue_date': '2026-09-28',
              'is_paused': false,
              'is_active': true,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          DoctorSelectScreen(
            specialization: const Specialization(
              id: 1,
              clinicId: 1,
              name: 'Terapiya',
            ),
            catalogService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on doctor
      await tester.tap(find.text('Dr. Kamol Boboyev'));
      await tester.pumpAndSettle();

      // DoctorQueueScreen opens
      expect(find.byType(DoctorQueueScreen), findsOneWidget);
      expect(find.text('Navbat maʼlumotlari'), findsOneWidget);
      expect(find.text('Dr. Kamol Boboyev'), findsOneWidget);
      expect(find.text('105-xona'), findsOneWidget);
      expect(find.text('Bugungi navbat holati'), findsOneWidget);
      expect(find.text('Faol'), findsOneWidget);
      expect(find.text('2026-09-28'), findsOneWidget);
      expect(find.text('#700'), findsNothing);
      expect(find.byKey(const Key('doctor_queue_join_button')), findsOneWidget);
      expect(find.text('Navbatga qo‘shilish'), findsOneWidget);
    });

    testWidgets('7. Doctor with no active queue today shows clear empty state',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/catalog/doctors/51/queue') {
          return http.Response(
            jsonEncode({'detail': 'No active queue for this doctor today'}),
            404,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = CatalogService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          DoctorQueueScreen(
            doctor: const Doctor(
              id: 51,
              clinicId: 1,
              specializationId: 1,
              fullName: 'Dr. Nodir Saidov',
              roomNumber: '102',
              isActive: true,
            ),
            specialization: const Specialization(
              id: 1,
              clinicId: 1,
              name: 'Terapiya',
            ),
            catalogService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bugun navbat mavjud emas'), findsOneWidget);
      expect(find.byKey(const Key('doctor_queue_join_button')), findsNothing);
    });
  });
}
