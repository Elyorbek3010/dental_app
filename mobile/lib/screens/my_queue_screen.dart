import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../l10n/l10n.dart';
import '../models/patient_ticket.dart';
import '../services/push_notification_service.dart';
import '../services/queue_realtime_service.dart';
import '../services/queue_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/empty_state_card.dart';
import 'qr_scanner_screen.dart';
import 'specialization_select_screen.dart';

/// Patient "My Queue" Screen.
///
/// Displays:
///  - WAITING: ticket card + check-in CTA + cancel option
///  - CALLED:  prominent "It's your turn" banner + room guidance + cancel
///  - SERVING: reception-in-progress banner
///  - 404:     empty state → join queue CTA
///
/// QR check-in uses the existing `POST /api/queues/check-in/qr` protocol.
/// Cancellation uses `PATCH /api/queues/my-ticket/cancel` (patient-owned only).
class MyQueueScreen extends StatefulWidget {
  const MyQueueScreen({
    super.key,
    this.queueService,
    this.pushNotificationService,
    this.realtimeService,
  });

  final QueueService? queueService;
  final PushNotificationService? pushNotificationService;
  final QueueRealtimeService? realtimeService;

  @override
  State<MyQueueScreen> createState() => _MyQueueScreenState();
}

class _MyQueueScreenState extends State<MyQueueScreen> with WidgetsBindingObserver {
  late final QueueService _queueService;
  late final PushNotificationService _pushNotificationService;
  late final QueueRealtimeService _realtimeService;
  StreamSubscription<Map<String, dynamic>>? _queueEventSubscription;
  StreamSubscription<QueueUpdatedEvent>? _realtimeSubscription;

