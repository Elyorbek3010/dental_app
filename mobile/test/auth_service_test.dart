import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/services/auth_service.dart';
import 'package:app/services/push_notification_service.dart';
import 'package:app/services/secure_token_storage.dart';

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

  bool registerShouldFail = false;
  String? registeredAccessToken;
  int registerCallCount = 0;

  @override
  Future<bool> registerDevice(
    String accessToken, {
    String? fcmToken,
    String? customBaseUrl,
  }) async {
    registerCallCount++;
    registeredAccessToken = accessToken;
    if (registerShouldFail) {
      return false;
    }
    return true;
  }

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService Unit Tests', () {
    late InMemoryTokenStorage tokenStorage;
    late FakePushNotificationService fakePushService;

    setUp(() {
      tokenStorage = InMemoryTokenStorage();
      fakePushService = FakePushNotificationService();
    });

    test('Successful login sets tokens, returns PatientUser, and invokes FCM registration',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'test_access_jwt',
              'refresh_token': 'test_refresh_jwt',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/me') {
          expect(request.headers['Authorization'], 'Bearer test_access_jwt');
          return http.Response(
            jsonEncode({
              'id': 101,
              'clinic_id': 1,
              'full_name': 'Ali Valiyev',
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
        pushService: fakePushService,
      );

      final user = await authService.login(
        phone: '+998901234567',
        password: 'password123',
      );

      expect(user.id, 101);
      expect(user.fullName, 'Ali Valiyev');
      expect(user.phone, '+998901234567');
      expect(user.role, 'PATIENT');
      expect(await tokenStorage.getAccessToken(), 'test_access_jwt');
      expect(await tokenStorage.getRefreshToken(), 'test_refresh_jwt');
      expect(authService.currentUser, equals(user));
    });

    test('Login with non-PATIENT role rejects user with AuthException', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'reception_token',
              'refresh_token': 'reception_refresh',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 202,
              'clinic_id': 1,
              'full_name': 'Reception Staff',
              'phone': '+998911112233',
              'role': 'RECEPTIONIST',
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
        pushService: fakePushService,
      );

      expect(
        () => authService.login(phone: '+998911112233', password: 'secretpassword'),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('faqat bemorlar uchun'),
        )),
      );
      expect(await tokenStorage.getAccessToken(), isNull);
    });

    test('Login with invalid credentials (401) throws AuthException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Invalid credentials'}),
          401,
        );
      });

      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: fakePushService,
      );

      expect(
        () => authService.login(phone: '+998900000000', password: 'wrongpassword'),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('noto‘g‘ri'),
        )),
      );
      expect(await tokenStorage.getAccessToken(), isNull);
    });

    test('FCM registration failure does not fail login', () async {
      fakePushService.registerShouldFail = true;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'fcm_test_token',
              'refresh_token': 'fcm_refresh_token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 303,
              'full_name': 'Vali Aliyev',
              'phone': '+998939876543',
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
        pushService: fakePushService,
      );

      // Should succeed despite FCM registration failure
      final user = await authService.login(
        phone: '+998939876543',
        password: 'password123',
      );
      expect(user.id, 303);
      expect(authService.currentUser, isNotNull);
    });

    test('Register succeeds, calls backend register, and automatically logs in', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/register') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['full_name'], 'Nodira Karimova');
          expect(body['phone'], '+998941234567');
          expect(body['password'], 'secretpass123');
          return http.Response(
            jsonEncode({
              'id': 404,
              'clinic_id': null,
              'full_name': 'Nodira Karimova',
              'phone': '+998941234567',
              'role': 'PATIENT',
              'is_active': true,
            }),
            201,
          );
        }
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'nodira_jwt',
              'refresh_token': 'nodira_refresh',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 404,
              'full_name': 'Nodira Karimova',
              'phone': '+998941234567',
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
        pushService: fakePushService,
      );

      final user = await authService.register(
        fullName: 'Nodira Karimova',
        phone: '+998941234567',
        password: 'secretpass123',
      );

      expect(user.id, 404);
      expect(user.fullName, 'Nodira Karimova');
      expect(await tokenStorage.getAccessToken(), 'nodira_jwt');
    });

    test('Register with duplicate phone (409) throws AuthException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Phone number already registered'}),
          409,
        );
      });

      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: fakePushService,
      );

      expect(
        () => authService.register(
          fullName: 'Test Patient',
          phone: '+998901234567',
          password: 'password123',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('allaqachon ro‘yxatdan o‘tgan'),
        )),
      );
    });

    test('restoreSession restores patient session when valid access token exists', () async {
      await tokenStorage.saveTokens(
        accessToken: 'saved_valid_jwt',
        refreshToken: 'saved_refresh_jwt',
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 505,
              'full_name': 'Sanjar Umarov',
              'phone': '+998971234567',
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
        pushService: fakePushService,
      );

      final restored = await authService.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.id, 505);
      expect(restored.fullName, 'Sanjar Umarov');
      expect(authService.currentUser, equals(restored));
    });

    test('restoreSession refreshes token when access token is expired', () async {
      await tokenStorage.saveTokens(
        accessToken: 'expired_jwt',
        refreshToken: 'valid_refresh_jwt',
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/auth/me') {
          if (request.headers['Authorization'] == 'Bearer expired_jwt') {
            return http.Response(jsonEncode({'detail': 'Could not validate credentials'}), 401);
          }
          if (request.headers['Authorization'] == 'Bearer refreshed_access_jwt') {
            return http.Response(
              jsonEncode({
                'id': 606,
                'full_name': 'Zuhra Karimova',
                'phone': '+998991234567',
                'role': 'PATIENT',
                'is_active': true,
              }),
              200,
            );
          }
        }
        if (request.url.path == '/api/auth/refresh') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['refresh_token'] == 'valid_refresh_jwt') {
            return http.Response(
              jsonEncode({
                'access_token': 'refreshed_access_jwt',
                'token_type': 'bearer',
              }),
              200,
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final authService = AuthService(
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        pushService: fakePushService,
      );

      final restored = await authService.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.fullName, 'Zuhra Karimova');
      expect(await tokenStorage.getAccessToken(), 'refreshed_access_jwt');
    });

    test('logout clears stored tokens and current user', () async {
      await tokenStorage.saveTokens(
        accessToken: 'some_token',
        refreshToken: 'some_refresh',
      );

      final authService = AuthService(
        tokenStorage: tokenStorage,
        pushService: fakePushService,
      );

      await authService.logout();
      expect(await tokenStorage.getAccessToken(), isNull);
      expect(await tokenStorage.getRefreshToken(), isNull);
      expect(authService.currentUser, isNull);
    });
  });
}
