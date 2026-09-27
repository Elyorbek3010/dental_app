import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Reusable service for managing patient personal local notifications and reminders.
///
/// Responsibilities:
/// - Initializing local notifications and timezone database.
/// - Creating the dedicated Android notification channel for personal reminders.
/// - Requesting Android notification and exact alarm permissions.
/// - Scheduling local notifications for specific future dates/times (exact, alarm-while-idle).
/// - Cancelling scheduled notifications by ID or all at once.
///
/// Note: This service is strictly local to the patient's phone and independent of
/// server-side FCM push notifications ([PushNotificationService]).
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Whether the service has been initialized.
  bool get isInitialized => _isInitialized;

  /// Dedicated Android notification channel for patient reminders.
  static const AndroidNotificationChannel reminderChannel =
      AndroidNotificationChannel(
    'patient_reminders_channel',
    'Bemor eslatmalari',
    description: 'Bemorning shaxsiy qabul va tashrif eslatmalari',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// Initializes timezone data, notification settings, and notification channels.
  ///
  /// Safe execution: catches errors, never throws uncaught exceptions.
  Future<bool> initialize({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async {
    if (_isInitialized) {
      return true;
    }

    try {
      // 1. Initialize timezone database and detect device location
      await _configureTimezone();

      // 2. Platform initialization settings
      const initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const initializationSettingsDarwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
      );

      // 3. Initialize plugin
      final initialized = await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: onNotificationResponse,
      );

      if (initialized != true) {
        debugPrint(
          '[LocalNotificationService] Warning: Plugin initialize returned false/null.',
        );
      }

      // 4. Create Android notification channel
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(reminderChannel);
        debugPrint(
          '[LocalNotificationService] Android notification channel "${reminderChannel.id}" created.',
        );
      }

      _isInitialized = true;
      debugPrint('[LocalNotificationService] Initialized successfully.');
      return true;
    } catch (e, stack) {
      debugPrint('[LocalNotificationService] Initialization error: $e\n$stack');
      return false;
    }
  }

  /// Configures timezone data and sets local location.
  Future<void> _configureTimezone() async {
    tz.initializeTimeZones();
    try {
      final TimezoneInfo tzInfo = await FlutterTimezone.getLocalTimezone()
          .timeout(const Duration(seconds: 2));
      final String timeZoneName = tzInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint('[LocalNotificationService] Local timezone configured: $timeZoneName');
    } catch (e) {
      debugPrint(
        '[LocalNotificationService] Could not resolve device timezone ($e). Falling back to Asia/Tashkent or UTC.',
      );
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Tashkent'));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
    }
  }

  /// Requests notification and alarm scheduling permissions from the operating system.
  Future<bool> requestPermissions() async {
    bool granted = false;

    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Request POST_NOTIFICATIONS permission (Android 13+)
        final notifGranted =
            await androidPlugin.requestNotificationsPermission() ?? false;

        // Request SCHEDULE_EXACT_ALARM permission (Android 14+)
        final exactGranted =
            await androidPlugin.requestExactAlarmsPermission() ?? false;

        debugPrint(
          '[LocalNotificationService] Android permission - Notifications: $notifGranted, ExactAlarms: $exactGranted',
        );
        granted = notifGranted;
      }

      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();

      if (iosPlugin != null) {
        final iosGranted = await iosPlugin.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
        debugPrint(
          '[LocalNotificationService] iOS notification permission: $iosGranted',
        );
        granted = iosGranted;
      }
    } catch (e) {
      debugPrint('[LocalNotificationService] Error requesting permissions: $e');
    }

    return granted;
  }

  /// Schedules a local notification for a specific date and time.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for the notification.
  /// - [title]: Notification title displayed to the patient.
  /// - [body]: Notification body text (e.g., "Dental check-up").
  /// - [scheduledDate]: Future [DateTime] when the notification must trigger.
  /// - [payload]: Optional payload string passed to the click handler.
  ///
  /// Returns `true` if scheduled successfully, `false` otherwise.
  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (scheduledDate.isBefore(DateTime.now())) {
      debugPrint(
        '[LocalNotificationService] Error: Scheduled date ($scheduledDate) must be in the future.',
      );
      return false;
    }

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        debugPrint(
          '[LocalNotificationService] Error: Failed to initialize before scheduling.',
        );
        return false;
      }
    }

    try {
      final tz.TZDateTime scheduledTz =
          tz.TZDateTime.from(scheduledDate, tz.local);

      final androidDetails = AndroidNotificationDetails(
        reminderChannel.id,
        reminderChannel.name,
        channelDescription: reminderChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledTz,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      debugPrint(
        '[LocalNotificationService] Scheduled notification #$id for $scheduledTz',
      );
      return true;
    } catch (e, stack) {
      debugPrint(
        '[LocalNotificationService] Error scheduling notification #$id: $e\n$stack',
      );
      return false;
    }
  }

  /// Cancels an existing scheduled notification by its [id].
  Future<bool> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id: id);
      debugPrint('[LocalNotificationService] Cancelled notification #$id');
      return true;
    } catch (e) {
      debugPrint('[LocalNotificationService] Error cancelling notification #$id: $e');
      return false;
    }
  }

  /// Cancels all scheduled and active notifications created by this app.
  Future<bool> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint('[LocalNotificationService] All notifications cancelled.');
      return true;
    } catch (e) {
      debugPrint('[LocalNotificationService] Error cancelling all notifications: $e');
      return false;
    }
  }

  /// Retrieves the list of currently pending scheduled notification requests.
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('[LocalNotificationService] Error getting pending notifications: $e');
      return [];
    }
  }
}
