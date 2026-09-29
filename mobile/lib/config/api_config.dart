import 'package:flutter/foundation.dart';

import '../services/push_notification_service.dart';

/// Centralized API configuration for the Dental Queue mobile application.
///
/// In Android emulator: 10.0.2.2 maps to the development host localhost:8000.
/// On physical devices: set via [setBaseUrl] or `--dart-define=API_BASE_URL=http://<YOUR_IP>:8000`.
class ApiConfig {
  ApiConfig._();

  static const String _defaultUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static String _baseUrl = _defaultUrl;

  /// Returns the currently active base API URL.
  static String get baseUrl => _baseUrl;

  /// Updates the base API URL dynamically (e.g., during app startup or testing).
  /// Automatically keeps [PushNotificationService] in sync.
  static void setBaseUrl(String newUrl) {
    var trimmed = newUrl.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    _baseUrl = trimmed;
    PushNotificationService.instance.baseUrl = _baseUrl;
    debugPrint('[ApiConfig] Base URL updated to: $_baseUrl');
  }

  static const int defaultClinicId = 1;

  // Endpoints
  static Uri get loginUri => Uri.parse('$_baseUrl/api/auth/login');
  static Uri get registerUri => Uri.parse('$_baseUrl/api/auth/register');
  static Uri get refreshUri => Uri.parse('$_baseUrl/api/auth/refresh');
  static Uri get meUri => Uri.parse('$_baseUrl/api/auth/me');
  static Uri get notificationDevicesUri =>
      Uri.parse('$_baseUrl/api/notifications/devices');

  static Uri specializationsUri({int clinicId = defaultClinicId}) =>
      Uri.parse('$_baseUrl/api/catalog/specializations?clinic_id=$clinicId');

  static Uri doctorsUri({
    required int specializationId,
    int clinicId = defaultClinicId,
  }) =>
      Uri.parse(
        '$_baseUrl/api/catalog/doctors?clinic_id=$clinicId&specialization_id=$specializationId',
      );

  static Uri doctorQueueUri(int doctorId) =>
      Uri.parse('$_baseUrl/api/catalog/doctors/$doctorId/queue');

  static Uri joinQueueUri(int queueId) =>
      Uri.parse('$_baseUrl/api/queues/$queueId/join');

  static Uri get myTicketUri =>
      Uri.parse('$_baseUrl/api/queues/my-ticket');

  static Uri get cancelMyTicketUri =>
      Uri.parse('$_baseUrl/api/queues/my-ticket/cancel');

  static Uri cancelTicketUri(int queueId, int ticketId) =>
      Uri.parse('$_baseUrl/api/queues/$queueId/tickets/$ticketId/cancel');

  static Uri get checkInQrUri =>
      Uri.parse('$_baseUrl/api/queues/check-in/qr');

  static Uri queueStatusUri(int queueId) =>
      Uri.parse('$_baseUrl/api/queues/$queueId/status');

  static Uri clinicDisplayWsUri(int clinicId) {
    final baseUri = Uri.parse(_baseUrl);
    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final normalizedPath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    return baseUri.replace(
      scheme: wsScheme,
      path: '$normalizedPath/api/public/ws/clinics/$clinicId/display',
    );
  }
}
