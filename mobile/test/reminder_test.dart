import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/models/reminder.dart';
import 'package:app/services/local_notification_service.dart';
import 'package:app/services/reminder_service.dart';

class FakeLocalNotificationService implements LocalNotificationService {
  final List<int> scheduledIds = [];
  final List<int> cancelledIds = [];

  @override
  bool get isInitialized => true;

  @override
  Future<bool> initialize({
    void Function(NotificationResponse)? onNotificationResponse,
  }) async =>
      true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    scheduledIds.add(id);
    return true;
  }

  @override
  Future<bool> cancelNotification(int id) async {
    cancelledIds.add(id);
    return true;
  }

  @override
  Future<bool> cancelAllNotifications() async {
    cancelledIds.clear();
    return true;
  }

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reminder Model Tests', () {
    test('toJson and fromJson serialize and deserialize correctly', () {
      final scheduled = DateTime(2027, 3, 27, 10, 0);
      final reminder = Reminder(
        id: 42,
        scheduledAt: scheduled,
        note: 'Dental check-up',
      );

      final json = reminder.toJson();
      expect(json['id'], 42);
      expect(json['scheduledAt'], scheduled.toIso8601String());
      expect(json['note'], 'Dental check-up');

      final reconstructed = Reminder.fromJson(json);
      expect(reconstructed, equals(reminder));
      expect(reconstructed.id, 42);
      expect(reconstructed.scheduledAt, scheduled);
      expect(reconstructed.note, 'Dental check-up');
    });

    test('copyWith works as expected', () {
      final r1 = Reminder(
        id: 1,
        scheduledAt: DateTime(2027, 1, 1),
        note: 'Original',
      );
      final r2 = r1.copyWith(note: 'Modified');
      expect(r2.id, 1);
      expect(r2.scheduledAt, DateTime(2027, 1, 1));
      expect(r2.note, 'Modified');
    });

    test('isPast detects past and future dates', () {
      final pastReminder = Reminder(
        id: 1,
        scheduledAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final futureReminder = Reminder(
        id: 2,
        scheduledAt: DateTime.now().add(const Duration(days: 1)),
      );

      expect(pastReminder.isPast, isTrue);
      expect(futureReminder.isPast, isFalse);
    });
  });

  group('ReminderService Tests', () {
    late ReminderService service;
    late FakeLocalNotificationService fakeNotificationService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      fakeNotificationService = FakeLocalNotificationService();
      service = ReminderService(
        notificationService: fakeNotificationService,
        initialPreferences: prefs,
      );
    });

    test('formatNotificationBody returns note or default text', () {
      expect(
        ReminderService.formatNotificationBody('Dental check-up'),
        'Dental check-up',
      );
      expect(
        ReminderService.formatNotificationBody('   '),
        'Stomatolog tashrifingiz uchun eslatma.',
      );
      expect(
        ReminderService.formatNotificationBody(null),
        'Stomatolog tashrifingiz uchun eslatma.',
      );
    });

    test('createReminder rejects past dates', () async {
      final past = DateTime.now().subtract(const Duration(minutes: 10));
      expect(
        () => service.createReminder(scheduledAt: past, note: 'Test'),
        throwsA(isA<ArgumentError>()),
      );
      expect(fakeNotificationService.scheduledIds, isEmpty);
    });

    test('createReminder persists locally, assigns sequential unique IDs, and schedules notification',
        () async {
      final future1 = DateTime.now().add(const Duration(days: 2));
      final future2 = DateTime.now().add(const Duration(days: 1));

      final r1 = await service.createReminder(scheduledAt: future1, note: 'Checkup 1');
      expect(r1.id, 1);
      expect(r1.note, 'Checkup 1');
      expect(fakeNotificationService.scheduledIds, contains(1));

      final r2 = await service.createReminder(scheduledAt: future2, note: 'Checkup 2');
      expect(r2.id, 2);
      expect(fakeNotificationService.scheduledIds, contains(2));

      // getReminders sorts chronologically: future2 comes before future1
      final all = await service.getReminders();
      expect(all.length, 2);
      expect(all[0].id, 2);
      expect(all[1].id, 1);
    });

    test('updateReminder modifies reminder, cancels old notification, and schedules new one',
        () async {
      final future = DateTime.now().add(const Duration(days: 5));
      final created = await service.createReminder(scheduledAt: future, note: 'Initial');

      final newFuture = DateTime.now().add(const Duration(days: 6));
      final updated = await service.updateReminder(
        id: created.id,
        scheduledAt: newFuture,
        note: 'Updated Note',
      );

      expect(updated.id, created.id);
      expect(updated.note, 'Updated Note');
      expect(fakeNotificationService.cancelledIds, contains(created.id));
      expect(fakeNotificationService.scheduledIds.where((id) => id == created.id).length, 2);

      final all = await service.getReminders();
      expect(all.length, 1);
      expect(all.first.note, 'Updated Note');

      // Attempting to update to past date throws ArgumentError
      final past = DateTime.now().subtract(const Duration(hours: 1));
      expect(
        () => service.updateReminder(id: created.id, scheduledAt: past),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleteReminder removes from storage and cancels notification', () async {
      final future = DateTime.now().add(const Duration(days: 3));
      final r = await service.createReminder(scheduledAt: future, note: 'To delete');

      var all = await service.getReminders();
      expect(all.length, 1);

      await service.deleteReminder(r.id);

      expect(fakeNotificationService.cancelledIds, contains(r.id));
      all = await service.getReminders();
      expect(all, isEmpty);
    });
  });
}
