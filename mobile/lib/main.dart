import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/api_config.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth_gate.dart';
import 'services/auth_controller.dart';
import 'services/local_notification_service.dart';
import 'services/locale_controller.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize server push notifications (FCM) with central ApiConfig
  await PushNotificationService.instance.initialize(
    customBaseUrl: ApiConfig.baseUrl,
  );

  // Initialize local notifications (personal reminders)
  await LocalNotificationService.instance.initialize();

  // Initialize locale preferences
  await LocaleController.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.home,
    this.authController,
    this.localeController,
  });

  /// Optional custom home widget for widget testing.
  final Widget? home;
  final AuthController? authController;
  final LocaleController? localeController;

  @override
  Widget build(BuildContext context) {
    final controller = localeController ?? LocaleController.instance;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Dental Queue',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: controller.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home ??
              AuthGate(
                authController: authController ?? AuthController(),
              ),
        );
      },
    );
  }
}
