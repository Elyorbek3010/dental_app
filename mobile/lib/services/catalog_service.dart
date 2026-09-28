import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/doctor.dart';
import '../models/doctor_queue.dart';
import '../models/specialization.dart';
import 'auth_service.dart';
import 'locale_controller.dart';
import 'secure_token_storage.dart';

/// Exception thrown when catalog queries fail.
class CatalogException implements Exception {
  final String message;
  final int? statusCode;

  const CatalogException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Service handling clinic catalog queries: specializations, doctors, and active doctor queues.
class CatalogService {
  CatalogService({
    http.Client? httpClient,
    SecureTokenStorage? tokenStorage,
    AuthService? authService,
    this.localeController,
  })  : _client = httpClient ?? http.Client(),
        _storage = tokenStorage ?? SecureTokenStorage(),
        _authService = authService ?? AuthService.instance;

  static final CatalogService instance = CatalogService();

  final http.Client _client;
  final SecureTokenStorage _storage;
  final AuthService _authService;
  final LocaleController? localeController;

  String get _currentLanguage =>
      (localeController ?? LocaleController.instance).languageCode;

  /// Retrieves a valid access token, attempting session restore/refresh if needed.
  Future<String> _getValidAccessToken() async {
    var token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }

    // Attempt recovery
    final restoredUser = await _authService.restoreSession();
    if (restoredUser != null) {
      token = await _storage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        return token;
      }
    }

    throw const CatalogException(
      'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.',
      statusCode: 401,
    );
  }

  /// Helper to execute an authenticated GET request, retrying once if a 401 occurs.
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
      debugPrint('[CatalogService] Received 401. Attempting session restore...');
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

  /// Fetches available dental specializations for the given clinic.
  Future<List<Specialization>> fetchSpecializations({
    int clinicId = ApiConfig.defaultClinicId,
  }) async {
    try {
      final uri = ApiConfig.specializationsUri(clinicId: clinicId);
      final response = await _getWithAuth(uri);

      if (response.statusCode == 200) {
        final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded
            .map((item) => Specialization.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 401) {
        throw const CatalogException(
          'Autentifikatsiya muddati tugagan.',
          statusCode: 401,
        );
      } else if (response.statusCode == 404) {
        throw const CatalogException(
          'Klinika topilmadi.',
          statusCode: 404,
        );
      } else {
        throw CatalogException(
          'Mutaxassisliklarni yuklashda xatolik yuz berdi (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on SocketException {
      throw const CatalogException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } on http.ClientException {
      throw const CatalogException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    }
  }

  /// Fetches doctors belonging to a specific specialization.
  Future<List<Doctor>> fetchDoctors({
    required int specializationId,
    int clinicId = ApiConfig.defaultClinicId,
  }) async {
    try {
      final uri = ApiConfig.doctorsUri(
        specializationId: specializationId,
        clinicId: clinicId,
      );
      final response = await _getWithAuth(uri);

      if (response.statusCode == 200) {
        final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded
            .map((item) => Doctor.fromJson(item as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 401) {
        throw const CatalogException(
          'Autentifikatsiya muddati tugagan.',
          statusCode: 401,
        );
      } else if (response.statusCode == 404) {
        throw const CatalogException(
          'Mutaxassislik yoki klinika topilmadi.',
          statusCode: 404,
        );
      } else {
        throw CatalogException(
          'Shifokorlar ro‘yxatini yuklashda xatolik yuz berdi (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on SocketException {
      throw const CatalogException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } on http.ClientException {
      throw const CatalogException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    }
  }

  /// Fetches today's active queue for a specific doctor.
  ///
  /// Returns [DoctorQueue] if an active queue is running today.
  /// Returns `null` if no active queue exists for this doctor today (404).
  Future<DoctorQueue?> fetchDoctorQueue(int doctorId) async {
    try {
      final uri = ApiConfig.doctorQueueUri(doctorId);
      final response = await _getWithAuth(uri);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return DoctorQueue.fromJson(json);
      } else if (response.statusCode == 404) {
        // No queue exists for this doctor today
        return null;
      } else if (response.statusCode == 409) {
        throw const CatalogException(
          'Shifokor hozirda nofaol holatda.',
          statusCode: 409,
        );
      } else if (response.statusCode == 401) {
        throw const CatalogException(
          'Autentifikatsiya muddati tugagan.',
          statusCode: 401,
        );
      } else {
        throw CatalogException(
          'Navbat maʼlumotlarini yuklashda xatolik (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on SocketException {
      throw const CatalogException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    } on http.ClientException {
      throw const CatalogException(
        'Server bilan aloqa o‘rnatib bo‘lmadi. Internet aloqasini tekshiring.',
      );
    }
  }
}
