import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/specialization.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_localizer.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/loading_skeleton.dart';
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
  String _searchQuery = '';
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

  IconData _specialtyIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('ortod') || lower.contains('braces')) {
      return Icons.grid_view_rounded;
    }
    if (lower.contains('endo') || lower.contains('kanal')) {
      return Icons.healing_rounded;
    }
    if (lower.contains('xirurg') || lower.contains('surg') || lower.contains('implant')) {
      return Icons.precision_manufacturing_outlined;
    }
    if (lower.contains('bolalar') || lower.contains('ped') || lower.contains('child')) {
      return Icons.child_care_rounded;
    }
    if (lower.contains('gigiy') || lower.contains('hyg') || lower.contains('clean')) {
      return Icons.auto_awesome_outlined;
    }
    return Icons.medical_services_rounded;
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

    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _specializations
        : _specializations
            .where((s) => s.name.toLowerCase().contains(query))
            .toList();

    return RefreshIndicator(
      onRefresh: _loadSpecializations,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.chooseCareSubtitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: l10n.searchSpecialtiesHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: EmptyStateCard(
                  icon: Icons.search_off_rounded,
                  title: l10n.noSpecializationsTitle,
                  description: l10n.noSpecializationsDesc,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.08,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = filtered[index];
                    final isEven = index.isEven;
                    final fg = isEven ? colors.teal : colors.blue;
                    final bg = isEven ? colors.tealSoft : colors.blueSoft;

                    return Material(
                      key: Key('specialization_item_${item.id}'),
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: () => _onSpecializationSelected(item),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: colors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _specialtyIcon(item.name),
                                  color: fg,
                                  size: 24,
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceMuted,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 14,
                                          color: fg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
