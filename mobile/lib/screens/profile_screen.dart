import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/user.dart';
import '../services/auth_controller.dart';
import '../services/locale_controller.dart';
import '../theme/app_theme.dart';

/// Patient Profile Screen.
///
/// Displays real authenticated patient information from the backend `/api/auth/me`,
/// provides language switching across Uzbek, Russian, and English,
/// and allows the patient to log out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.authController,
    this.localeController,
  });

  final AuthController? authController;
  final LocaleController? localeController;

  Future<void> _handleLogout(
    BuildContext context,
    AuthController? controller,
    AppLocalizations l10n,
  ) async {
    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.authNextStep),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.logoutDialogTitle),
          content: Text(l10n.logoutDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancelButton),
            ),
            TextButton(
              key: const Key('profile_confirm_logout_button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: Text(l10n.logoutButton),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = authController;

    if (controller != null) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _buildContent(context, controller),
      );
    }

    return _buildContent(context, null);
  }

  Widget _buildContent(BuildContext context, AuthController? controller) {
    final PatientUser? user = controller?.currentUser;
    final l10n = context.l10n;
    final activeLocaleCtrl = localeController ?? LocaleController.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          children: [
            // User Avatar & Name Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppTheme.primaryLight,
                    child: Text(
                      user != null && user.fullName.isNotEmpty
                          ? user.fullName[0].toUpperCase()
                          : 'B',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    user != null && user.fullName.isNotEmpty
                        ? user.fullName
                        : l10n.patientDefaultName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (user?.isActive ?? false)
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Text(
                      user != null
                          ? (user.isActive
                              ? l10n.activeAccountBadge
                              : l10n.inactiveAccountBadge)
                          : l10n.accountNotLoadedBadge,
                      style: TextStyle(
                        fontSize: 12,
                        color: (user?.isActive ?? false)
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Language Selector Card (UZ / RU / EN)
            Container(
              width: double.infinity,
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
                      const Icon(
                        Icons.language_outlined,
                        size: 20,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.languageSectionTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: activeLocaleCtrl,
                    builder: (context, _) {
                      final currentCode = activeLocaleCtrl.languageCode;
                      return Row(
                        children: [
                          _buildLanguageChoice(
                            key: const Key('language_option_uz'),
                            label: l10n.languageUzbek,
                            isSelected: currentCode == 'uz',
                            onSelect: () => activeLocaleCtrl.setLanguageCode('uz'),
                          ),
                          const SizedBox(width: 8),
                          _buildLanguageChoice(
                            key: const Key('language_option_ru'),
                            label: l10n.languageRussian,
                            isSelected: currentCode == 'ru',
                            onSelect: () => activeLocaleCtrl.setLanguageCode('ru'),
                          ),
                          const SizedBox(width: 8),
                          _buildLanguageChoice(
                            key: const Key('language_option_en'),
                            label: l10n.languageEnglish,
                            isSelected: currentCode == 'en',
                            onSelect: () => activeLocaleCtrl.setLanguageCode('en'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Account Information Details
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  _buildProfileTile(
                    icon: Icons.phone_outlined,
                    title: l10n.phoneProfileLabel,
                    value: user?.phone ?? l10n.notAssigned,
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  _buildProfileTile(
                    icon: Icons.badge_outlined,
                    title: l10n.userRoleProfileLabel,
                    value: user != null
                        ? l10n.patientRoleValue(user.role)
                        : l10n.patientRoleFallback,
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  _buildProfileTile(
                    icon: Icons.notifications_none_outlined,
                    title: l10n.pushNotificationsProfileLabel,
                    value: l10n.pushNotificationsActiveValue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // App & System Information
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  _buildProfileTile(
                    icon: Icons.local_hospital_outlined,
                    title: l10n.systemProfileLabel,
                    value: 'Dental Clinic Queue V1',
                  ),
                  const Divider(height: 1, color: AppTheme.cardBorder),
                  _buildProfileTile(
                    icon: Icons.info_outline,
                    title: l10n.appVersionProfileLabel,
                    value: '1.0.0',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('profile_logout_button'),
                onPressed: () => _handleLogout(context, controller, l10n),
                icon: const Icon(Icons.logout, color: AppTheme.error, size: 20),
                label: Text(
                  l10n.logoutButton,
                  style: const TextStyle(color: AppTheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageChoice({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return Expanded(
      child: InkWell(
        key: key,
        onTap: onSelect,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