  MyQueueTicket? _ticket;
  bool _isLoading = true;
  bool _isCheckingIn = false;
  bool _isCancelling = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueService = widget.queueService ?? QueueService.instance;
    _pushNotificationService =
        widget.pushNotificationService ?? PushNotificationService.instance;
    _realtimeService = widget.realtimeService ?? QueueRealtimeService.instance;
    _fetchMyTicket();
    _subscribeToQueueEvents();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[MyQueueScreen] App resumed from background, silently refreshing ticket');
      _pushNotificationService.ensureListeners();
      _fetchMyTicket(isSilent: _ticket != null);
      _connectRealtime();
    }
  }

  void _subscribeToQueueEvents() {
    _pushNotificationService.ensureListeners();
    _queueEventSubscription = _pushNotificationService.queueEvents.listen(
      (event) {
        if (!mounted) return;
        debugPrint('[MyQueueScreen] Received queue event, refreshing ticket');
        _fetchMyTicket(isSilent: _ticket != null);
      },
      onError: (Object error) {
        debugPrint('[MyQueueScreen] Error in queue event subscription: $error');
      },
    );

    _connectRealtime();
    _realtimeSubscription = _realtimeService.events.listen(
      (event) {
        if (!mounted) return;
        // Trigger refetch if event matches current queue, current queue was null, or clinic-wide
        if (event.queueId == null ||
            _ticket == null ||
            event.queueId == _ticket!.queueId) {
          debugPrint('[MyQueueScreen] Received WebSocket queue update, refreshing ticket');
          _fetchMyTicket(isSilent: _ticket != null);
        }
      },
      onError: (Object error) {
        debugPrint('[MyQueueScreen] Realtime WebSocket error: $error');
      },
    );
  }

  void _connectRealtime() {
    final clinicId = _ticket?.clinicId ?? _ticket?.doctor.clinicId ?? ApiConfig.defaultClinicId;
    _realtimeService.connect(clinicId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _queueEventSubscription?.cancel();
    _queueEventSubscription = null;
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    super.dispose();
  }

  Future<void> _fetchMyTicket({bool isSilent = false}) async {
    if (isSilent && (_isCheckingIn || _isCancelling)) return;

    if (!isSilent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final ticket = await _queueService.getMyTicket();
      if (mounted) {
        setState(() {
          _ticket = ticket;
          _isLoading = false;
        });
        if (ticket != null) {
          final clinicId = ticket.clinicId ?? ticket.doctor.clinicId ?? ApiConfig.defaultClinicId;
          if (_realtimeService.activeClinicId != clinicId) {
            _realtimeService.connect(clinicId);
          }
        }
      }
    } on QueueException catch (e) {
      if (mounted) {
        setState(() {
          if (e.statusCode == 401) {
            _ticket = null;
          } else if (!isSilent) {
            _errorMessage = e.message;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!isSilent) {
            _errorMessage = 'Kutilmagan xatolik yuz berdi: $e';
          }
          _isLoading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // QR Check-in
  // ---------------------------------------------------------------------------

  Future<void> _startQrScan() async {
    final scanned = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => const QrScannerScreen(),
      ),
    );

    if (scanned == null || scanned.trim().isEmpty) return;
    await _submitQrToken(scanned.trim());
  }

  Future<void> _submitQrToken(String token) async {
    if (_isCheckingIn) return;
    setState(() => _isCheckingIn = true);

    try {
      await _queueService.checkInWithQr(token);
      if (mounted) {
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('checkin_success_snackbar'),
            content: Text(l10n.checkInSuccessSnackbar),
            backgroundColor: AppTheme.success,
          ),
        );
        // Refresh to show updated check-in state
        await _fetchMyTicket();
      }
    } on QueueException catch (e) {
      if (mounted) {
        final l10n = context.l10n;
        String message = e.message;
        if (e.statusCode == 400) message = l10n.errorInvalidQrCode;
        if (e.statusCode == 404) message = l10n.errorNoWaitingTicketForClinic;
        if (e.statusCode == 409) message = l10n.errorTicketAlreadyCheckedIn;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('checkin_error_snackbar'),
            content: Text(message),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('checkin_unexpected_error_snackbar'),
            content: Text('Kutilmagan xatolik: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingIn = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Cancellation
  // ---------------------------------------------------------------------------

  Future<void> _confirmAndCancelTicket() async {
    final l10n = context.l10n;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('cancel_confirm_dialog'),
        title: Text(l10n.cancelConfirmTitle),
        content: Text(l10n.cancelConfirmMessage),
        actions: [
          TextButton(
            key: const Key('cancel_confirm_no_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancelConfirmNo),
          ),
          ElevatedButton(
            key: const Key('cancel_confirm_yes_button'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.cancelConfirmYes,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _cancelTicket();
  }

  Future<void> _cancelTicket() async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);

    try {
      await _queueService.cancelTicket();
      if (mounted) {
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('cancel_success_snackbar'),
            content: Text(l10n.cancelSuccessSnackbar),
            backgroundColor: AppTheme.success,
          ),
        );
        // Refresh — ticket gone → show empty state
        await _fetchMyTicket();
      }
    } on QueueException catch (e) {
      if (mounted) {
        final l10n = context.l10n;
        String message = e.message;
        if (e.statusCode == 403) message = l10n.errorCannotCancelOtherTicket;
        if (e.statusCode == 409) message = l10n.errorOnlyWaitingCalledCancellable;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('cancel_error_snackbar'),
            content: Text(message),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kutilmagan xatolik: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _navigateToQueueFlow(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SpecializationSelectScreen(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myQueueTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshTooltip,
            onPressed: _isLoading ? null : _fetchMyTicket,
          ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        key: const Key('my_queue_refresh_indicator_error'),
        onRefresh: _fetchMyTicket,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              EmptyStateCard(
                icon: Icons.error_outline,
                title: l10n.errorOccurred,
                description: localizeError(_errorMessage, l10n),
                buttonText: l10n.retryButton,
                onButtonPressed: _fetchMyTicket,
              ),
            ],
          ),
        ),
      );
    }

    final ticket = _ticket;

    if (ticket == null) {
      return RefreshIndicator(
        key: const Key('my_queue_refresh_indicator_empty'),
        onRefresh: _fetchMyTicket,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              EmptyStateCard(
                icon: Icons.receipt_long_outlined,
                title: l10n.myQueueNoActiveTitle,
                description: l10n.myQueueNoActiveDesc,
                buttonText: l10n.homeJoinQueueButton,
                onButtonPressed: () => _navigateToQueueFlow(context),
              ),
              const SizedBox(height: 24),
              _buildFeatureOverviewCard(l10n),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      key: const Key('my_queue_refresh_indicator_ticket'),
      onRefresh: _fetchMyTicket,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // CALLED: prominent banner
            if (ticket.isCalled) _buildCalledBanner(ticket, l10n),

            // SERVING: in-progress banner
            if (ticket.isServing) _buildServingBanner(l10n),

            if (ticket.isCalled || ticket.isServing) const SizedBox(height: 16),

            _buildTicketCard(ticket, l10n),
            const SizedBox(height: 16),

            // Check-in card (only when WAITING and not already checked in)
            if (ticket.isWaiting) ...[
              _buildCheckInCard(ticket, l10n),
              const SizedBox(height: 16),
            ],

            _buildImportantNotesCard(ticket, l10n),
            const SizedBox(height: 16),

            // Cancel button — only for WAITING or CALLED
            if (ticket.isWaiting || ticket.isCalled)
              _buildCancelButton(l10n),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CALLED Banner
  // ---------------------------------------------------------------------------

  Widget _buildCalledBanner(MyQueueTicket ticket, AppLocalizations l10n) {
    return Container(
      key: const Key('called_banner'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.warning,
            AppTheme.warning.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.warning.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active, color: Colors.white, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.calledBannerTitle,
                  key: const Key('called_banner_title'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                if (ticket.doctor.roomNumber != null &&
                    ticket.doctor.roomNumber!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${l10n.calledBannerSubtitle} — ${l10n.roomWithNumber(ticket.doctor.roomNumber!)}',
                      key: const Key('called_banner_subtitle'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.calledBannerSubtitle,
                      key: const Key('called_banner_subtitle'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SERVING Banner
  // ---------------------------------------------------------------------------

  Widget _buildServingBanner(AppLocalizations l10n) {
    return Container(
      key: const Key('serving_banner'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.success,
            AppTheme.success.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.success.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services, color: Colors.white, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.servingBannerTitle,
                  key: const Key('serving_banner_title'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.servingBannerSubtitle,
                    key: const Key('serving_banner_subtitle'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Ticket Card
  // ---------------------------------------------------------------------------

  Widget _buildTicketCard(MyQueueTicket ticket, AppLocalizations l10n) {
    Color statusColor;
    Color statusBgColor;

    switch (ticket.status.toUpperCase()) {
      case 'CALLED':
        statusColor = AppTheme.warning;
        statusBgColor = AppTheme.warning.withValues(alpha: 0.15);
        break;
      case 'SERVING':
        statusColor = AppTheme.success;
        statusBgColor = AppTheme.success.withValues(alpha: 0.15);
        break;
      case 'WAITING':
      default:
        statusColor = AppTheme.primary;
        statusBgColor = AppTheme.primaryLight;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: const Border(bottom: BorderSide(color: AppTheme.cardBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.confirmation_number_outlined,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.ticketNumberLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ticket.localizedStatus(l10n),
                    key: const Key('my_ticket_status_badge'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Ticket number + people ahead
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            child: Column(
              children: [
                Text(
                  '№${ticket.ticketNumber}',
                  key: const Key('my_ticket_number_text'),
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_outline, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        l10n.peopleAhead(ticket.peopleAhead),
                        key: const Key('my_ticket_people_ahead_text'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.cardBorder),

          // Details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildTicketDetailRow(
                  icon: Icons.person_outline,
                  label: l10n.doctorLabel,
                  value: ticket.doctor.fullName,
                  valueKey: const Key('my_ticket_doctor_name'),
                ),
                const SizedBox(height: 14),
                _buildTicketDetailRow(
                  icon: Icons.medical_services_outlined,
                  label: l10n.specializationLabel,
                  value: ticket.specialization.name,
                  valueKey: const Key('my_ticket_specialization_name'),
                ),
                if (ticket.doctor.roomNumber != null &&
                    ticket.doctor.roomNumber!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildTicketDetailRow(
                    icon: Icons.meeting_room_outlined,
                    label: l10n.roomLabel,
                    value: l10n.roomWithNumber(ticket.doctor.roomNumber!),
                    valueKey: const Key('my_ticket_room_number'),
                  ),
                ],
                if (ticket.queuePosition != null) ...[
                  const SizedBox(height: 14),
                  _buildTicketDetailRow(
                    icon: Icons.format_list_numbered,
                    label: l10n.queuePositionLabel,
                    value: '#${ticket.queuePosition}',
                  ),
                ],
                const SizedBox(height: 14),
                _buildTicketDetailRow(
                  icon: Icons.access_time_outlined,
                  label: l10n.ticketTimeLabel,
                  value: _formatDateTime(ticket.createdAt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Check-in Card
  // ---------------------------------------------------------------------------

  Widget _buildCheckInCard(MyQueueTicket ticket, AppLocalizations l10n) {
    final isCheckedIn = ticket.isCheckedIn;

    return Container(
      key: const Key('checkin_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCheckedIn ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isCheckedIn ? Icons.check_circle : Icons.info_outline,
                color: isCheckedIn ? AppTheme.success : AppTheme.warning,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCheckedIn
                          ? l10n.checkedInStatusTitle
                          : l10n.notCheckedInStatusTitle,
                      key: const Key('my_ticket_checkin_status_text'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCheckedIn ? AppTheme.success : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCheckedIn
                          ? l10n.checkedInStatusDesc
                          : l10n.notCheckedInStatusDesc,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // QR check-in actions — only when NOT yet checked in
          if (!isCheckedIn) ...[
            const SizedBox(height: 14),
            Text(
              l10n.waitingCheckInPrompt,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            _isCheckingIn
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        key: const Key('qr_checkin_button'),
                        onPressed: _startQrScan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(l10n.checkInButtonText),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cancel Button
  // ---------------------------------------------------------------------------

  Widget _buildCancelButton(AppLocalizations l10n) {
    if (_isCancelling) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const Key('cancel_ticket_button'),
      onPressed: _confirmAndCancelTicket,
      icon: const Icon(Icons.cancel_outlined, color: AppTheme.error),
      label: Text(l10n.cancelTicketButton),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.error,
        side: const BorderSide(color: AppTheme.error),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildImportantNotesCard(MyQueueTicket ticket, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined, size: 18, color: AppTheme.secondary),
              const SizedBox(width: 8),
              Text(
                l10n.myQueueReminderTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.myQueueReminderDesc,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Key? valueKey,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          key: valueKey,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureOverviewCard(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: AppTheme.secondary, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.featuresTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFeatureBullet(l10n.featureTicketAndSpec),
          _buildFeatureBullet(l10n.featureLiveQueue),
          _buildFeatureBullet(l10n.featureCheckIn),
          _buildFeatureBullet(l10n.featurePushNotifications),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.check_circle_outline, size: 14, color: AppTheme.secondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}
