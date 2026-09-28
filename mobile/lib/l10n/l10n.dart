import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_uz.dart';

export 'app_localizations.dart';

/// Extension providing safe, convenient access to [AppLocalizations].
///
/// Falls back to default Uzbek translations [AppLocalizationsUz] if no
/// localization delegate is mounted in the widget tree (e.g. in standalone tests).
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizationsUz();
}
