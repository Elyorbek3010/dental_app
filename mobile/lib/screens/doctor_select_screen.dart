import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/doctor.dart';
import '../models/specialization.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/dental_surfaces.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/loading_skeleton.dart';
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
    final colors = context.dentalColors;

    if (_isLoading) {
      return const LoadingSkeleton(itemCount: 4);
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 54,
                color: colors.error,
              ),
              const SizedBox(height: 16),
              Text(
                localizeError(_errorMessage, l10n),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
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
        itemCount: _doctors.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return DentalWaveBackdrop(
              child: Container(
                margin: const EdgeInsets.only(bottom: 0),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.tealSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.medical_services_rounded,
                        size: 20,
                        color: colors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.specializationHeaderPrefix(widget.specialization.name),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        '${_doctors.length}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: colors.teal,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final doctor = _doctors[index - 1];
          return Padding(
            padding: EdgeInsets.only(top: index == 1 ? 16 : 12),
            child: Material(
              key: Key('doctor_item_${doctor.id}'),
              color: colors.surface,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                onTap: () => _onDoctorSelected(doctor),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          DoctorMonogramBadge(
                            fullName: doctor.fullName,
                            size: 54,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doctor.fullName,
                                  style: TextStyle(
                                    fontSize: 16.5,
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
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.tealSoft,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        widget.specialization.name,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: colors.teal,
                                        ),
                                      ),
                                    ),
                                    if (doctor.roomNumber != null &&
                                        doctor.roomNumber!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
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
                                              size: 13,
                                              color: colors.textSecondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              l10n.roomNumberDoctorFormat(doctor.roomNumber!),
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: colors.textSecondary,
                                                fontWeight: FontWeight.w600,
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
                      const SizedBox(height: 14),
                      Divider(height: 1, color: colors.border),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.viewLiveQueueLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.teal,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colors.tealSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
