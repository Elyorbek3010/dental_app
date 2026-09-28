import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_controller.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'patient_shell.dart';

/// The root routing widget that inspects session state:
/// - Uninitialized: displays clean splash / loading indicator while verifying stored tokens.
/// - Authenticated (Patient): displays [PatientShell].
/// - Unauthenticated: displays [LoginScreen].
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authController,
    this.reminderService,
  });

  final AuthController authController;
  final ReminderService? reminderService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    if (!widget.authController.isInitialized) {
      widget.authController.checkAuthSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.authController,
      builder: (context, _) {
        if (!widget.authController.isInitialized) {
          return const _AuthLoadingSplashScreen();
        }

        if (widget.authController.isAuthenticated) {
          return PatientShell(
            authController: widget.authController,
            reminderService: widget.reminderService,
          );
        }

        return LoginScreen(
          authController: widget.authController,
        );
      },
    );
  }
}

class _AuthLoadingSplashScreen extends StatelessWidget {
  const _AuthLoadingSplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medical_services_outlined,
                size: 54,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Dental Queue',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)?.checkingSession ??
                  'Xavfsiz sessiya tekshirilmoqda...',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
