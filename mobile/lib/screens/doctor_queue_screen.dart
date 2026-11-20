import 'dart:async';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/doctor.dart';
import '../models/doctor_queue.dart';
import '../models/specialization.dart';
import '../services/catalog_service.dart';
import '../services/queue_realtime_service.dart';
import '../services/queue_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/dental_surfaces.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/status_chip.dart';
import 'patient_shell.dart';

/// Screen displaying today's queue information for the selected doctor
/// with live real-time WebSocket updates and allowing the authenticated patient to join.
class DoctorQueueScreen extends StatefulWidget {
  const DoctorQueueScreen({
    super.key,
    required this.doctor,
    required this.specialization,
    this.catalogService,
    this.queueService,
    this.realtimeService,
  });

  final Doctor doctor;
  final Specialization specialization;
  final CatalogService? catalogService;
  final QueueService? queueService;
  final QueueRealtimeService? realtimeService;

  @override
  State<DoctorQueueScreen> createState() => _DoctorQueueScreenState();
}

class _DoctorQueueScreenState extends State<DoctorQueueScreen> {
  late final CatalogService _catalogService;
  late final QueueService _queueService;
  late final QueueRealtimeService _realtimeService;
  final Object _realtimeConsumer = Object();

  StreamSubscription<QueueUpdatedEvent>? _realtimeSubscription;
  DoctorQueue? _queue;
  bool _isLoading = true;
  bool _isJoining = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? CatalogService.instance;
    _queueService = widget.queueService ?? QueueService.instance;
    _realtimeService = widget.realtimeService ?? QueueRealtimeService.instance;
    _loadQueue();
    _initRealtime();
  }

  void _initRealtime() {
    try {
      _realtimeService.connectForConsumer(
        _realtimeConsumer,
        widget.doctor.clinicId,
      );
      _realtimeSubscription = _realtimeService.events.listen(
        (event) {
          if (!mounted) return;
          // Trigger refetch if event matches current queue, current queue was null, or clinic-wide
          if (event.queueId == null ||
              _queue == null ||
              event.queueId == _queue!.id) {
            _loadQueue(isSilent: true);
          }
        },
        onError: (Object error) {
          debugPrint('[DoctorQueueScreen] Realtime error (ignored): $error');
        },
      );
    } catch (e) {
      debugPrint('[DoctorQueueScreen] Could not initialize realtime: $e');
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _realtimeService.disconnectConsumer(_realtimeConsumer);
    super.dispose();
  }

  Future<void> _loadQueue({bool isSilent = false}) async {
    if (!isSilent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final queue = await _catalogService.fetchDoctorQueue(widget.doctor.id);
      if (mounted) {
        setState(() {
          _queue = queue;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } on CatalogException catch (e) {
      if (mounted && !isSilent) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !isSilent) {
        setState(() {
          _errorMessage = 'Kutilmagan xatolik yuz berdi: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleJoinQueue(AppLocalizations l10n) async {
    final queue = _queue;
    if (_isJoining || queue == null) return;

    if (queue.isPaused) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.queuePausedSnackbar),
          backgroundColor: context.dentalColors.warning,
        ),
      );
      return;
    }

    if (!queue.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.queueInactiveSnackbar),
          backgroundColor: context.dentalColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isJoining = true;
    });

    try {
      final ticket = await _queueService.joinQueue(queue.id);
      if (!mounted) return;

      setState(() {
        _isJoining = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.ticketJoinedSuccess(ticket.ticketNumber)),
          backgroundColor: context.dentalColors.success,
        ),
      );

      // Navigate to patient's real ticket in PatientShell (My Queue tab - index 1)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => PatientShell(
            initialIndex: 1,
            queueService: _queueService,
            realtimeService: widget.realtimeService,
          ),
        ),
        (route) => false,
      );
    } on QueueConflictException catch (e) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
      });
      _showConflictDialog(e, l10n);
    } on QueueException catch (e) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizeError(e.message, l10n)),
          backgroundColor: AppTheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizeError(e.toString(), l10n)),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _showConflictDialog(QueueConflictException e, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                e.isAlreadyActive ? Icons.info_outline : Icons.warning_amber_rounded,
                color: e.isAlreadyActive ? AppTheme.primary : AppTheme.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.isAlreadyActive
                      ? l10n.conflictActiveTicketTitle
                      : l10n.conflictCannotJoinTitle,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Text(localizeError(e.message, l10n)),
          actions: [
            if (e.isAlreadyActive)
              TextButton(
                key: const Key('conflict_dialog_go_to_ticket'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => PatientShell(
                        initialIndex: 1,
                        queueService: _queueService,
                      ),
                    ),
                    (route) => false,
                  );
                },
                child: Text(l10n.goToMyTicketButton),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.closeButton),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dentalColors;
    final queue = _queue;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.doctorQueueTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(l10n),
      bottomNavigationBar: (!_isLoading &&
              _errorMessage == null &&
              queue != null &&
              queue.isActive)
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: ElevatedButton.icon(
                  key: const Key('doctor_queue_join_button'),
                  onPressed: (_isJoining || queue.isPaused)
                      ? null
                      : () => _handleJoinQueue(l10n),
                  icon: _isJoining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_circle_outline, size: 20),
                  label: Text(
                    _isJoining
                        ? l10n.loadingText
                        : (queue.isPaused
                            ? l10n.queueTemporarilyPaused
                            : l10n.joinQueueButton),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final colors = context.dentalColors;

    if (_isLoading) {
      return const LoadingSkeleton(itemCount: 3);
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: EmptyStateCard(
            icon: Icons.error_outline,
            title: l10n.errorOccurred,
            description: localizeError(_errorMessage, l10n),
            buttonText: l10n.retryButton,
            onButtonPressed: _loadQueue,
          ),
        ),
      );
    }

    final queue = _queue;

    return RefreshIndicator(
      onRefresh: _loadQueue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Editorial Doctor Profile Strip
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  DoctorMonogramBadge(
                    fullName: widget.doctor.fullName,
                    size: 56,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.doctor.fullName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.tealSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                widget.specialization.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colors.teal,
                                ),
                              ),
                            ),
                            if (widget.doctor.roomNumber != null &&
                                widget.doctor.roomNumber!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: colors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.meeting_room_outlined,
                                      size: 14,
                                      color: colors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.roomNumberDoctorFormat(widget.doctor.roomNumber!),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            if (queue == null) ...[
              EmptyStateCard(
                icon: Icons.event_busy_outlined,
                title: l10n.noQueueTodayTitle,
                description: l10n.noQueueTodayDesc(widget.doctor.fullName),
              ),
            ] else if (!queue.isActive) ...[
              EmptyStateCard(
                icon: Icons.block_outlined,
                title: l10n.queueUnavailableState,
                description: l10n.queueInactiveSnackbar,
              ),
            ] else ...[
              // Perforated Ticket-Pass Pre-Join Telemetry Board
              TicketPassCard(
                accentColor: queue.isPaused ? colors.warning : colors.teal,
                topSection: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.todayQueueHeader,
                                  style: TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  queue.queueDate,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusChip(
                            status: queue.isPaused ? 'PAUSED' : 'SERVING',
                            isPaused: queue.isPaused,
                            label: queue.isPaused
                                ? l10n.queueStatusPaused
                                : l10n.queueStatusActive,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              colors: colors,
                              label: l10n.currentlyServingLabel,
                              value: '${queue.servingCount}',
                              valueKey: const Key('prejoin_serving_count'),
                              color: colors.teal,
                              icon: Icons.medical_services_outlined,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricTile(
                              colors: colors,
                              label: l10n.waitingCountLabel,
                              value: '${queue.waitingCount}',
                              valueKey: const Key('prejoin_waiting_count'),
                              color: colors.blue,
                              icon: Icons.schedule_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricTile(
                              colors: colors,
                              label: l10n.calledCountLabel,
                              value: '${queue.calledCount}',
                              valueKey: const Key('prejoin_called_count'),
                              color: colors.warning,
                              icon: Icons.notifications_active_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                bottomSection: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.ifYouJoinNowLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l10n.estimatedPositionLabel,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l10n.peopleAhead(
                                queue.waitingCount +
                                    queue.calledCount +
                                    queue.servingCount,
                              ),
                              key: const Key('prejoin_people_ahead_text'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: colors.tealSoft,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colors.teal.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          l10n.estimatedPositionValue(
                            queue.estimatedPositionIfJoined,
                          ),
                          key: const Key('prejoin_estimated_position'),
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: colors.teal,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required DentalThemeTokens colors,
    required String label,
    required String value,
    required Key valueKey,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            key: valueKey,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
