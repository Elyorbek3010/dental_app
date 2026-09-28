import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/doctor.dart';
import '../models/specialization.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/empty_state_card.dart';
import 'doctor_queue_screen.dart';

/// Screen displaying doctors belonging to the selected specialization.
class DoctorSelectScreen extends StatefulWidget {
  const DoctorSelectScreen({
    super.key,
    required this.specialization,
    this.catalogService,
    this.clinicId = 1,
  });

  final Specialization specialization;
  final CatalogService? catalogService;
  final int clinicId;

  @override
  State<DoctorSelectScreen> createState() => _DoctorSelectScreenState();
}

class _DoctorSelectScreenState extends State<DoctorSelectScreen> {
  late final CatalogService _catalogService;

  List<Doctor> _doctors = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? CatalogService.instance;
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _catalogService.fetchDoctors(
        specializationId: widget.specialization.id,
        clinicId: widget.clinicId,
      );
      if (mounted) {
        setState(() {
          _doctors = items;
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

  void _onDoctorSelected(Doctor doctor) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DoctorQueueScreen(
          doctor: doctor,
          specialization: widget.specialization,
          catalogService: _catalogService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.selectDoctorTitle),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 54,
                color: AppTheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                localizeError(_errorMessage, l10n),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                key: const Key('doctor_retry_button'),
                onPressed: _loadDoctors,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.retryButton),
              ),
            ],
          ),
        ),
      );
    }

    if (_doctors.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: EmptyStateCard(
            icon: Icons.person_off_outlined,
            title: l10n.noDoctorsTitle,
            description: l10n.noDoctorsDesc(widget.specialization.name),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDoctors,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _doctors.length + 1, // Header + list
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.medical_services_outlined,
                    size: 18,
                    color: AppTheme.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.specializationHeaderPrefix(widget.specialization.name),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final doctor = _doctors[index - 1];
          return Card(
            key: Key('doctor_item_${doctor.id}'),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primaryLight,
                child: const Icon(
                  Icons.person,
                  color: AppTheme.primary,
                  size: 26,
                ),
              ),
              title: Text(
                doctor.fullName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    widget.specialization.name,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (doctor.roomNumber != null && doctor.roomNumber!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.meeting_room_outlined,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.roomNumberDoctorFormat(doctor.roomNumber!),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppTheme.textMuted,
              ),
              onTap: () => _onDoctorSelected(doctor),
            ),
          );
        },
      ),
    );
  }
}
