import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/patient_ticket.dart';
import '../models/reminder.dart';
import '../models/specialization.dart';
import '../services/catalog_service.dart';
import '../services/push_notification_service.dart';
import '../services/queue_realtime_service.dart';
import '../services/queue_service.dart';
import '../services/reminder_service.dart';
import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/dental_logo.dart';
import '../widgets/dental_surfaces.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/status_chip.dart';
import 'doctor_select_screen.dart';
import 'specialization_select_screen.dart';

/// Clean Premium Dental Patient Home Dashboard.
///
/// Integrates real active queue tickets, clinic dental specializations,
/// and saved reminder counts without fabricating any placeholder data.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.isActiveTab = true,
    this.onNavigateToQueue,
    this.onNavigateToReminders,
    this.queueService,
    this.catalogService,
    this.reminderService,
    this.pushNotificationService,
    this.realtimeService,
  });

  final bool isActiveTab;
  final VoidCallback? onNavigateToQueue;
  final VoidCallback? onNavigateToReminders;
  final QueueService? queueService;
  final CatalogService? catalogService;
  final ReminderService? reminderService;
  final PushNotificationService? pushNotificationService;
  final QueueRealtimeService? realtimeService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final Object _realtimeConsumer = Object();
  StreamSubscription<QueueUpdatedEvent>? _realtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? _pushSubscription;

  List<MyQueueTicket> _tickets = [];
  List<Specialization> _specializations = [];
  int _reminderCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadDashboardData());
    _subscribeToQueueUpdates();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActiveTab && widget.isActiveTab) {
      unawaited(_refreshTicketsOnly());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshTicketsOnly());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _pushSubscription?.cancel();
    _pushSubscription = null;
    (widget.realtimeService ?? QueueRealtimeService.instance)
        .disconnectConsumer(_realtimeConsumer);
    super.dispose();
  }

  void _subscribeToQueueUpdates() {
    try {
      final pushSvc = widget.pushNotificationService ?? PushNotificationService.instance;
      pushSvc.ensureListeners();
      _pushSubscription = pushSvc.queueEvents.listen((_) {
        if (mounted) unawaited(_refreshTicketsOnly());
      });
    } catch (_) {
      // Optional push listener in isolated test environments.
    }

    try {
      final realtimeSvc = widget.realtimeService ?? QueueRealtimeService.instance;
      _realtimeSubscription = realtimeSvc.events.listen((event) {
        if (!mounted) return;
        if (event.queueId == null ||
            _tickets.isEmpty ||
            _tickets.any((t) => t.queueId == event.queueId)) {
          unawaited(_refreshTicketsOnly());
        }
      });
    } catch (_) {
      // Optional realtime listener in isolated test environments.
    }
  }

  Future<void> _refreshTicketsOnly() async {
    final queueSvc = widget.queueService ?? QueueService.instance;
    try {
      final tickets = await queueSvc.getMyTickets();
      final active =
          tickets.where((t) => !t.isCompleted && !t.isCancelled).toList();
      if (!mounted) return;
      setState(() {
        _tickets = active;
      });
    } catch (_) {
      // Preserve last known state on transient errors.
    }
  }

  Future<void> _loadDashboardData() async {
    final queueSvc = widget.queueService ?? QueueService.instance;
    final catalogSvc = widget.catalogService ?? CatalogService.instance;
    final reminderSvc = widget.reminderService ?? ReminderService.instance;

    try {
      final ticketsFuture = queueSvc.getMyTickets().catchError((_) => <MyQueueTicket>[]);
      final specsFuture = catalogSvc.fetchSpecializations(clinicId: 1).catchError((_) => <Specialization>[]);
      final remindersFuture = reminderSvc.getReminders().catchError((_) => <Reminder>[]);

      final results = await Future.wait<dynamic>([
        ticketsFuture,
        specsFuture,
        remindersFuture,
      ]);

      final activeTickets = (results[0] as List<MyQueueTicket>)
          .where((t) => !t.isCompleted && !t.isCancelled)
          .toList();

      if (!mounted) return;
      setState(() {
        _tickets = activeTickets;
        _specializations = results[1] as List<Specialization>;
        _reminderCount = (results[2] as List).length;
      });

      if (activeTickets.isNotEmpty) {
        final clinicId = activeTickets.first.clinicId ??
            activeTickets.first.doctor.clinicId ??
            1;
        try {
          (widget.realtimeService ?? QueueRealtimeService.instance)
              .connectForConsumer(_realtimeConsumer, clinicId);
        } catch (_) {}
      }
    } catch (_) {
      // Fail gracefully without interrupting home rendering.
    }
  }

  void _navigateToQueueFlow(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SpecializationSelectScreen(),
      ),
    );
  }

  void _navigateToSpecialtyDoctors(BuildContext context, Specialization spec) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DoctorSelectScreen(
          specialization: spec,
          clinicId: 1,
        ),
      ),
    );
  }

  void _cycleQuickTheme(BuildContext context) {
    final ctrl = ThemeController.instance;
    final currentBrightness = Theme.of(context).brightness;
    ctrl.setThemeMode(
      currentBrightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dentalColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTicket = _tickets.isNotEmpty ? _tickets.first : null;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Architectural Top Brand Bar
                Row(
                  children: [
                    const DentalLogo(size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.appTitle,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            l10n.clinicPortalBadge,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => _cycleQuickTheme(context),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.border),
                          ),
                          child: Icon(
                            isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Hero Dental Concierge Card (wave motif)
                DentalWaveBackdrop(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.tealSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 14,
                                color: colors.teal,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  l10n.viewLiveQueueLabel,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.teal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.greeting,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.homeGreetingSubtitle,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const Key('home_join_queue_button'),
                            onPressed: () => _navigateToQueueFlow(context),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_circle_outline, size: 20),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    l10n.homeJoinQueueButton,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Asymmetric 2-Column Bento Services Grid
                Text(
                  l10n.quickAccessTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BentoActionCard(
                        icon: Icons.confirmation_number_outlined,
                        title: l10n.activeVisitStatusTitle,
                        subtitle: primaryTicket != null
                            ? '№${primaryTicket.ticketNumber} • ${primaryTicket.specialization.name}'
                            : l10n.viewLiveQueueLabel,
                        badgeText: '${_tickets.length}',
                        accentColor: colors.teal,
                        accentSoftColor: colors.tealSoft,
                        onTap: widget.onNavigateToQueue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BentoActionCard(
                        key: const Key('home_reminders_quick_button'),
                        icon: Icons.alarm_rounded,
                        title: l10n.homeRemindersSection,
                        subtitle: l10n.homeRemindersCardTitle,
                        badgeText: '$_reminderCount',
                        accentColor: colors.blue,
                        accentSoftColor: colors.blueSoft,
                        onTap: widget.onNavigateToReminders,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Real Backend Dental Specialties Strip (shown when loaded)
                if (_specializations.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.selectSpecializationTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _navigateToQueueFlow(context),
                        child: Text(l10n.viewButton),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _specializations.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final spec = _specializations[index];
                        return ActionChip(
                          avatar: Icon(
                            Icons.medical_services_outlined,
                            size: 16,
                            color: colors.teal,
                          ),
                          label: Text(
                            spec.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          backgroundColor: colors.surface,
                          side: BorderSide(color: colors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onPressed: () => _navigateToSpecialtyDoctors(context, spec),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Current Queue Live Ticket Preview OR Empty State
                Text(
                  l10n.homeCurrentQueueSection,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),

                if (primaryTicket != null)
                  _buildActiveVisitSpotlight(primaryTicket, l10n, colors)
                else
                  EmptyStateCard(
                    icon: Icons.confirmation_number_outlined,
                    title: l10n.homeNoActiveQueueTitle,
                    description: l10n.homeNoActiveQueueDesc,
                    buttonText: l10n.homeJoinQueueButton,
                    onButtonPressed: () => _navigateToQueueFlow(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveVisitSpotlight(
    MyQueueTicket ticket,
    AppLocalizations l10n,
    DentalThemeTokens colors,
  ) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: widget.onNavigateToQueue,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.teal.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.tealSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  '№${ticket.ticketNumber}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: colors.teal,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: StatusChip(
                            status: ticket.status,
                            label: ticket.localizedStatus(l10n),
                            isPaused: ticket.isQueuePaused,
                          ),
                        ),
                        if (_tickets.length > 1) ...[
                          const SizedBox(width: 6),
                          Text(
                            '+${_tickets.length - 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: colors.blue,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ticket.doctor.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ticket.specialization.name} • ${l10n.peopleAhead(ticket.peopleAhead)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: colors.teal,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
