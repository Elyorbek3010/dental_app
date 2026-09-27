import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';
import 'local_notification_service.dart';

/// Service responsible for managing patient personal reminders:
/// - Local persistence via [SharedPreferences]
/// - Synchronization with native Android alarms via [LocalNotificationService]
class ReminderService {
  ReminderService({
    LocalNotificationService? notificationService,
    SharedPreferences? initialPreferences,
  })  : _notificationService =
            notificationService ?? LocalNotificationService.instance,
        _preferences = initialPreferences;

  static final ReminderService instance = ReminderService();

  final LocalNotificationService _notificationService;
  SharedPreferences? _preferences;

  static const String _storageKey = 'patient_personal_reminders';
  static const String notificationTitle = 'Dental Queue';
  static const String defaultNotificationBody =
      'Stomatolog tashrifingiz uchun eslatma.';

  Future<SharedPreferences> _getPrefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  /// Sets custom SharedPreferences (useful for unit testing with mock instances).
  @visibleForTesting
  void setPreferences(SharedPreferences prefs) {
    _preferences = prefs;
  }

  /// Formats notification body according to product specifications:
  /// Uses patient note if non-empty, otherwise falls back to default body.
  static String formatNotificationBody(String? note) {
    if (note != null && note.trim().isNotEmpty) {
      return note.trim();
    }
    return defaultNotificationBody;
  }

  /// Retrieves all reminders from local storage, sorted chronologically by [scheduledAt].
  Future<List<Reminder>> getReminders() async {
    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> decoded = jsonDecode(jsonString) as List<dynamic>;
      final reminders = decoded
          .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
          .toList();

      reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return reminders;
    } catch (e) {
      debugPrint('[ReminderService] Error reading reminders: $e');
      return [];
    }
  }

  /// Persists the list of reminders to local storage.
  Future<void> _saveReminders(List<Reminder> reminders) async {
    reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final prefs = await _getPrefs();
    final jsonList = reminders.map((r) => r.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  /// Generates a unique, stable 32-bit positive integer ID for a new reminder.
  int _generateUniqueId(List<Reminder> existing) {
    if (existing.isEmpty) {
      return 1;
    }
    int maxId = 0;
    for (final r in existing) {
      if (r.id > maxId) {
        maxId = r.id;
      }
    }
    return maxId + 1;
  }

  /// Creates a new reminder:
  /// 1. Validates that [scheduledAt] is in the future.
  /// 2. Saves to local storage.
  /// 3. Schedules the native notification.
  Future<Reminder> createReminder({
    required DateTime scheduledAt,
    String? note,
  }) async {
    final now = DateTime.now();
    if (scheduledAt.isBefore(now)) {
      throw ArgumentError(
        'Eslatma vaqti kelajakda bo‘lishi kerak (Scheduled date must be in the future).',
      );
    }

    final existing = await getReminders();
    final newId = _generateUniqueId(existing);
    final trimmedNote = note?.trim().isEmpty ?? true ? null : note!.trim();

    final reminder = Reminder(
      id: newId,
      scheduledAt: scheduledAt,
      note: trimmedNote,
    );

    existing.add(reminder);
    await _saveReminders(existing);

    // Schedule notification
    final body = formatNotificationBody(trimmedNote);
    await _notificationService.scheduleNotification(
      id: reminder.id,
      title: notificationTitle,
      body: body,
      scheduledDate: reminder.scheduledAt,
    );

    debugPrint('[ReminderService] Created reminder #$newId for $scheduledAt');
    return reminder;
  }

  /// Updates an existing reminder:
  /// 1. Validates that [scheduledAt] is in the future.
  /// 2. Cancels old scheduled notification.
  /// 3. Updates local storage.
  /// 4. Schedules updated notification.
  Future<Reminder> updateReminder({
    required int id,
    required DateTime scheduledAt,
    String? note,
  }) async {
    final now = DateTime.now();
    if (scheduledAt.isBefore(now)) {
      throw ArgumentError(
        'Eslatma vaqti kelajakda bo‘lishi kerak (Scheduled date must be in the future).',
      );
    }

    final existing = await getReminders();
    final index = existing.indexWhere((r) => r.id == id);
    if (index == -1) {
      throw StateError('Eslatma topilmadi (Reminder #$id not found).');
    }

    final trimmedNote = note?.trim().isEmpty ?? true ? null : note!.trim();
    final updated = Reminder(
      id: id,
      scheduledAt: scheduledAt,
      note: trimmedNote,
    );

    // 1. Cancel previous notification
    await _notificationService.cancelNotification(id);

    // 2. Update storage
    existing[index] = updated;
    await _saveReminders(existing);

    // 3. Schedule updated notification
    final body = formatNotificationBody(trimmedNote);
    await _notificationService.scheduleNotification(
      id: updated.id,
      title: notificationTitle,
      body: body,
      scheduledDate: updated.scheduledAt,
    );

    debugPrint('[ReminderService] Updated reminder #$id for $scheduledAt');
    return updated;
  }

  /// Deletes a reminder:
  /// 1. Cancels scheduled notification.
  /// 2. Removes from local storage.
  Future<void> deleteReminder(int id) async {
    // 1. Cancel notification
    await _notificationService.cancelNotification(id);

    // 2. Remove from local storage
    final existing = await getReminders();
    existing.removeWhere((r) => r.id == id);
    await _saveReminders(existing);

    debugPrint('[ReminderService] Deleted reminder #$id');
  }
}
