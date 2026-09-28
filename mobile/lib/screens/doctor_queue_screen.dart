import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/doctor.dart';
import '../models/doctor_queue.dart';
import '../models/specialization.dart';
import '../services/catalog_service.dart';
import '../services/queue_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/empty_state_card.dart';
import 'patient_shell.dart';

/// Screen displaying today's queue information for the selected doctor
/// and allowing the authenticated patient to join the queue.
class DoctorQueueScreen extends StatefulWidget {
  const DoctorQueueScreen({
    super.key,
    required this.doctor,
    required this.specialization,
    this.catalogService,
    this.queueService,
  });

  final Doctor doctor;
  final Specialization specialization;
  final CatalogService? catalogService;
  final QueueService? queueService;

  @override
  State<DoctorQueueScreen> createState() => _DoctorQueueScreenState();
}

class _DoctorQueueScreenState extends State<DoctorQueueScreen> {
  late final CatalogService _catalogService;
  late final QueueService _queueService;

  DoctorQueue? _queue;
  bool _isLoading = true;
  bool _isJoining = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? CatalogService.instance;
    _queueService = widget.queueService ?? QueueService.instance;
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final queue = await _catalogService.fetchDoctorQueue(widget.doctor.id);
      if (mounted) {
        setState(() {
          _queue = queue;
          _isLoading = false;
        });
      }
    } on CatalogException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

    return SingleChildScrollView(
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
          const SizedBox(height: 24),

          // Queue Availability Section
          if (queue == null) ...[
            EmptyStateCard(
              icon: Icons.event_busy_outlined,
              title: l10n.noQueueTodayTitle,
              description: l10n.noQueueTodayDesc(widget.doctor.fullName),
            ),
          ] else ...[
            // Real Active Queue Details Card
            Container(
              padding: const EdgeInsets.all(18),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        child: Text(
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildQueueDetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: l10n.queueDateLabel,
                    value: queue.queueDate,
                  ),
                  const Divider(height: 20, color: AppTheme.cardBorder),
                  _buildQueueDetailRow(
                    icon: Icons.access_time_outlined,
                    label: l10n.admissionStatusLabel,
                    value: queue.isPaused
                        ? l10n.admissionStatusPaused
                        : l10n.admissionStatusServing,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Real Join Queue Action Button with loading and double-tap prevention
            ElevatedButton.icon(
              key: const Key('doctor_queue_join_button'),
              onPressed: _isJoining ? null : () => _handleJoinQueue(l10n),
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
              label: Text(_isJoining ? l10n.loadingText : l10n.joinQueueButton),
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
    );
  }

  Widget _buildQueueDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
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
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
