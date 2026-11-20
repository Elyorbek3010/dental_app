import '../l10n/app_localizations.dart';

/// Maps raw or service error messages to patient-friendly localized messages.
String localizeError(String? rawError, AppLocalizations l10n) {
  if (rawError == null || rawError.trim().isEmpty) {
    return l10n.errorOccurred;
  }

  final lower = rawError.toLowerCase();

  // Network / Connection errors
  if (lower.contains('socketexception') ||
      lower.contains('serverga ulanib') ||
      lower.contains('server bilan aloqa') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('clientexception')) {
    return l10n.networkUnavailable;
  }

  // Session / 401
  if (lower.contains('autentifikatsiya') ||
      lower.contains('session expired') ||
      lower.contains('not authenticated') ||
      lower.contains('could not validate') ||
      lower.contains('token expired')) {
    return l10n.sessionExpired;
  }

  // Login credentials
  if (lower.contains('telefon raqam yoki parol noto‘g‘ri') ||
      lower.contains('invalid credentials') ||
      lower.contains('incorrect phone or password')) {
    return l10n.loginInvalidCredentials;
  }

  // Inactive account
  if (lower.contains('hisobi faol emas') || lower.contains('inactive account')) {
    return l10n.loginAccountInactive;
  }

  // Patient only
  if (lower.contains('faqat bemorlar') || lower.contains('patient only')) {
    return l10n.loginPatientOnly;
  }

  // Register phone duplicate
  if (lower.contains('allaqachon ro‘yxatdan o‘tgan') ||
      lower.contains('already registered')) {
    return l10n.registerPhoneExists;
  }

  // Already joined queue / 409
  if (lower.contains('mutaxassislik') ||
      (lower.contains('already has an active ticket') &&
          lower.contains('specialization'))) {
    return l10n.alreadyJoinedSpecializationError;
  }

  if (lower.contains('already has an active ticket') ||
      lower.contains('allaqachon ushbu navbatda faol talon')) {
    return l10n.alreadyJoinedError;
  }

  // Queue closing for new patients
  if (lower.contains('closed for new patients') ||
      lower.contains('yangi bemorlar uchun navbat yopilgan')) {
    return l10n.queueClosedForNewPatients;
  }

  // Queue paused
  if (lower.contains('vaqtincha to‘xtatilgan') || lower.contains('paused')) {
    return l10n.queuePausedSnackbar;
  }

  // Queue inactive / finished shift
  if (lower.contains('hozirda faol emas') ||
      lower.contains('queue is inactive') ||
      lower.contains('shift has already finished')) {
    return l10n.queueInactiveSnackbar;
  }

  // Queue not found / 404
  if (lower.contains('navbat topilmadi') || lower.contains('queue not found')) {
    return l10n.queueUnavailable;
  }

  // Doctor inactive
  if (lower.contains('shifokor hozirda nofaol')) {
    return l10n.doctorInactive;
  }

  // If starts with "Kutilmagan xatolik yuz berdi: "
  if (rawError.startsWith('Kutilmagan xatolik yuz berdi: ')) {
    final detail = rawError.replaceFirst('Kutilmagan xatolik yuz berdi: ', '');
    return l10n.unexpectedError(detail);
  }

  return rawError;
}
