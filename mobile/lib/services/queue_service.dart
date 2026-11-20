import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/patient_ticket.dart';
import 'auth_service.dart';
import 'locale_controller.dart';
import 'secure_token_storage.dart';

/// Exception thrown during queue operations.
class QueueException implements Exception {
  final String message;
  final int? statusCode;

  const QueueException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Specialized exception for 409 Conflict responses (e.g. duplicate active ticket).
class QueueConflictException extends QueueException {
  final String backendDetail;
  final bool isAlreadyActive;

  const QueueConflictException(
    super.message, {
    super.statusCode = 409,
    required this.backendDetail,
    required this.isAlreadyActive,
  });
}

/// Service handling patient queue interactions: joining a queue,
/// fetching the patient's current ticket, and querying queue status.
class QueueService {
  QueueService({
    http.Client? httpClient,
    SecureTokenStorage? tokenStorage,
    AuthService? authService,
    this.localeController,
  })  : _client = httpClient ?? http.Client(),
        _storage = tokenStorage ?? SecureTokenStorage(),
        _authService = authService ?? AuthService.instance;

  static QueueService _instance = QueueService();
  static QueueService get instance => _instance;

  @visibleForTesting
  static set instance(QueueService s) => _instance = s;

  final http.Client _client;
  final SecureTokenStorage _storage;
  final AuthService _authService;
  final LocaleController? localeController;
  bool _includeSkippedInMyTicket = false;

  /// Configures whether [getMyTicket] requests today's SKIPPED ticket as a fallback.
  void setIncludeSkipped(bool value) {
    _includeSkippedInMyTicket = value;
  }

  String get _currentLanguage =>
      (localeController ?? LocaleController.instance).languageCode;

  /// Retrieves a valid access token, attempting session restore/refresh if needed.
  Future<String> _getValidAccessToken() async {
    var token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }

    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      // Attempt recovery only if a refresh token is present
      final restoredUser = await _authService.restoreSession();
      if (restoredUser != null) {
        token = await _storage.getAccessToken();
        if (token != null && token.isNotEmpty) {
          return token;
        }
      }
    }

