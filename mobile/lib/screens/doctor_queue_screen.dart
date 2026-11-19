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
import '../widgets/empty_state_card.dart';
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
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    if (!queue.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.queueInactiveSnackbar),
          backgroundColor: AppTheme.warning,
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
          backgroundColor: AppTheme.success,
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
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Doctor & Specialization Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.primaryLight,
                    child: const Icon(
                      Icons.person,
                      size: 36,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.doctor.fullName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.specialization.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        if (widget.doctor.roomNumber != null &&
                            widget.doctor.roomNumber!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.meeting_room_outlined,
                                size: 15,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.roomNumberDoctorFormat(widget.doctor.roomNumber!),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Queue Availability & Overview Section
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
              // Material 3 Pre-Join Queue Overview Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status Badge Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.todayQueueHeader,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: queue.isPaused
                                ? AppTheme.warning.withValues(alpha: 0.15)
                                : AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: queue.isPaused
                                    ? AppTheme.warning
                                    : AppTheme.success,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                queue.isPaused
                                    ? l10n.queueStatusPaused
                                    : l10n.queueStatusActive,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: queue.isPaused
                                      ? AppTheme.warning
                                      : AppTheme.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      queue.queueDate,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Live 3-column metrics
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            label: l10n.currentlyServingLabel,
                            value: '${queue.servingCount}',
                            valueKey: const Key('prejoin_serving_count'),
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            label: l10n.waitingCountLabel,
                            value: '${queue.waitingCount}',
                            valueKey: const Key('prejoin_waiting_count'),
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricTile(
                            label: l10n.calledCountLabel,
                            value: '${queue.calledCount}',
                            valueKey: const Key('prejoin_called_count'),
                            color: AppTheme.warning,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(height: 1, color: AppTheme.cardBorder),
                    const SizedBox(height: 16),

                    // "If you join now" Estimated Position Box
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.ifYouJoinNowLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.estimatedPositionLabel,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              l10n.estimatedPositionValue(
                                queue.estimatedPositionIfJoined,
                              ),
                              key: const Key('prejoin_estimated_position'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Join Queue Button
              ElevatedButton.icon(
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
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
    required String label,
    required String value,
    required Key valueKey,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            value,
            key: valueKey,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
