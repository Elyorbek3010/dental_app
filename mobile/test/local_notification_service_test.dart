import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalNotificationService Tests', () {
    test('Singleton instance and reminderChannel constants are configured correctly', () {
      final service = LocalNotificationService.instance;
      expect(service, isNotNull);
      expect(LocalNotificationService.reminderChannel.id, 'patient_reminders_channel');
      expect(LocalNotificationService.reminderChannel.name, 'Bemor eslatmalari');
      expect(LocalNotificationService.reminderChannel.importance, Importance.high);
      expect(LocalNotificationService.reminderChannel.playSound, isTrue);
      expect(LocalNotificationService.reminderChannel.enableVibration, isTrue);
    });

    test('scheduleNotification rejects past dates cleanly without throwing', () async {
      final service = LocalNotificationService.instance;
      final pastDate = DateTime.now().subtract(const Duration(minutes: 5));

      final result = await service.scheduleNotification(
        id: 999,
        title: 'Past Reminder',
        body: 'This should be rejected',
        scheduledDate: pastDate,
      );

      expect(result, isFalse);
    });
  });
}
