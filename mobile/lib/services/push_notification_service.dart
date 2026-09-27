import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Reusable service for managing FCM push notifications and backend device registration.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Base URL of the backend API.
  /// Defaults to Android emulator host (http://10.0.2.2:8000).
  /// For physical devices or custom network setups, this can be updated.
  String baseUrl = 'http://10.0.2.2:8000';

  /// Currently active patient JWT/access token.
  /// Stored in-memory so that refreshed FCM tokens can be automatically registered.
  String? _currentAccessToken;

  /// Optional dynamic provider for retrieving the latest access token.
  String? Function()? accessTokenProvider;

  /// The active access token, if any.
  String? get currentAccessToken => _currentAccessToken ?? accessTokenProvider?.call();

  /// Updates or sets the stored access token.
  void setAccessToken(String? token) {
    _currentAccessToken = token;
  }

  /// Clears the stored access token (e.g., on patient logout).
  void clearAccessToken() {
    _currentAccessToken = null;
  }

  /// Initializes notification permissions, logs initial FCM token,
  /// and attaches listeners for token refresh and foreground messages.
  Future<void> initialize({
    String? customBaseUrl,
    String? Function()? tokenProvider,
  }) async {
    if (customBaseUrl != null) {
      baseUrl = customBaseUrl;
    }
    if (tokenProvider != null) {
      accessTokenProvider = tokenProvider;
    }

    // 1. Request notification permissions
    await requestPermissions();

    // 2. Log current FCM token for development inspection
    final token = await getDeviceToken();
    if (token != null) {
      debugPrint('FCM TOKEN: $token');
    } else {
      debugPrint('[PushNotificationService] Warning: Initial FCM token is null.');
    }

    // 3. Set up listeners
    setupTokenRefreshListener();
    setupForegroundMessageListener();
  }

  /// Requests notification permissions from the operating system.
  Future<NotificationSettings> requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[PushNotificationService] Notification permission status: ${settings.authorizationStatus}');
    return settings;
  }

  /// Obtains the current FCM registration token.
  Future<String?> getDeviceToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('[PushNotificationService] Error retrieving FCM token: $e');
      return null;
    }
  }

  /// Registers the FCM device token with the backend.
  ///
  /// Sends POST to `/api/notifications/devices` with:
  /// Header: `Authorization: Bearer <accessToken>`
  /// Body: `{"fcm_token": "<token>"}`
  ///
  /// Safe execution: catches network/server errors, never throws uncaught exceptions.
  Future<bool> registerDevice(
    String accessToken, {
    String? fcmToken,
    String? customBaseUrl,
  }) async {
    if (accessToken.trim().isEmpty) {
      debugPrint('[PushNotificationService] registerDevice failed: accessToken is empty');
      return false;
    }

    _currentAccessToken = accessToken;

    final token = fcmToken ?? await getDeviceToken();
    if (token == null || token.trim().isEmpty) {
      debugPrint('[PushNotificationService] registerDevice failed: FCM token unavailable');
      return false;
    }

    final targetUrl = customBaseUrl ?? baseUrl;
    final uri = Uri.parse('$targetUrl/api/notifications/devices');

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      request.add(utf8.encode(jsonEncode({'fcm_token': token})));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.ok || response.statusCode == HttpStatus.created) {
        debugPrint('[PushNotificationService] Device registered successfully with backend: $responseBody');
        return true;
      } else {
        debugPrint(
          '[PushNotificationService] Backend device registration failed (status ${response.statusCode}): $responseBody',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Network error during device registration: $e');
      return false;
    } finally {
      client?.close();
    }
  }

  /// Sets up the FCM token refresh listener.
  ///
  /// When FCM issues a new token, this listener logs it and, if a patient access token
  /// is currently available, automatically re-registers the new token with the backend.
  void setupTokenRefreshListener() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('[PushNotificationService] FCM token refreshed: $newToken');
      final activeToken = currentAccessToken;
      if (activeToken != null && activeToken.trim().isNotEmpty) {
        debugPrint('[PushNotificationService] Auto-registering refreshed FCM token with backend...');
        await registerDevice(activeToken, fcmToken: newToken);
      } else {
        debugPrint('[PushNotificationService] Refreshed FCM token noted. Awaiting patient authentication.');
      }
    }, onError: (Object error) {
      debugPrint('[PushNotificationService] Error in FCM onTokenRefresh stream: $error');
    });
  }

  /// Sets up foreground notification message listening.
  void setupForegroundMessageListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground FCM message received:');
      debugPrint('Title: ${message.notification?.title}');
      debugPrint('Body: ${message.notification?.body}');
      if (message.data.isNotEmpty) {
        debugPrint('Data: ${message.data}');
      }
    });
  }

  /// Disposes active subscriptions when no longer needed.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}
