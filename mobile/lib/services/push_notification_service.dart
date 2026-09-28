import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Reusable service for managing FCM push notifications and backend device registration.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Whether Firebase has been initialized in the current runtime environment.
  bool get isFirebaseAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseMessaging? get _messaging {
    if (!isFirebaseAvailable) return null;
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedAppSubscription;

  final StreamController<Map<String, dynamic>> _queueEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Broadcast stream that emits whenever a queue-related FCM notification
  /// is received in the foreground or opened from background.
  Stream<Map<String, dynamic>> get queueEvents => _queueEventController.stream;

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

  /// Parses and normalizes the queue lifecycle event type from data and notification payloads.
  /// Returns normalized string (e.g. 'CALLED', 'APPROACHING', 'COMPLETED') or null if not a queue event.
  static String? parseQueueEventType(Map<String, dynamic> data, [RemoteNotification? notification]) {
    // 1. Primary classification via data payload
    if (data.isNotEmpty) {
      final rawType = (data['type'] ?? data['event'] ?? data['notification_type'] ?? '')
          .toString()
          .trim()
          .toUpperCase()
          .replaceAll(' ', '_');

      if (rawType.isNotEmpty) {
        final normalized = rawType.startsWith('QUEUE_') ? rawType.substring(6) : rawType;
        const knownEvents = {
          'CALLED',
          'APPROACHING',
          'MISSED_TURN',
          'PAUSED',
          'RESUMED',
          'COMPLETED',
          'JOINED',
        };

        if (knownEvents.contains(normalized)) {
          return normalized;
        }

        if (rawType.startsWith('QUEUE_')) {
          return normalized;
        }
      }

      // Identifier presence check
      if (data.containsKey('queue_id') || data.containsKey('ticket_id')) {
        return 'QUEUE_UPDATE';
      }
    }

    // 2. Fallback classification via notification text (for devices where OEM battery managers strip custom data)
    if (notification != null) {
      final body = (notification.body ?? '').toLowerCase();
      final title = (notification.title ?? '').toLowerCase();

      if (body.contains('navbatingiz keldi') || body.contains('qabulga kiring')) {
        return 'CALLED';
      }
      if (body.contains('yaqinlashmoqda') || body.contains('oldingizda')) {
        return 'APPROACHING';
      }
      if (body.contains('o‘tkazib yuborildi') || body.contains('oxiriga')) {
        return 'MISSED_TURN';
      }
      if (body.contains('vaqtincha to‘xtatildi')) {
        return 'PAUSED';
      }
      if (body.contains('davom etmoqda')) {
        return 'RESUMED';
      }
      if (body.contains('yakunlandi') || body.contains('tashrifingiz')) {
        return 'COMPLETED';
      }
      if (body.contains('muvaffaqiyatli qo‘shildingiz')) {
        return 'JOINED';
      }
      if (title.contains('queue') || title.contains('navbat')) {
        return 'QUEUE_UPDATE';
      }
    }

    return null;
  }

  /// Checks whether the provided FCM payload contains a queue-related lifecycle event.
  static bool isQueueEvent(Map<String, dynamic> data, [RemoteNotification? notification]) =>
      parseQueueEventType(data, notification) != null;

  /// Dispatches and processes an incoming FCM message payload.
  void handleRemoteMessage(RemoteMessage message) {
    debugPrint('FCM foreground message received');
    final data = message.data;
    final eventType = parseQueueEventType(data, message.notification);
    if (eventType != null) {
      debugPrint('Queue event recognized: $eventType');
      final payload = Map<String, dynamic>.from(data);
      payload['type'] ??= 'QUEUE_$eventType';
      notifyQueueEvent(payload);
    }
  }

  /// Emits a queue event payload to all active listeners.
  void notifyQueueEvent(Map<String, dynamic> data) {
    debugPrint('queueEvents emitted');
    if (!_queueEventController.isClosed) {
      _queueEventController.add(data);
    }
  }

  /// Ensures foreground and interaction listeners are actively registered.
  void ensureListeners() {
    setupForegroundMessageListener();
    setupInteractionListeners();
    setupTokenRefreshListener();
  }

  /// Initializes notification permissions, sets up listeners for token refresh,
  /// foreground messages, background resume taps, and checks initial message.
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

    // 1. Immediately register listeners so no messages are dropped during initialization
    ensureListeners();

    // 2. Request notification permissions safely
    try {
      await requestPermissions();
    } catch (e) {
      debugPrint('[PushNotificationService] Notification permission request error: $e');
    }

    // 3. Fetch current FCM token without logging secret token
    try {
      final token = await getDeviceToken();
      if (token != null) {
        debugPrint('[PushNotificationService] Initial FCM token obtained successfully.');
      } else {
        debugPrint('[PushNotificationService] Warning: Initial FCM token is null.');
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Token retrieval error: $e');
    }

    // 4. Check if app was opened from terminated state via notification tap
    await checkInitialMessage();
  }

  /// Requests notification permissions from the operating system.
  Future<NotificationSettings?> requestPermissions() async {
    final messaging = _messaging;
    if (messaging == null) return null;
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[PushNotificationService] Notification permission status: ${settings.authorizationStatus}');
      return settings;
    } catch (e) {
      debugPrint('[PushNotificationService] Notification permission request error: $e');
      return null;
    }
  }

  /// Obtains the current FCM registration token.
  Future<String?> getDeviceToken() async {
    final messaging = _messaging;
    if (messaging == null) return null;
    try {
      return await messaging.getToken();
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
      await response.drain<void>();

      if (response.statusCode == HttpStatus.ok || response.statusCode == HttpStatus.created) {
        debugPrint(
          '[PushNotificationService] Device registered successfully with backend (status ${response.statusCode})',
        );
        return true;
      } else {
        debugPrint(
          '[PushNotificationService] Backend device registration failed (status ${response.statusCode})',
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
  /// When FCM issues a new token, this listener registers the new token with the backend.
  void setupTokenRefreshListener() {
    final messaging = _messaging;
    if (messaging == null) return;
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('[PushNotificationService] FCM token refreshed.');
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
    if (!isFirebaseAvailable) return;
    _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      handleRemoteMessage(message);
    }, onError: (Object error) {
      debugPrint('[PushNotificationService] Error in FCM onMessage stream: $error');
    });
  }

  /// Sets up listeners for user tapping notifications from background.
  void setupInteractionListeners() {
    if (!isFirebaseAvailable) return;
    _messageOpenedAppSubscription?.cancel();
    _messageOpenedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM notification opened from background');
      handleRemoteMessage(message);
    }, onError: (Object error) {
      debugPrint('[PushNotificationService] Error in onMessageOpenedApp stream: $error');
    });
  }

  /// Checks whether the app was launched by tapping a notification from terminated state.
  Future<void> checkInitialMessage() async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM notification opened from terminated state');
        handleRemoteMessage(initialMessage);
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Error checking initial FCM message: $e');
    }
  }

  /// Disposes active subscriptions when no longer needed.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription?.cancel();
    _foregroundSubscription = null;
    _messageOpenedAppSubscription?.cancel();
    _messageOpenedAppSubscription = null;
  }
}
