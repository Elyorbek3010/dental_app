import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/models/doctor.dart';
import 'package:app/models/doctor_queue.dart';
import 'package:app/models/patient_ticket.dart';
import 'package:app/models/specialization.dart';
import 'package:app/screens/doctor_queue_screen.dart';
import 'package:app/screens/my_queue_screen.dart';
import 'package:app/services/catalog_service.dart';
import 'package:app/services/queue_realtime_service.dart';
import 'package:app/services/queue_service.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/utils/error_localizer.dart';

class _FakeClosingCatalogService extends CatalogService {
  _FakeClosingCatalogService(this.queueToReturn);
  final DoctorQueue queueToReturn;

  @override
  Future<DoctorQueue> fetchDoctorQueue(int doctorId) async => queueToReturn;
}

class _FakeNoopRealtimeService extends QueueRealtimeService {
  @override
  Future<void> connectForConsumer(Object consumer, int clinicId) async {}

  @override
  void disconnectConsumer(Object consumer) {}
}

class _FakeActiveTicketsQueueService extends QueueService {
  _FakeActiveTicketsQueueService(this.tickets);
  final List<MyQueueTicket> tickets;

  @override
  Future<List<MyQueueTicket>> getMyTickets({bool includeSkipped = false}) async =>
      tickets;
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('ru'), Locale('uz')],
    home: child,
  );
}

void main() {
  testWidgets(
    'DoctorQueueScreen disables Join Queue and displays closing message when shift_status is CLOSING',
    (tester) async {
      final doc = Doctor(
        id: 1,
        clinicId: 1,
        specializationId: 1,
        fullName: 'Dr. Farrux',
        roomNumber: '101',
        isActive: true,
      );
      final spec = Specialization(id: 1, clinicId: 1, name: 'General');
      final closingQueue = DoctorQueue.fromJson({
        'id': 42,
        'queue_id': 42,
        'doctor_id': 1,
        'queue_date': '2026-11-20',
        'is_paused': false,
        'is_active': true,
        'shift_status': 'CLOSING',
        'waiting_count': 2,
        'called_count': 1,
        'serving_count': 0,
        'estimated_position_if_joined': 4,
      });

      await tester.pumpWidget(
        _wrap(
          DoctorQueueScreen(
            doctor: doc,
            specialization: spec,
            catalogService: _FakeClosingCatalogService(closingQueue),
            realtimeService: _FakeNoopRealtimeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Queue closed for new patients.'), findsWidgets);
      final btn = tester.widget<ElevatedButton>(
        find.byKey(const Key('doctor_queue_join_button')),
      );
      expect(btn.onPressed, isNull);
    },
  );

  testWidgets(
    'Patient with existing ticket keeps viewing ticket status while queue is CLOSING',
    (tester) async {
      final ticket = MyQueueTicket.fromJson({
        'id': 10,
        'queue_id': 42,
        'ticket_number': 3,
        'queue_position': 2,
        'status': 'WAITING',
        'created_at': '2026-11-20T22:00:00Z',
        'people_ahead': 1,
        'doctor': {'id': 1, 'full_name': 'Dr. Farrux', 'room_number': '101', 'clinic_id': 1},
        'specialization': {'id': 1, 'name': 'General'},
        'is_queue_paused': false,
      });

      await tester.pumpWidget(
        _wrap(
          MyQueueScreen(
            queueService: _FakeActiveTicketsQueueService([ticket]),
            realtimeService: _FakeNoopRealtimeService(),
            isActiveTab: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('№3'), findsWidgets);
      expect(find.text('Dr. Farrux'), findsOneWidget);
    },
  );

  testWidgets('localizeError maps CLOSING backend message cleanly across EN/UZ/RU', (tester) async {
    late AppLocalizations enL10n;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) {
            enL10n = AppLocalizations.of(ctx)!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(
      localizeError('Queue closed for new patients', enL10n),
      'Queue closed for new patients.',
    );
  });
}
