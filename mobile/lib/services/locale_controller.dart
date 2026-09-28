import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight controller for managing, switching, and persisting the patient app locale.
///
/// Supported locales:
/// - Uzbek (`uz`) - Default
/// - Russian (`ru`)
/// - English (`en`)
class LocaleController extends ChangeNotifier {
  LocaleController({
    SharedPreferences? preferences,
  }) {
    _preferences = preferences;
  }

  static final LocaleController instance = LocaleController();

  static const String languageKey = 'patient_app_language_code';
  static const Locale defaultLocale = Locale('uz');
  static const List<String> supportedLanguageCodes = ['uz', 'ru', 'en'];

  SharedPreferences? _preferences;
  Locale _locale = defaultLocale;
  bool _isInitialized = false;

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isInitialized => _isInitialized;

  @visibleForTesting
  void setPreferences(SharedPreferences prefs) {
    _preferences = prefs;
  }

  Future<SharedPreferences> _getPrefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  /// Initializes the locale:
  /// 1. Load saved language if one exists in SharedPreferences.
  /// 2. Otherwise inspect device locale (passed in or PlatformDispatcher).
  /// 3. If device language is 'uz', 'ru', or 'en', use it.
  /// 4. Otherwise fall back to Uzbek ('uz').
  Future<void> initialize({Locale? deviceLocale}) async {
    try {
      final prefs = await _getPrefs();
      final savedCode = prefs.getString(languageKey);

      if (savedCode != null && supportedLanguageCodes.contains(savedCode)) {
        _locale = Locale(savedCode);
      } else {
        // Fallback to inspecting device locale
        final detected = deviceLocale ?? ui.PlatformDispatcher.instance.locale;
        final devCode = detected.languageCode.toLowerCase();
        if (supportedLanguageCodes.contains(devCode)) {
          _locale = Locale(devCode);
        } else {
          _locale = defaultLocale;
        }
      }
    } catch (e) {
      debugPrint('[LocaleController] Error loading saved locale: $e');
      _locale = defaultLocale;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Changes the current application locale and persists the selection.
  Future<void> setLocale(Locale newLocale) async {
    final code = newLocale.languageCode.toLowerCase();
    if (!supportedLanguageCodes.contains(code)) {
      debugPrint('[LocaleController] Unsupported locale code: $code');
      return;
    }

    if (_locale.languageCode == code) {
      return;
    }

    _locale = Locale(code);
    notifyListeners();

    try {
      final prefs = await _getPrefs();
      await prefs.setString(languageKey, code);
    } catch (e) {
      debugPrint('[LocaleController] Error saving locale preference: $e');
    }
  }

  /// Changes the current locale by language code string.
  Future<void> setLanguageCode(String code) async {
    await setLocale(Locale(code));
  }
}
