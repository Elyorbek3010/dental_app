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
import '../widgets/circular_countdown.dart';
import '../widgets/dental_surfaces.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/status_chip.dart';
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
    this.isActiveTab = true,
    this.queueService,
    this.pushNotificationService,
    this.realtimeService,
    this.nowProvider,
  });

  final bool isActiveTab;
  final QueueService? queueService;
  final PushNotificationService? pushNotificationService;
  final QueueRealtimeService? realtimeService;
  final DateTime Function()? nowProvider;

  @override
  State<MyQueueScreen> createState() => _MyQueueScreenState();
}

class _MyQueueScreenState extends State<MyQueueScreen> with WidgetsBindingObserver {
  static const List<int> _expiryRetryDelaysSeconds = <int>[2, 3, 5];

  late final QueueService _queueService;
  late final PushNotificationService _pushNotificationService;
  late final QueueRealtimeService _realtimeService;
  final Object _realtimeConsumer = Object();
  StreamSubscription<Map<String, dynamic>>? _queueEventSubscription;
  StreamSubscription<QueueUpdatedEvent>? _realtimeSubscription;
  StreamSubscription<bool>? _connectionStateSubscription;
  StreamSubscription<int>? _reconnectedSubscription;
  Timer? _countdownTimer;
  Timer? _recoveryRetryTimer;

  List<MyQueueTicket> _tickets = [];
  bool _isLoading = true;
  int? _checkingInTicketId;
  int? _cancellingTicketId;
  String? _errorMessage;
  String? _lastForegroundNoticeKey;
  DateTime? _lastForegroundNoticeAt;

  // Request sequencing and coalescing for concurrent WS/FCM/manual refreshes
  int _latestFetchSeq = 0;
  int? _activeSilentFetchSeq;
  bool _queuedSilentRefresh = false;

  // Sync / connectivity degradation state
  bool _isHttpSyncDegraded = false;
  bool _isRealtimeDegraded = false;
  bool get _showSyncWarning =>
      _tickets.isNotEmpty && (_isHttpSyncDegraded || _isRealtimeDegraded);

