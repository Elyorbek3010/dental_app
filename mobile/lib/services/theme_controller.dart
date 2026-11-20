import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent theme controller supporting Light, Dark, and System modes.
class ThemeController extends ChangeNotifier {
  ThemeController({
    SharedPreferences? preferences,
  }) {
    _preferences = preferences;
  }

  static final ThemeController instance = ThemeController();

  static const String themeKey = 'patient_app_theme_mode';

  SharedPreferences? _preferences;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isInitialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _isInitialized;

  @visibleForTesting
  void setPreferences(SharedPreferences prefs) {
    _preferences = prefs;
  }

  Future<SharedPreferences> _getPrefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<void> initialize() async {
    try {
      final prefs = await _getPrefs();
      final saved = prefs.getString(themeKey);
      _themeMode = _parseThemeMode(saved);
    } catch (e) {
      debugPrint('[ThemeController] Error loading theme preference: $e');
      _themeMode = ThemeMode.system;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await _getPrefs();
      await prefs.setString(themeKey, _serializeThemeMode(mode));
    } catch (e) {
      debugPrint('[ThemeController] Error saving theme preference: $e');
    }
  }

  static ThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _serializeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
