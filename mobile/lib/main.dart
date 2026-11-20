import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/api_config.dart';
import 'l10n/app_localizations.dart';
import 'screens/auth_gate.dart';
import 'services/auth_controller.dart';
import 'services/local_notification_service.dart';
import 'services/locale_controller.dart';
import 'services/push_notification_service.dart';
import 'services/theme_controller.dart';
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

  // Initialize locale and theme preferences before first frame
  await LocaleController.instance.initialize();
  await ThemeController.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.home,
    this.authController,
    this.localeController,
    this.themeController,
  });

  /// Optional custom home widget for widget testing.
  final Widget? home;
  final AuthController? authController;
  final LocaleController? localeController;
  final ThemeController? themeController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AuthController _authController;
  late bool _ownsAuthController;

  @override
  void initState() {
    super.initState();
    _ownsAuthController = widget.authController == null;
    _authController = widget.authController ?? AuthController();
  }

  @override
  void didUpdateWidget(MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.authController != null &&
        widget.authController != oldWidget.authController) {
      if (_ownsAuthController) {
        _authController.dispose();
      }
      _ownsAuthController = false;
      _authController = widget.authController!;
    }
  }

  @override
  void dispose() {
    if (_ownsAuthController) {
      _authController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeController = widget.localeController ?? LocaleController.instance;
    final themeController = widget.themeController ?? ThemeController.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([localeController, themeController]),
      child: widget.home ??
          AuthGate(
            authController: _authController,
          ),
      builder: (context, homeChild) {
        return MaterialApp(
          title: 'Dental Queue',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeController.themeMode,
          // Switch Light <-> Dark atomically in one frame to avoid 200ms ThemeData.lerp grey flicker & subtree rebuild storms
          themeAnimationStyle: AnimationStyle.noAnimation,
          locale: localeController.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: homeChild,
        );
      },
    );
  }
}