  // Per-ticket bounded countdown expiry recovery state
  final Map<int, DateTime> _trackedDeadlines = <int, DateTime>{};
  final Map<int, int> _expiryAttempts = <int, int>{};
  final Map<int, int> _expiryTicksRemaining = <int, int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueService = widget.queueService ?? QueueService.instance;
    _pushNotificationService =
        widget.pushNotificationService ?? PushNotificationService.instance;
    _realtimeService = widget.realtimeService ?? QueueRealtimeService.instance;
    _fetchMyTickets();
    _subscribeToQueueEvents();
  }

  @override
  void didUpdateWidget(covariant MyQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActiveTab && widget.isActiveTab) {
      unawaited(_fetchMyTickets(isSilent: _tickets.isNotEmpty));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[MyQueueScreen] App resumed from background, silently refreshing tickets');
      _pushNotificationService.ensureListeners();
      unawaited(_fetchMyTickets(isSilent: _tickets.isNotEmpty, bypassCoalescing: true));
      _connectRealtime(forceReconnect: true);
    }
  }

  void _subscribeToQueueEvents() {
    _pushNotificationService.ensureListeners();
    _queueEventSubscription = _pushNotificationService.queueEvents.listen(
      (event) {
        if (!mounted) return;
        debugPrint('[MyQueueScreen] Received queue event, refreshing tickets');
        _showForegroundQueueFeedback(event);
        unawaited(_fetchMyTickets(isSilent: _tickets.isNotEmpty));
      },
      onError: (Object error) {
        debugPrint('[MyQueueScreen] Error in queue event subscription: $error');
      },
    );

    _connectRealtime();
    _realtimeSubscription = _realtimeService.events.listen(
      (event) {
        if (!mounted) return;
        // Trigger refetch if event matches any active queue, list was empty, or clinic-wide
        if (event.queueId == null ||
            _tickets.isEmpty ||
            _tickets.any((t) => t.queueId == event.queueId)) {
          debugPrint('[MyQueueScreen] Received WebSocket queue update, refreshing tickets');
          unawaited(_fetchMyTickets(isSilent: _tickets.isNotEmpty));
        }
      },
      onError: (Object error) {
        debugPrint('[MyQueueScreen] Realtime WebSocket error: $error');
      },
    );

    _connectionStateSubscription = _realtimeService.connectionStates.listen(
      (isHealthy) {
        if (!mounted) return;
        if (!isHealthy) {
          if (_tickets.isNotEmpty && !_isRealtimeDegraded) {
            setState(() => _isRealtimeDegraded = true);
          }
        } else if (_isRealtimeDegraded) {
          setState(() => _isRealtimeDegraded = false);
        }
      },
    );

    _reconnectedSubscription = _realtimeService.onReconnected.listen(
      (_) {
        if (!mounted) return;
        debugPrint('[MyQueueScreen] WebSocket reconnected, refreshing tickets');
        if (_isRealtimeDegraded) {
          setState(() => _isRealtimeDegraded = false);
        }
        unawaited(_fetchMyTickets(isSilent: _tickets.isNotEmpty, bypassCoalescing: true));
      },
    );
  }

  void _showForegroundQueueFeedback(Map<String, dynamic> event) {
    if (!mounted) return;
    final eventType =
        (event['event_type'] ?? PushNotificationService.parseQueueEventType(event))
            ?.toString()
            .toUpperCase();
    if (eventType == null) return;

    final l10n = context.l10n;
    String? message;
    Color bgColor = AppTheme.primary;

    switch (eventType) {
      case 'CALLED':
        message = l10n.fgNotifCalled;
        bgColor = AppTheme.warning;
        break;
      case 'SKIPPED':
        message = l10n.fgNotifSkipped;
        bgColor = AppTheme.warning;
        break;
      case 'RESTORED':
        message = l10n.fgNotifRestored;
        bgColor = AppTheme.success;
        break;
      case 'MISSED_TURN':
        message = l10n.fgNotifMissedTurn;
        bgColor = AppTheme.warning;
        break;
      default:
        return;
    }

    final dedupKey = '$eventType:${event['ticket_id'] ?? event['queue_id'] ?? ''}';
    final now = DateTime.now();
    if (_lastForegroundNoticeKey == dedupKey &&
        _lastForegroundNoticeAt != null &&
        now.difference(_lastForegroundNoticeAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastForegroundNoticeKey = dedupKey;
    _lastForegroundNoticeAt = now;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        key: Key('foreground_notif_${eventType.toLowerCase()}'),
        content: Text(message),
        backgroundColor: bgColor,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _connectRealtime({bool forceReconnect = false}) {
    final firstTicket = _tickets.isNotEmpty ? _tickets.first : null;
    final clinicId =
        firstTicket?.clinicId ?? firstTicket?.doctor.clinicId ?? ApiConfig.defaultClinicId;
    if (forceReconnect) {
      _realtimeService.ensureConnected(clinicId, forceReconnect: true);
    }
    _realtimeService.connectForConsumer(_realtimeConsumer, clinicId);
  }

  DateTime _utcNow() => widget.nowProvider?.call() ?? DateTime.now().toUtc();

  void _clearExpiryTracking() {
    _trackedDeadlines.clear();
    _expiryAttempts.clear();
    _expiryTicksRemaining.clear();
  }

  void _reconcileExpiryTracking(List<MyQueueTicket> tickets) {
    final activeCalledIds = <int>{};
    for (final ticket in tickets) {
      final canCountDown = ticket.isCalled &&
          !ticket.isQueuePaused &&
          ticket.pausedRemainingSeconds == null &&
          ticket.callDeadlineAt != null;
      if (!canCountDown) continue;

      activeCalledIds.add(ticket.id);
      final deadlineUtc = ticket.callDeadlineAt!.toUtc();
      final prevDeadline = _trackedDeadlines[ticket.id];
      if (prevDeadline == null || prevDeadline != deadlineUtc) {
        _trackedDeadlines[ticket.id] = deadlineUtc;
        _expiryAttempts[ticket.id] = 0;
        _expiryTicksRemaining.remove(ticket.id);
      }
    }

    _trackedDeadlines.removeWhere((id, _) => !activeCalledIds.contains(id));
    _expiryAttempts.removeWhere((id, _) => !activeCalledIds.contains(id));
    _expiryTicksRemaining.removeWhere((id, _) => !activeCalledIds.contains(id));
  }

  void _checkAndScheduleExpiredTickets({required bool decrementTicks}) {
    bool shouldRefresh = false;

    for (final ticket in _tickets) {
      final canCountDown = ticket.isCalled &&
          !ticket.isQueuePaused &&
          ticket.pausedRemainingSeconds == null &&
          ticket.callDeadlineAt != null;
      if (!canCountDown) continue;

      final remaining = _remainingCallSeconds(ticket);
      if (remaining == null || remaining > 0) {
        continue;
      }

      final attempts = _expiryAttempts[ticket.id] ?? 0;
      if (attempts >= _expiryRetryDelaysSeconds.length) {
        continue;
      }

      final currentTicks = _expiryTicksRemaining[ticket.id];
      if (currentTicks == null) {
        _expiryTicksRemaining[ticket.id] = _expiryRetryDelaysSeconds[attempts];
      } else if (decrementTicks) {
        final nextTicks = currentTicks - 1;
        if (nextTicks <= 0) {
          final nextAttempts = attempts + 1;
          _expiryAttempts[ticket.id] = nextAttempts;
          if (nextAttempts < _expiryRetryDelaysSeconds.length) {
            _expiryTicksRemaining[ticket.id] =
                _expiryRetryDelaysSeconds[nextAttempts];
          } else {
            _expiryTicksRemaining.remove(ticket.id);
          }
          shouldRefresh = true;
        } else {
          _expiryTicksRemaining[ticket.id] = nextTicks;
        }
      }
    }

    if (shouldRefresh) {
      unawaited(_fetchMyTickets(isSilent: true));
    }
  }

  void _syncCountdownTimer() {
    final shouldTick = _tickets.any(
      (ticket) =>
          ticket.isCalled &&
          !ticket.isQueuePaused &&
          ticket.pausedRemainingSeconds == null &&
          ticket.callDeadlineAt != null,
    );

    if (!shouldTick) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }

    _checkAndScheduleExpiredTickets(decrementTicks: false);

    _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _checkAndScheduleExpiredTickets(decrementTicks: true);
    });
  }

  int? _remainingCallSeconds(MyQueueTicket ticket) {
    if (!ticket.isCalled) return null;
    if (ticket.pausedRemainingSeconds != null) {
      final paused = ticket.pausedRemainingSeconds!;
      return paused < 0 ? 0 : paused;
    }
    final deadline = ticket.callDeadlineAt;
    if (deadline == null) return null;

    final offset = (ticket.serverTime != null && ticket.fetchedAt != null)
        ? ticket.serverTime!.difference(ticket.fetchedAt!)
        : Duration.zero;
    final adjustedNow = _utcNow().add(offset);
    final remainingMs = deadline.toUtc().difference(adjustedNow).inMilliseconds;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 1000).ceil();
  }

  String _formatCountdownMmSs(int totalSeconds) {
    final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final mins = safeSeconds ~/ 60;
    final secs = safeSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _scheduleRecoveryRetry() {
    if (!mounted || _tickets.isEmpty || _recoveryRetryTimer != null) return;
    _recoveryRetryTimer = Timer(const Duration(seconds: 5), () {
      _recoveryRetryTimer = null;
      if (!mounted || _tickets.isEmpty || !_isHttpSyncDegraded) return;
      unawaited(_fetchMyTickets(isSilent: true));
    });
  }

  void _cancelRecoveryRetryTimer() {
    _recoveryRetryTimer?.cancel();
    _recoveryRetryTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _cancelRecoveryRetryTimer();
    _clearExpiryTracking();
    _queueEventSubscription?.cancel();
    _queueEventSubscription = null;
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    _reconnectedSubscription?.cancel();
    _reconnectedSubscription = null;
    _realtimeService.disconnectConsumer(_realtimeConsumer);
    super.dispose();
  }

  Future<void> _fetchMyTickets({
    bool isSilent = false,
    bool bypassCoalescing = false,
  }) async {
    if (isSilent && (_checkingInTicketId != null || _cancellingTicketId != null)) {
      _queuedSilentRefresh = true;
      return;
    }

    if (isSilent && !bypassCoalescing && _activeSilentFetchSeq != null) {
      _queuedSilentRefresh = true;
      return;
    }

    final int fetchSeq = ++_latestFetchSeq;
    final bool isCoalescedSilent = isSilent && !bypassCoalescing;
    if (isCoalescedSilent) {
      _activeSilentFetchSeq = fetchSeq;
    } else {
      _queuedSilentRefresh = false;
      if (!isSilent && _tickets.isEmpty) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
    }

    try {
      _queueService.setIncludeSkipped(true);
      final rawTickets = await _queueService.getMyTickets();
      final tickets = rawTickets
          .where((t) => !t.isCompleted && !t.isCancelled)
          .toList();
      if (!mounted || fetchSeq != _latestFetchSeq) return;

      setState(() {
        _tickets = tickets;
        _isLoading = false;
        _errorMessage = null;
        _isHttpSyncDegraded = false;
      });
      _cancelRecoveryRetryTimer();
      _reconcileExpiryTracking(tickets);
      _syncCountdownTimer();

      if (tickets.isNotEmpty) {
        final first = tickets.first;
        final clinicId =
            first.clinicId ?? first.doctor.clinicId ?? ApiConfig.defaultClinicId;
        if (_realtimeService.activeClinicId != clinicId ||
            !_realtimeService.isConnected) {
          _realtimeService.connectForConsumer(_realtimeConsumer, clinicId);
        }
      }
    } on QueueException catch (e) {
      if (!mounted || fetchSeq != _latestFetchSeq) return;

      setState(() {
        if (e.statusCode == 401) {
          _tickets = [];
          _isHttpSyncDegraded = false;
          _isRealtimeDegraded = false;
          _clearExpiryTracking();
          _cancelRecoveryRetryTimer();
        } else if (_tickets.isNotEmpty) {
          _isHttpSyncDegraded = true;
          _scheduleRecoveryRetry();
        } else if (!isSilent) {
          _errorMessage = e.message;
        }
        _isLoading = false;
      });
      _syncCountdownTimer();
    } catch (e) {
      if (!mounted || fetchSeq != _latestFetchSeq) return;

      setState(() {
        if (_tickets.isNotEmpty) {
          _isHttpSyncDegraded = true;
          _scheduleRecoveryRetry();
        } else if (!isSilent) {
          _errorMessage = 'Kutilmagan xatolik yuz berdi: $e';
        }
        _isLoading = false;
      });
      _syncCountdownTimer();
    } finally {
      if (_activeSilentFetchSeq == fetchSeq) {
        _activeSilentFetchSeq = null;
      }
      if (mounted &&
          _queuedSilentRefresh &&
          _activeSilentFetchSeq == null &&
          _checkingInTicketId == null &&
          _cancellingTicketId == null) {
        _queuedSilentRefresh = false;
        unawaited(_fetchMyTickets(isSilent: _tickets.isNotEmpty));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // QR Check-in
  // ---------------------------------------------------------------------------

  Future<void> _startQrScan(MyQueueTicket ticket) async {
    final scanned = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => const QrScannerScreen(),
      ),
    );

    if (scanned == null || scanned.trim().isEmpty) return;
    await _submitQrToken(scanned.trim(), ticket: ticket);
  }

  Future<void> _submitQrToken(String token, {required MyQueueTicket ticket}) async {
    if (_checkingInTicketId != null) return;
    setState(() => _checkingInTicketId = ticket.id);

    try {
      await _queueService.checkInWithQr(token, ticketId: ticket.id);
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
        await _fetchMyTickets();
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
      if (mounted) setState(() => _checkingInTicketId = null);
    }
  }

  // ---------------------------------------------------------------------------
  // Cancellation
  // ---------------------------------------------------------------------------

  Future<void> _confirmAndCancelTicket(MyQueueTicket ticket) async {
    final l10n = context.l10n;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('cancel_confirm_dialog'),
        title: Text(l10n.cancelConfirmTitle),
        content: Text(
          '№${ticket.ticketNumber} (${ticket.specialization.name})\n${l10n.cancelConfirmMessage}',
        ),
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
    await _cancelTicket(ticket);
  }

  Future<void> _cancelTicket(MyQueueTicket ticket) async {
    if (_cancellingTicketId != null) return;
    setState(() => _cancellingTicketId = ticket.id);

    try {
      await _queueService.cancelTicket(
        queueId: ticket.queueId,
        ticketId: ticket.id,
      );
      if (mounted) {
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('cancel_success_snackbar'),
            content: Text(l10n.cancelSuccessSnackbar),
            backgroundColor: AppTheme.success,
          ),
        );
        await _fetchMyTickets();
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
      if (mounted) setState(() => _cancellingTicketId = null);
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
            onPressed: _isLoading ? null : _fetchMyTickets,
          ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final colors = context.dentalColors;

    if (_isLoading) {
      return const LoadingSkeleton(itemCount: 3);
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        key: const Key('my_queue_refresh_indicator_error'),
        onRefresh: _fetchMyTickets,
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
                onButtonPressed: _fetchMyTickets,
              ),
            ],
          ),
        ),
      );
    }

    if (_tickets.isEmpty) {
      return RefreshIndicator(
        key: const Key('my_queue_refresh_indicator_empty'),
        onRefresh: _fetchMyTickets,
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
              _buildFeatureOverviewCard(l10n, colors),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      key: const Key('my_queue_refresh_indicator_ticket'),
      onRefresh: _fetchMyTickets,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showSyncWarning) ...[
              _buildSyncWarningBanner(l10n, colors),
              const SizedBox(height: 14),
            ],
            for (int i = 0; i < _tickets.length; i++) ...[
              _buildSpecialistSection(_tickets[i], l10n, colors),
              if (i < _tickets.length - 1) const SizedBox(height: 24),
            ],
            const SizedBox(height: 20),
            _buildImportantNotesCard(l10n, colors),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('join_another_queue_button'),
              onPressed: () => _navigateToQueueFlow(context),
              icon: const Icon(Icons.add_circle_outline),
              label: Text(l10n.homeJoinQueueButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncWarningBanner(AppLocalizations l10n, DentalThemeTokens colors) {
    return Container(
      key: const Key('my_queue_connection_warning'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.warningSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: colors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.syncConnectionWarning,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            key: const Key('my_queue_connection_retry_button'),
            onPressed: () {
              _connectRealtime(forceReconnect: true);
              unawaited(_fetchMyTickets(isSilent: true, bypassCoalescing: true));
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.retryButton),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialistSection(
    MyQueueTicket ticket,
    AppLocalizations l10n,
    DentalThemeTokens colors,
  ) {
    return Column(
      key: Key('specialist_ticket_section_${ticket.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ticket.isQueuePaused && !ticket.isCalled) ...[
          Container(
            key: Key('paused_banner_${ticket.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.warningSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.warning.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(Icons.pause_circle_outline, color: colors.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.queuePausedBadge,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // CALLED: prominent banner
        if (ticket.isCalled) _buildCalledBanner(ticket, l10n, colors),

        // SERVING: in-progress banner
        if (ticket.isServing) _buildServingBanner(l10n, colors),

        // SKIPPED: skipped banner explaining reception must restore
        if (ticket.isSkipped) _buildSkippedBanner(l10n, colors),

        if (ticket.isCalled || ticket.isServing || ticket.isSkipped)
          const SizedBox(height: 14),

        _buildTicketCard(ticket, l10n, colors),
        const SizedBox(height: 14),

        // Check-in card (only when WAITING and not already checked in)
        if (ticket.isWaiting) ...[
          _buildCheckInCard(ticket, l10n, colors),
          const SizedBox(height: 14),
        ],

        // Cancel button — allowed for WAITING, CALLED, or SKIPPED
        if (ticket.isWaiting || ticket.isCalled || ticket.isSkipped)
          _buildCancelButton(ticket, l10n, colors),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CALLED Banner
  // ---------------------------------------------------------------------------

  Widget _buildCalledBanner(
    MyQueueTicket ticket,
    AppLocalizations l10n,
    DentalThemeTokens colors,
  ) {
    final remaining = _remainingCallSeconds(ticket);

    return Container(
      key: const Key('called_banner'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colors.warning.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.calledBannerTitle,
                  key: const Key('called_banner_title'),
                  style: const TextStyle(
                    fontSize: 19,
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
                if (remaining != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      key: const Key('called_countdown_badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              ticket.isQueuePaused
                                  ? '${l10n.remainingTimeLabel}: ${_formatCountdownMmSs(remaining)} (${l10n.pausedCountdownBadge})'
                                  : '${l10n.remainingTimeLabel}: ${_formatCountdownMmSs(remaining)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (remaining != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: CircularCountdown(
                remainingSeconds: remaining,
                isPaused: ticket.isQueuePaused,
                size: 56,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SERVING Banner
  // ---------------------------------------------------------------------------

  Widget _buildServingBanner(AppLocalizations l10n, DentalThemeTokens colors) {
    return Container(
      key: const Key('serving_banner'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colors.teal.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.medical_services_rounded, color: Colors.white, size: 34),
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
  // SKIPPED Banner
  // ---------------------------------------------------------------------------

  Widget _buildSkippedBanner(AppLocalizations l10n, DentalThemeTokens colors) {
    return Container(
      key: const Key('skipped_banner'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.errorSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.error, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.skippedBannerTitle,
                  key: const Key('skipped_banner_title'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.skippedBannerSubtitle,
                  key: const Key('skipped_banner_subtitle'),
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                    height: 1.35,
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

  Widget _buildTicketCard(
    MyQueueTicket ticket,
    AppLocalizations l10n,
    DentalThemeTokens colors,
  ) {
    final Color statusAccent = ticket.isCalled
        ? colors.warning
        : ticket.isServing
            ? colors.teal
            : ticket.isSkipped
                ? colors.error
                : colors.blue;

    return TicketPassCard(
      accentColor: statusAccent,
      topSection: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Specialty & Status header bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.confirmation_number_outlined,
                        color: statusAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l10n.ticketNumberLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  status: ticket.status,
                  label: ticket.localizedStatus(l10n),
                  textKey: const Key('my_ticket_status_badge'),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Bold Boarding-Pass Stub: Massive Ticket Number + Doctor Monogram & People Ahead
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: statusAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: statusAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '№${ticket.ticketNumber}',
                    key: const Key('my_ticket_number_text'),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: statusAccent,
                      letterSpacing: -1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.doctor.fullName,
                        key: const Key('my_ticket_doctor_name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ticket.specialization.name,
                        key: const Key('my_ticket_specialization_name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.teal,
                        ),
                      ),
                      if (!ticket.isSkipped) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.blueSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline, color: colors.blue, size: 15),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  l10n.peopleAhead(ticket.peopleAhead),
                                  key: const Key('my_ticket_people_ahead_text'),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomSection: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (ticket.doctor.roomNumber != null &&
                ticket.doctor.roomNumber!.isNotEmpty)
              _buildMetaPill(
                colors: colors,
                icon: Icons.meeting_room_outlined,
                label: l10n.roomLabel,
                value: l10n.roomWithNumber(ticket.doctor.roomNumber!),
                valueKey: const Key('my_ticket_room_number'),
              ),
            if (ticket.queuePosition != null)
              _buildMetaPill(
                colors: colors,
                icon: Icons.format_list_numbered_rounded,
                label: l10n.queuePositionLabel,
                value: '#${ticket.queuePosition}',
              ),
            _buildMetaPill(
              colors: colors,
              icon: Icons.access_time_rounded,
              label: l10n.ticketTimeLabel,
              value: _formatDateTime(ticket.createdAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaPill({
    required DentalThemeTokens colors,
    required IconData icon,
    required String label,
    required String value,
    Key? valueKey,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.teal),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              Text(
                value,
                key: valueKey,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Check-in Card
  // ---------------------------------------------------------------------------

  Widget _buildCheckInCard(
    MyQueueTicket ticket,
    AppLocalizations l10n,
    DentalThemeTokens colors,
  ) {
    final isCheckedIn = ticket.isCheckedIn;

    return Container(
      key: const Key('checkin_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCheckedIn ? colors.success.withValues(alpha: 0.45) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCheckedIn ? colors.successSoft : colors.warningSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCheckedIn ? Icons.check_circle_rounded : Icons.qr_code_2_rounded,
                  color: isCheckedIn ? colors.success : colors.warning,
                  size: 22,
                ),
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
                        color: isCheckedIn ? colors.success : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCheckedIn
                          ? l10n.checkedInStatusDesc
                          : l10n.notCheckedInStatusDesc,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                        height: 1.35,
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
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _checkingInTicketId == ticket.id
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        key: const Key('qr_checkin_button'),
                        onPressed: _checkingInTicketId == null
                            ? () => _startQrScan(ticket)
                            : null,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: Text(l10n.checkInButtonText),
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

  Widget _buildCancelButton(
    MyQueueTicket ticket,
    AppLocalizations l10n,
    DentalThemeTokens colors,
  ) {
    if (_cancellingTicketId == ticket.id) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const Key('cancel_ticket_button'),
      onPressed: _cancellingTicketId == null
          ? () => _confirmAndCancelTicket(ticket)
          : null,
      icon: Icon(Icons.cancel_outlined, color: colors.error),
      label: Text(l10n.cancelTicketButton),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.error,
        side: BorderSide(color: colors.error.withValues(alpha: 0.7)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildImportantNotesCard(AppLocalizations l10n, DentalThemeTokens colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined, size: 18, color: colors.blue),
              const SizedBox(width: 8),
              Text(
                l10n.myQueueReminderTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.myQueueReminderDesc,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureOverviewCard(AppLocalizations l10n, DentalThemeTokens colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.featuresTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFeatureBullet(l10n.featureTicketAndSpec, colors),
          _buildFeatureBullet(l10n.featureLiveQueue, colors),
          _buildFeatureBullet(l10n.featureCheckIn, colors),
          _buildFeatureBullet(l10n.featurePushNotifications, colors),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(String text, DentalThemeTokens colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle_outline, size: 15, color: colors.teal),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.35,
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
