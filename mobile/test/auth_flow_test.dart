import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/models/patient_ticket.dart';
import 'package:app/screens/auth_gate.dart';
import 'package:app/screens/login_screen.dart';
import 'package:app/screens/patient_shell.dart';
import 'package:app/screens/profile_screen.dart';
import 'package:app/screens/register_screen.dart';
import 'package:app/services/auth_controller.dart';
import 'package:app/services/auth_service.dart';
import 'package:app/services/local_notification_service.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/services/reminder_service.dart';
import 'package:app/services/secure_token_storage.dart';
import 'package:app/theme/app_theme.dart';

class InMemoryTokenStorage implements SecureTokenStorage {
  String? accessToken;
  String? refreshToken;

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

class FakePushNotificationService implements PushNotificationService {
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
  }) async {}

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

  final StreamController<Map<String, dynamic>> _queueEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get queueEvents => _queueEventController.stream;

  @override
  void notifyQueueEvent(Map<String, dynamic> data) {
    if (!_queueEventController.isClosed) {
      _queueEventController.add(data);
    }
  }

  @override
  void handleRemoteMessage(RemoteMessage message) {
    if (PushNotificationService.isQueueEvent(message.data)) {
      notifyQueueEvent(message.data);
    }
  }

  @override
  void setupInteractionListeners() {}

  @override
  Future<void> checkInitialMessage() async {}

  @override
  void setupTokenRefreshListener() {}

  @override
  void ensureListeners() {}

  @override
  void setupForegroundMessageListener() {}

  @override
  void dispose() {
    _queueEventController.close();
  }
}

class FakeLocalNotificationService implements LocalNotificationService {
  @override
  bool get isInitialized => true;

  @override
  Future<bool> initialize({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async =>
      true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async =>
      true;

  @override
  Future<bool> cancelNotification(int id) async => true;

  @override
  Future<bool> cancelAllNotifications() async => true;

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async => [];
}

class FakeQueueService extends QueueService {
  @override
  Future<MyQueueTicket?> getMyTicket() async => null;

  @override
  Future<List<MyQueueTicket>> getMyTickets() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Patient Auth Flow Widget Tests', () {
    late InMemoryTokenStorage tokenStorage;
    late FakePushNotificationService pushService;
    late ReminderService reminderService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tokenStorage = InMemoryTokenStorage();
      pushService = FakePushNotificationService();
      QueueService.instance = FakeQueueService();
      reminderService = ReminderService(
        notificationService: FakeLocalNotificationService(),
        initialPreferences: prefs,
      );
    });

