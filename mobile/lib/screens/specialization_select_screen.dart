import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/specialization.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/empty_state_card.dart';
import 'doctor_select_screen.dart';

/// Screen displaying clinic specializations for the patient to choose from.
class SpecializationSelectScreen extends StatefulWidget {
  const SpecializationSelectScreen({
    super.key,
    this.catalogService,
    this.clinicId = 1,
  });

  final CatalogService? catalogService;
  final int clinicId;

  @override
  State<SpecializationSelectScreen> createState() =>
      _SpecializationSelectScreenState();
}

class _SpecializationSelectScreenState extends State<SpecializationSelectScreen> {
  late final CatalogService _catalogService;

  List<Specialization> _specializations = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? CatalogService.instance;
    _loadSpecializations();
  }

  Future<void> _loadSpecializations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _catalogService.fetchSpecializations(
        clinicId: widget.clinicId,
      );
      if (mounted) {
        setState(() {
          _specializations = items;
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

  void _onSpecializationSelected(Specialization specialization) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DoctorSelectScreen(
          specialization: specialization,
          catalogService: _catalogService,
          clinicId: widget.clinicId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.selectSpecializationTitle),
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
                key: const Key('specialization_retry_button'),
                onPressed: _loadSpecializations,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.retryButton),
              ),
            ],
          ),
        ),
      );
    }

    if (_specializations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: EmptyStateCard(
            icon: Icons.medical_services_outlined,
            title: l10n.noSpecializationsTitle,
            description: l10n.noSpecializationsDesc,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSpecializations,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _specializations.length,
        itemBuilder: (context, index) {
          final item = _specializations[index];
          return Card(
            key: Key('specialization_item_${item.id}'),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              title: Text(
                item.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppTheme.textMuted,
              ),
              onTap: () => _onSpecializationSelected(item),
            ),
          );
        },
      ),
    );
  }
}
