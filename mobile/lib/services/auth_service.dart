import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_tokens.dart';
import '../models/user.dart';
import 'push_notification_service.dart';
import 'secure_token_storage.dart';

/// Custom exception thrown during authentication errors with user-friendly messages.
class AuthException implements Exception {
  final String message;
  final int? statusCode;

  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Service handling patient authentication, registration, session restoration,
/// token refresh, and background FCM device synchronization.
class AuthService {
  AuthService({
    http.Client? httpClient,
    SecureTokenStorage? tokenStorage,
    PushNotificationService? pushService,
  })  : _client = httpClient ?? http.Client(),
        _storage = tokenStorage ?? SecureTokenStorage(),
        _pushService = pushService ?? PushNotificationService.instance;

  static final AuthService instance = AuthService();

  final http.Client _client;
  final SecureTokenStorage _storage;
  final PushNotificationService _pushService;

  PatientUser? _currentUser;

  /// The currently authenticated patient user, or null if unauthenticated.
  PatientUser? get currentUser => _currentUser;

  /// Helper to safely parse backend error responses.
  String _parseErrorMessage(String responseBody, String defaultMsg) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic> && decoded.containsKey('detail')) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first.containsKey('msg')) {
            return first['msg'].toString();
          }
        }
      }
    } catch (_) {}
    return defaultMsg;
  }

  /// Logs in using patient phone number and password.
  ///
  /// Matches existing FastAPI endpoint:
  /// POST `/api/auth/login`
  /// Body: `{"phone": "...", "password": "..."}`
  Future<PatientUser> login({
    required String phone,
    required String password,
  }) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty || password.isEmpty) {
      throw const AuthException('Telefon raqam va parolni kiriting.');
    }

    try {
      final response = await _client.post(
        ApiConfig.loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': cleanPhone,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final tokens = AuthTokens.fromJson(json);

        // Fetch user profile
        final user = await getCurrentUser(tokens.accessToken);

        // Enforce: only PATIENT accounts allowed in patient mobile app
        if (!user.isPatient) {
          throw const AuthException(
            'Ushbu ilova faqat bemorlar uchun mo‘ljallangan.',
          );
        }

        // Store tokens securely
        await _storage.saveTokens(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        );

        _currentUser = user;

        // Register FCM device in background (failure must never prevent login)
        _syncFcmDevice(tokens.accessToken);

        return user;
      } else if (response.statusCode == 401) {
        throw const AuthException(
          'Telefon raqam yoki parol noto‘g‘ri.',
          statusCode: 401,
        );
      } else if (response.statusCode == 403) {
        throw const AuthException(
          'Foydalanuvchi hisobi faol emas.',
          statusCode: 403,
        );
      } else {
        final msg = _parseErrorMessage(
          response.body,
          'Tizimga kirishda xatolik yuz berdi (${response.statusCode}).',
        );
        throw AuthException(msg, statusCode: response.statusCode);
      }
    } on SocketException {
      throw const AuthException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } on http.ClientException {
      throw const AuthException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    }
  }

  /// Registers a new patient.
  ///
  /// Matches existing FastAPI endpoint:
  /// POST `/api/auth/register`
  /// Body: `{"full_name": "...", "phone": "...", "password": "..."}`
  ///
  /// After successful registration, automatically logs in and returns [PatientUser].
  Future<PatientUser> register({
    required String fullName,
    required String phone,
    required String password,
  }) async {
    final cleanName = fullName.trim();
    final cleanPhone = phone.trim();

    if (cleanName.isEmpty) {
      throw const AuthException('Ism va familiyangizni kiriting.');
    }
    if (cleanPhone.isEmpty) {
      throw const AuthException('Telefon raqamingizni kiriting.');
    }
    if (password.length < 8) {
      throw const AuthException('Parol kamida 8 ta belgidan iborat bo‘lishi kerak.');
    }

    try {
      final response = await _client.post(
        ApiConfig.registerUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'full_name': cleanName,
          'phone': cleanPhone,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        // Backend registered successfully. Automatically log in to establish session.
        return await login(phone: cleanPhone, password: password);
      } else if (response.statusCode == 409) {
        throw const AuthException(
          'Ushbu telefon raqam allaqachon ro‘yxatdan o‘tgan.',
          statusCode: 409,
        );
      } else if (response.statusCode == 422) {
        final msg = _parseErrorMessage(
          response.body,
          'Parol kamida 8 ta belgidan iborat bo‘lishi kerak.',
        );
        throw AuthException(msg, statusCode: 422);
      } else {
        final msg = _parseErrorMessage(
          response.body,
          'Ro‘yxatdan o‘tishda xatolik yuz berdi (${response.statusCode}).',
        );
        throw AuthException(msg, statusCode: response.statusCode);
      }
    } on SocketException {
      throw const AuthException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } on http.ClientException {
      throw const AuthException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    }
  }

  /// Fetches the profile of the current user from `/api/auth/me`.
  Future<PatientUser> getCurrentUser(String accessToken) async {
    final response = await _client.get(
      ApiConfig.meUri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return PatientUser.fromJson(json);
    } else {
      throw AuthException(
        'Foydalanuvchi maʼlumotlarini yuklab bo‘lmadi.',
        statusCode: response.statusCode,
      );
    }
  }

  /// Attempts to restore a previously saved authentication session.
  ///
  /// Checks secure storage for stored tokens:
  /// 1. Tries `getCurrentUser` with existing access token.
  /// 2. If access token is expired, attempts refresh using refresh token.
  /// 3. If valid, verifies `PATIENT` role and restores session.
  /// 4. If invalid or missing, clears tokens and returns null.
  Future<PatientUser?> restoreSession() async {
    try {
      final accessToken = await _storage.getAccessToken();
      final refreshToken = await _storage.getRefreshToken();

      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }

      try {
        final user = await getCurrentUser(accessToken);
        if (user.isPatient) {
          _currentUser = user;
          _syncFcmDevice(accessToken);
          return user;
        } else {
          await logout();
          return null;
        }
      } catch (e) {
        // Access token might be expired. Try refresh token if available.
        if (refreshToken != null && refreshToken.isNotEmpty) {
          final newAccessToken = await _refreshAccessToken(refreshToken);
          if (newAccessToken != null) {
            final user = await getCurrentUser(newAccessToken);
            if (user.isPatient) {
              _currentUser = user;
              _syncFcmDevice(newAccessToken);
              return user;
            }
          }
        }
      }

      // If token verification and refresh both fail, clean up
      await logout();
      return null;
    } catch (e) {
      debugPrint('[AuthService] Error restoring session: $e');
      return null;
    }
  }

  /// Calls `/api/auth/refresh` to obtain a fresh access token.
  Future<String?> _refreshAccessToken(String refreshToken) async {
    try {
      final response = await _client.post(
        ApiConfig.refreshUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = json['access_token'] as String;
        await _storage.saveAccessToken(newAccessToken);
        return newAccessToken;
      }
    } catch (e) {
      debugPrint('[AuthService] Token refresh error: $e');
    }
    return null;
  }

  /// Synchronizes the active access token and device FCM token with the backend.
  /// Catching all errors ensures notification failure never blocks authentication.
  void _syncFcmDevice(String accessToken) {
    _pushService.setAccessToken(accessToken);
    _pushService.registerDevice(accessToken).then((success) {
      if (success) {
        debugPrint('[AuthService] FCM device successfully registered for patient.');
      } else {
        debugPrint('[AuthService] FCM registration returned false (non-fatal).');
      }
    }).catchError((Object error) {
      debugPrint('[AuthService] FCM registration error (non-fatal): $error');
    });
  }

  /// Logs the patient out locally, clears stored credentials and FCM access token.
  Future<void> logout() async {
    _currentUser = null;
    _pushService.clearAccessToken();
    await _storage.clearTokens();
    debugPrint('[AuthService] Patient logged out locally.');
  }
}