    throw const QueueException(
      'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.',
      statusCode: 401,
    );
  }

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

  /// Helper to execute an authenticated GET request, retrying once on 401.
  Future<http.Response> _getWithAuth(Uri uri) async {
    var token = await _getValidAccessToken();
    final lang = _currentLanguage;

    var response = await _client.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'Accept-Language': lang,
      },
    );

    if (response.statusCode == 401) {
      debugPrint('[QueueService] Received 401. Attempting session restore...');
      final restored = await _authService.restoreSession();
      if (restored != null) {
        final newToken = await _storage.getAccessToken();
        if (newToken != null) {
          response = await _client.get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $newToken',
              'Accept-Language': lang,
            },
          );
        }
      }
    }

    return response;
  }

  /// Helper to execute an authenticated POST request, retrying once on 401.
  Future<http.Response> _postWithAuth(Uri uri, [Map<String, dynamic>? body]) async {
    var token = await _getValidAccessToken();
    final lang = _currentLanguage;

    var response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'Accept-Language': lang,
      },
      body: body != null ? jsonEncode(body) : null,
    );

    if (response.statusCode == 401) {
      debugPrint('[QueueService] Received 401. Attempting session restore...');
      final restored = await _authService.restoreSession();
      if (restored != null) {
        final newToken = await _storage.getAccessToken();
        if (newToken != null) {
          response = await _client.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $newToken',
              'Accept-Language': lang,
            },
            body: body != null ? jsonEncode(body) : null,
          );
        }
      }
    }

    return response;
  }

  /// Helper to execute an authenticated PATCH request, retrying once on 401.
  Future<http.Response> _patchWithAuth(Uri uri, [Map<String, dynamic>? body]) async {
    var token = await _getValidAccessToken();
    final lang = _currentLanguage;

    var response = await _client.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'Accept-Language': lang,
      },
      body: body != null ? jsonEncode(body) : null,
    );

    if (response.statusCode == 401) {
      debugPrint('[QueueService] Received 401. Attempting session restore...');
      final restored = await _authService.restoreSession();
      if (restored != null) {
        final newToken = await _storage.getAccessToken();
        if (newToken != null) {
          response = await _client.patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $newToken',
              'Accept-Language': lang,
            },
            body: body != null ? jsonEncode(body) : null,
          );
        }
      }
    }

    return response;
  }

  /// Joins the queue with [queueId] for the currently authenticated patient.
  ///
  /// Calls `POST /api/queues/{queue_id}/join`.
  /// Returns the newly created [QueueTicket].
  ///
  /// Throws [QueueConflictException] if 409 Conflict occurs (e.g. duplicate active ticket).
  /// Throws [QueueException] for other API or network failures.
  Future<QueueTicket> joinQueue(int queueId) async {
    try {
      final uri = ApiConfig.joinQueueUri(queueId);
      final response = await _postWithAuth(uri);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return QueueTicket.fromJson(decoded);
      }

      if (response.statusCode == 409) {
        final detail = _parseErrorMessage(
          response.body,
          'Navbatga qo‘shilishda ziddiyat yuz berdi.',
        );
        final isAlreadyActive =
            detail.toLowerCase().contains('already has an active ticket');
        final isSameSpecialization =
            detail.toLowerCase().contains('specialization');
        final userMessage = isAlreadyActive
            ? (isSameSpecialization
                ? 'Sizda ushbu mutaxassislik bo‘yicha allaqachon faol talon mavjud.'
                : 'Sizda allaqachon ushbu navbatda faol talon mavjud.')
            : detail == 'Queue is inactive'
                ? 'Navbat hozirda faol emas.'
                : detail == 'Queue is paused'
                    ? 'Navbat vaqtincha to‘xtatilgan.'
                    : detail;

        throw QueueConflictException(
          userMessage,
          statusCode: 409,
          backendDetail: detail,
          isAlreadyActive: isAlreadyActive,
        );
      }

      if (response.statusCode == 404) {
        throw const QueueException(
          'Navbat topilmadi.',
          statusCode: 404,
        );
      }

      if (response.statusCode == 401) {
        throw const QueueException(
          'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.',
          statusCode: 401,
        );
      }

      final errorMsg = _parseErrorMessage(
        response.body,
        'Navbatga qo‘shilishda xatolik yuz berdi (${response.statusCode}).',
      );
      throw QueueException(errorMsg, statusCode: response.statusCode);
    } on QueueException {
      rethrow;
    } on SocketException {
      throw const QueueException(
        'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } catch (e) {
      throw QueueException('Kutilmagan xatolik yuz berdi: $e');
    }
  }

  /// Fetches the patient's current active queue ticket.
  ///
  /// Calls `GET /api/queues/my-ticket`.
  /// Returns [MyQueueTicket] if an active ticket exists, or `null` if 404 (no active ticket).
  ///
  /// Throws [QueueException] for network/auth errors.
  Future<MyQueueTicket?> getMyTicket() async {
    try {
      final uri = _includeSkippedInMyTicket
          ? ApiConfig.myTicketIncludeSkippedUri
          : ApiConfig.myTicketUri;
      final response = await _getWithAuth(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return MyQueueTicket.fromJson(decoded);
      }

      if (response.statusCode == 404) {
        // Backend returns 404 when patient has no active ticket in WAITING/CALLED/SERVING.
        return null;
      }

      if (response.statusCode == 401) {
        throw const QueueException(
          'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.',
          statusCode: 401,
        );
      }

      final errorMsg = _parseErrorMessage(
        response.body,
        'Talon maʼlumotlarini yuklashda xatolik yuz berdi (${response.statusCode}).',
      );
      throw QueueException(errorMsg, statusCode: response.statusCode);
    } on QueueException {
      rethrow;
    } on SocketException {
      throw const QueueException(
        'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } catch (e) {
      throw QueueException('Kutilmagan xatolik yuz berdi: $e');
    }
  }

  /// Fetches all of the patient's active queue tickets.
  ///
  /// Calls `GET /api/queues/my-tickets`.
  /// Returns an empty list if none exist.
  Future<List<MyQueueTicket>> getMyTickets() async {
    try {
      final uri = _includeSkippedInMyTicket
          ? ApiConfig.myTicketsIncludeSkippedUri
          : ApiConfig.myTicketsUri;
      final response = await _getWithAuth(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded
            .map((item) => MyQueueTicket.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      if (response.statusCode == 401) {
        throw const QueueException(
          'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.',
          statusCode: 401,
        );
      }

      final errorMsg = _parseErrorMessage(
        response.body,
        'Talon maʼlumotlarini yuklashda xatolik yuz berdi (${response.statusCode}).',
      );
      throw QueueException(errorMsg, statusCode: response.statusCode);
    } on QueueException {
      rethrow;
    } on SocketException {
      throw const QueueException(
        'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } catch (e) {
      throw QueueException('Kutilmagan xatolik yuz berdi: $e');
    }
  }

  /// Fetches the status summary of a queue (`GET /api/queues/{queue_id}/status`).
  Future<QueueStatus> fetchQueueStatus(int queueId) async {
    try {
      final uri = ApiConfig.queueStatusUri(queueId);
      final response = await _getWithAuth(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return QueueStatus.fromJson(decoded);
      }

      if (response.statusCode == 404) {
        throw const QueueException('Navbat topilmadi.', statusCode: 404);
      }

      final errorMsg = _parseErrorMessage(
        response.body,
        'Navbat holatini yuklashda xatolik yuz berdi (${response.statusCode}).',
      );
      throw QueueException(errorMsg, statusCode: response.statusCode);
    } on QueueException {
      rethrow;
    } on SocketException {
      throw const QueueException(
        'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } catch (e) {
      throw QueueException('Kutilmagan xatolik yuz berdi: $e');
    }
  }

  /// Performs patient QR check-in by posting the scanned clinic QR token
  /// and optional [ticketId] targeting a specific waiting ticket.
  ///
  /// Calls `POST /api/queues/check-in/qr`.
  /// Never logs raw QR tokens.
  Future<QueueTicket> checkInWithQr(String qrToken, {int? ticketId}) async {
    try {
      final uri = ApiConfig.checkInQrUri;
      // Never log raw QR token
      debugPrint('[QueueService] Submitting QR check-in token...');
      final response = await _postWithAuth(uri, {
        'token': qrToken.trim(),
        'ticket_id': ?ticketId,
      });

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return QueueTicket.fromJson(decoded);
      }

      if (response.statusCode == 400) {
        final detail = _parseErrorMessage(
          response.body,
          'Yaroqsiz yoki muddati o‘tgan QR-kod.',
        );
        throw QueueException(detail, statusCode: 400);
      }

      if (response.statusCode == 404) {
        final detail = _parseErrorMessage(
          response.body,
          'Ushbu klinika uchun faol navbat taloni topilmadi.',
        );
        throw QueueException(detail, statusCode: 404);
      }

      if (response.statusCode == 409) {
        final detail = _parseErrorMessage(
          response.body,
          'Talon allaqachon ro‘yxatdan o‘tkazilgan.',
        );
        throw QueueConflictException(
          detail,
          statusCode: 409,
          backendDetail: detail,
          isAlreadyActive: false,
        );
      }

      if (response.statusCode == 401) {
        throw const QueueException(
          'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.',
          statusCode: 401,
        );
      }

      final errorMsg = _parseErrorMessage(
        response.body,
        'QR orqali ro‘yxatdan o‘tishda xatolik yuz berdi (${response.statusCode}).',
      );
      throw QueueException(errorMsg, statusCode: response.statusCode);
    } on QueueException {
      rethrow;
    } on SocketException {
      throw const QueueException(
        'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } catch (e) {
      throw QueueException('Kutilmagan xatolik yuz berdi: $e');
    }
  }

  /// Cancels the patient's own active ticket.
  ///
  /// Calls `PATCH /api/queues/my-ticket/cancel` (or `PATCH /api/queues/{queue_id}/tickets/{ticket_id}/cancel`).
  Future<QueueTicket> cancelTicket({int? queueId, int? ticketId}) async {
    try {
      final uri = (queueId != null && ticketId != null)
          ? ApiConfig.cancelTicketUri(queueId, ticketId)
          : ApiConfig.cancelMyTicketUri;
      final response = await _patchWithAuth(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return QueueTicket.fromJson(decoded);
      }

      if (response.statusCode == 404) {
        throw const QueueException(
          'Bekor qilish uchun faol talon topilmadi.',
          statusCode: 404,
        );
      }

      if (response.statusCode == 403) {
        throw const QueueException(
          'Boshqa bemorning talonini bekor qilish taqiqlanadi.',
          statusCode: 403,
        );
      }

      if (response.statusCode == 409) {
        final detail = _parseErrorMessage(
          response.body,
          'Faqat kutilayotgan, chaqirilgan yoki o‘tkazib yuborilgan talonlar bekor qilinishi mumkin.',
        );
        throw QueueException(detail, statusCode: 409);
      }

      if (response.statusCode == 401) {
        throw const QueueException(
          'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.',
          statusCode: 401,
        );
      }

      final errorMsg = _parseErrorMessage(
        response.body,
        'Talonni bekor qilishda xatolik yuz berdi (${response.statusCode}).',
      );
      throw QueueException(errorMsg, statusCode: response.statusCode);
    } on QueueException {
      rethrow;
    } on SocketException {
      throw const QueueException(
        'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } catch (e) {
      throw QueueException('Kutilmagan xatolik yuz berdi: $e');
    }
  }
}