    Widget createAuthApp({
      required AuthController authController,
    }) {
      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: AuthGate(
          authController: authController,
          reminderService: reminderService,
        ),
      );
    }

    void setMobileDimensions(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('1. Unauthenticated startup routes to LoginScreen',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final authService = AuthService(
        httpClient: MockClient((_) async => http.Response('Not Found', 404)),
        tokenStorage: tokenStorage,
        pushService: pushService,
      );
      final authController = AuthController(authService: authService);

      await tester.pumpWidget(createAuthApp(authController: authController));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Dental Queue'), findsOneWidget);
      expect(find.byKey(const Key('login_phone_field')), findsOneWidget);
      expect(find.byKey(const Key('login_password_field')), findsOneWidget);
      expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
      expect(find.byKey(const Key('login_to_register_link')), findsOneWidget);
    });

    testWidgets('2. Login screen navigates to Register and back',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final authService = AuthService(
        httpClient: MockClient((_) async => http.Response('Not Found', 404)),
        tokenStorage: tokenStorage,
        pushService: pushService,
      );
      final authController = AuthController(authService: authService);

      await tester.pumpWidget(createAuthApp(authController: authController));
      await tester.pumpAndSettle();

      // Tap on 'Ro‘yxatdan o‘tish' link
      await tester.tap(find.byKey(const Key('login_to_register_link')));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('Bemor hisobini yaratish'), findsOneWidget);
      expect(find.byKey(const Key('register_name_field')), findsOneWidget);
      expect(find.byKey(const Key('register_phone_field')), findsOneWidget);
      expect(find.byKey(const Key('register_password_field')), findsOneWidget);

      // Tap back button
      await tester.tap(find.byTooltip('Ortga'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('3. Successful login transitions app to PatientShell',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'valid_access_token',
              'refresh_token': 'valid_refresh_token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 1,
              'full_name': 'Jasur Bekov',
              'phone': '+998901234567',
              'role': 'PATIENT',
              'is_active': true,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: pushService,
      );
      final authController = AuthController(authService: authService);

      await tester.pumpWidget(createAuthApp(authController: authController));
      await tester.pumpAndSettle();

      // Fill in credentials
      await tester.enterText(
        find.byKey(const Key('login_phone_field')),
        '+998901234567',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'password123',
      );

      // Tap login
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      // App should transition to PatientShell
      expect(find.byType(PatientShell), findsOneWidget);
      expect(find.text('Asosiy'), findsOneWidget);
      expect(authController.isAuthenticated, isTrue);
      expect(authController.currentUser?.fullName, 'Jasur Bekov');
    });

    testWidgets('4. Invalid login displays clear error and remains on LoginScreen',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({'detail': 'Invalid credentials'}),
            401,
          );
        }
        return http.Response('Not Found', 404);
      });

      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: pushService,
      );
      final authController = AuthController(authService: authService);

      await tester.pumpWidget(createAuthApp(authController: authController));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('login_phone_field')),
        '+998909999999',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'wrongpassword',
      );

      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Telefon raqam yoki parol noto‘g‘ri.'), findsWidgets);
      expect(authController.isAuthenticated, isFalse);
    });

    testWidgets('5. Restored valid session routes directly to PatientShell on startup',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      await tokenStorage.saveTokens(
        accessToken: 'saved_jwt',
        refreshToken: 'saved_refresh',
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 77,
              'full_name': 'Malika Karimova',
              'phone': '+998931112233',
              'role': 'PATIENT',
              'is_active': true,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: pushService,
      );
      final authController = AuthController(authService: authService);

      await tester.pumpWidget(createAuthApp(authController: authController));
      await tester.pumpAndSettle();

      // Directly on PatientShell
      expect(find.byType(PatientShell), findsOneWidget);
      expect(authController.isAuthenticated, isTrue);
      expect(authController.currentUser?.fullName, 'Malika Karimova');
    });

    testWidgets('6. Profile screen displays authenticated backend fields and handles logout',
        (WidgetTester tester) async {
      setMobileDimensions(tester);

      await tokenStorage.saveTokens(
        accessToken: 'test_token',
        refreshToken: 'test_refresh',
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 99,
              'clinic_id': 1,
              'full_name': 'Sardor Rahimiy',
              'phone': '+998971112233',
              'role': 'PATIENT',
              'is_active': true,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: pushService,
      );
      final authController = AuthController(authService: authService);

      await tester.pumpWidget(createAuthApp(authController: authController));
      await tester.pumpAndSettle();

      // Navigate to Profile tab
      await tester.tap(find.byKey(const Key('nav_profile')));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      // Backend fields displayed
      expect(find.text('Sardor Rahimiy'), findsOneWidget);
      expect(find.text('+998971112233'), findsOneWidget);
      expect(find.text('Bemor (PATIENT)'), findsOneWidget);
      expect(find.text('Faol hisob'), findsOneWidget);

      // Tap logout button
      await tester.ensureVisible(find.byKey(const Key('profile_logout_button')));
      await tester.tap(find.byKey(const Key('profile_logout_button')));
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Tizimdan chiqish'), findsWidgets);
      expect(find.byKey(const Key('profile_confirm_logout_button')), findsOneWidget);

      // Confirm logout
      await tester.tap(find.byKey(const Key('profile_confirm_logout_button')));
      await tester.pumpAndSettle();

      // App routes back to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(authController.isAuthenticated, isFalse);
      expect(await tokenStorage.getAccessToken(), isNull);
    });
  });
}
