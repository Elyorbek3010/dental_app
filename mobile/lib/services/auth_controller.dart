import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'auth_service.dart';

/// Lightweight session state controller managing patient authentication state,
/// startup session restoration, login, register, and logout.
class AuthController extends ChangeNotifier {
  AuthController({AuthService? authService})
      : _authService = authService ?? AuthService.instance;

  final AuthService _authService;

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _errorMessage;

  /// Whether the initial session check on app startup has completed.
  bool get isInitialized => _isInitialized;

  /// Whether an auth operation (login/register) is currently in progress.
  bool get isLoading => _isLoading;

  /// The active error message, if any.
  String? get errorMessage => _errorMessage;

  /// The currently authenticated patient user.
  PatientUser? get currentUser => _authService.currentUser;

  /// Whether a patient is actively authenticated.
  bool get isAuthenticated => currentUser != null;

  /// Clears the active error message.
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Checks for an existing saved session on startup.
  Future<void> checkAuthSession() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.restoreSession();
    } catch (e) {
      debugPrint('[AuthController] checkAuthSession error: $e');
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Logs in with phone and password. Returns true on success, false on failure.
  Future<bool> login({
    required String phone,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.login(phone: phone, password: password);
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Kutilmagan xatolik yuz berdi: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Registers a new patient. Returns true on success, false on failure.
  Future<bool> register({
    required String fullName,
    required String phone,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.register(
        fullName: fullName,
        phone: phone,
        password: password,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Kutilmagan xatolik yuz berdi: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logs out the patient and resets state.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logout();
    } catch (e) {
      debugPrint('[AuthController] Error during logout: $e');
    } finally {
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    }
  }
}
