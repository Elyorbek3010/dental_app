import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/user.dart';
import '../services/auth_controller.dart';
import '../services/locale_controller.dart';
import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/dental_surfaces.dart';

/// Patient Profile Screen.
///
/// Displays real authenticated patient information from the backend `/api/auth/me`,
/// provides Light/Dark/System theme switching and Uzbek/Russian/English language switching,
/// and allows the patient to log out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.authController,
    this.localeController,
    this.themeController,
  });

  final AuthController? authController;
  final LocaleController? localeController;
  final ThemeController? themeController;

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
              style: TextButton.styleFrom(foregroundColor: context.dentalColors.error),
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
    final colors = context.dentalColors;
    final activeLocaleCtrl = localeController ?? LocaleController.instance;
    final activeThemeCtrl = themeController ?? ThemeController.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Architectural Identity Header Card
            DentalWaveBackdrop(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: colors.tealSoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colors.teal.withValues(alpha: 0.35),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        user != null && user.fullName.isNotEmpty
                            ? user.fullName[0].toUpperCase()
                            : 'B',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: colors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user != null && user.fullName.isNotEmpty
                                ? user.fullName
                                : l10n.patientDefaultName,
                            style: TextStyle(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.clinicPortalBadge,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.teal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: (user?.isActive ?? false)
                                  ? colors.successSoft
                                  : colors.surfaceMuted,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: (user?.isActive ?? false)
                                    ? colors.success.withValues(alpha: 0.35)
                                    : colors.border,
                              ),
                            ),
                            child: Text(
                              user != null
                                  ? (user.isActive
                                      ? l10n.activeAccountBadge
                                      : l10n.inactiveAccountBadge)
                                  : l10n.accountNotLoadedBadge,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: (user?.isActive ?? false)
                                    ? colors.success
                                    : colors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Grouped Preferences Card: Theme (Light/Dark/System) + Language (UZ/RU/EN)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 20,
                        color: colors.teal,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.themeSectionTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: activeThemeCtrl,
                    builder: (context, _) {
                      final freshColors = context.dentalColors;
                      final mode = activeThemeCtrl.themeMode;
                      return Row(
                        children: [
                          _buildSegmentedChoice(
                            colors: freshColors,
                            key: const Key('theme_option_light'),
                            icon: Icons.light_mode_outlined,
                            label: l10n.themeLight,
                            isSelected: mode == ThemeMode.light,
                            onSelect: () => activeThemeCtrl.setThemeMode(ThemeMode.light),
                          ),
                          const SizedBox(width: 8),
                          _buildSegmentedChoice(
                            colors: freshColors,
                            key: const Key('theme_option_dark'),
                            icon: Icons.dark_mode_outlined,
                            label: l10n.themeDark,
                            isSelected: mode == ThemeMode.dark,
                            onSelect: () => activeThemeCtrl.setThemeMode(ThemeMode.dark),
                          ),
                          const SizedBox(width: 8),
                          _buildSegmentedChoice(
                            colors: freshColors,
                            key: const Key('theme_option_system'),
                            icon: Icons.settings_brightness_outlined,
                            label: l10n.themeSystem,
                            isSelected: mode == ThemeMode.system,
                            onSelect: () => activeThemeCtrl.setThemeMode(ThemeMode.system),
                          ),
                        ],
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1, color: colors.border),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.language_outlined,
                        size: 20,
                        color: colors.blue,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.languageSectionTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: activeLocaleCtrl,
                    builder: (context, _) {
                      final freshColors = context.dentalColors;
                      final currentCode = activeLocaleCtrl.languageCode;
                      return Row(
                        children: [
                          _buildSegmentedChoice(
                            colors: freshColors,
                            key: const Key('language_option_uz'),
                            label: l10n.languageUzbek,
                            isSelected: currentCode == 'uz',
                            onSelect: () => activeLocaleCtrl.setLanguageCode('uz'),
                          ),
                          const SizedBox(width: 8),
                          _buildSegmentedChoice(
                            colors: freshColors,
                            key: const Key('language_option_ru'),
                            label: l10n.languageRussian,
                            isSelected: currentCode == 'ru',
                            onSelect: () => activeLocaleCtrl.setLanguageCode('ru'),
                          ),
                          const SizedBox(width: 8),
                          _buildSegmentedChoice(
                            colors: freshColors,
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
            const SizedBox(height: 16),

            // Unified Account & System Details Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  _buildProfileTile(
                    colors: colors,
                    icon: Icons.phone_outlined,
                    title: l10n.phoneProfileLabel,
                    value: user?.phone ?? l10n.notAssigned,
                  ),
                  Divider(height: 1, color: colors.border),
                  _buildProfileTile(
                    colors: colors,
                    icon: Icons.badge_outlined,
                    title: l10n.userRoleProfileLabel,
                    value: user != null
                        ? l10n.patientRoleValue(user.role)
                        : l10n.patientRoleFallback,
                  ),
                  Divider(height: 1, color: colors.border),
                  _buildProfileTile(
                    colors: colors,
                    icon: Icons.notifications_none_outlined,
                    title: l10n.pushNotificationsProfileLabel,
                    value: l10n.pushNotificationsActiveValue,
                  ),
                  Divider(height: 1, color: colors.border),
                  _buildProfileTile(
                    colors: colors,
                    icon: Icons.local_hospital_outlined,
                    title: l10n.systemProfileLabel,
                    value: 'Dental Clinic Queue V1',
                  ),
                  Divider(height: 1, color: colors.border),
                  _buildProfileTile(
                    colors: colors,
                    icon: Icons.info_outline,
                    title: l10n.appVersionProfileLabel,
                    value: '1.0.0',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('profile_logout_button'),
                onPressed: () => _handleLogout(context, controller, l10n),
                icon: Icon(Icons.logout_rounded, color: colors.error, size: 20),
                label: Text(
                  l10n.logoutButton,
                  style: TextStyle(color: colors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.error.withValues(alpha: 0.7)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedChoice({
    required DentalThemeTokens colors,
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onSelect,
    IconData? icon,
  }) {
    return Expanded(
      child: InkWell(
        key: key,
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? colors.teal : colors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? colors.teal : colors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? Colors.white : colors.textSecondary,
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTile({
    required DentalThemeTokens colors,
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: colors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
