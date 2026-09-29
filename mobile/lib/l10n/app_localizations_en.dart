// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Dental Queue';

  @override
  String get appSubtitle => 'Queue system for patients';

  @override
  String get checkingSession => 'Checking secure session...';

  @override
  String get backTooltip => 'Back';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String get retryButton => 'Retry';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get saveButton => 'Save';

  @override
  String get updateButton => 'Update';

  @override
  String get deleteButton => 'Delete';

  @override
  String get editButton => 'Edit';

  @override
  String get viewButton => 'View';

  @override
  String get closeButton => 'Close';

  @override
  String get loadingText => 'Loading...';

  @override
  String get loginTitle => 'Login';

  @override
  String get loginButton => 'Log In';

  @override
  String get noAccount => 'Don\'t have an account? ';

  @override
  String get registerLink => 'Register';

  @override
  String get phoneLabel => 'Phone Number';

  @override
  String get phoneHint => '+998901234567';

  @override
  String get phoneRequired => 'Please enter your phone number';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordHint => 'Enter your password';

  @override
  String get passwordRequired => 'Please enter your password';

  @override
  String get registerTitle => 'Register';

  @override
  String get registerHeading => 'Create Patient Account';

  @override
  String get registerSubtitle =>
      'Enter your details to get full access to the clinic queue system.';

  @override
  String get fullNameLabel => 'Full Name';

  @override
  String get fullNameHint => 'e.g. John Doe';

  @override
  String get fullNameRequired => 'Please enter your full name';

  @override
  String get passwordLabelWithMin => 'Password (min 8 characters)';

  @override
  String get newPasswordHint => 'Enter new password';

  @override
  String get passwordMinLengthHelper =>
      'Password must be at least 8 characters long';

  @override
  String get passwordMinLengthError => 'Password must be at least 8 characters';

  @override
  String get registerButton => 'Register';

  @override
  String get haveAccount => 'Already have an account? ';

  @override
  String get loginLink => 'Log In';

  @override
  String get navHome => 'Home';

  @override
  String get navMyQueue => 'My Queue';

  @override
  String get navReminders => 'Reminders';

  @override
  String get navProfile => 'Profile';

  @override
  String get greeting => 'Welcome!';

  @override
  String get homeGreetingSubtitle =>
      'Fast and easy queue booking for dental visits.';

  @override
  String get homeJoinQueueButton => 'Join Queue';

  @override
  String get homeCurrentQueueSection => 'Current Queue Status';

  @override
  String get homeNoActiveQueueTitle => 'No active queue';

  @override
  String get homeNoActiveQueueDesc =>
      'You currently do not have an active queue ticket. Tap below to join a queue.';

  @override
  String get homeRemindersSection => 'Personal Reminders';

  @override
  String get homeRemindersCardTitle => 'Visit Reminders';

  @override
  String get homeRemindersCardDesc => 'Don\'t miss your dental check-ups';

  @override
  String get myQueueTitle => 'My Queue';

  @override
  String get myQueueNoActiveTitle => 'No active queue';

  @override
  String get myQueueNoActiveDesc =>
      'You are not currently in any doctor\'s queue. Tap the button below to join.';

  @override
  String get ticketNumberLabel => 'Ticket Number';

  @override
  String get doctorLabel => 'Doctor';

  @override
  String get specializationLabel => 'Specialization';

  @override
  String get roomLabel => 'Room';

  @override
  String roomWithNumber(String room) {
    return 'Room: $room';
  }

  @override
  String get queuePositionLabel => 'Queue Position';

  @override
  String get ticketTimeLabel => 'Time Issued';

  @override
  String get checkedInStatusTitle => 'Checked in at clinic';

  @override
  String get notCheckedInStatusTitle => 'Not checked in at clinic';

  @override
  String get checkedInStatusDesc =>
      'You have successfully checked in at reception. Please wait for your turn.';

  @override
  String get notCheckedInStatusDesc =>
      'When you arrive at the clinic, confirm your arrival at reception or via QR code.';

  @override
  String get myQueueReminderTitle => 'Reminder';

  @override
  String get myQueueReminderDesc =>
      'You will receive a push notification when it is your turn. You can also pull down to refresh at any time.';

  @override
  String get featuresTitle => 'Queue features:';

  @override
  String get featureTicketAndSpec => 'Ticket number and doctor specialization';

  @override
  String get featureLiveQueue =>
      'Live queue order and count of people ahead of you';

  @override
  String get featureCheckIn =>
      'QR or reception check-in upon arrival at clinic';

  @override
  String get featurePushNotifications =>
      'Instant push notification when your turn arrives';

  @override
  String peopleAhead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people ahead of you',
      one: '1 person ahead of you',
      zero: 'No one ahead of you',
    );
    return '$_temp0';
  }

  @override
  String get statusWaiting => 'Waiting';

  @override
  String get statusCalled => 'Your turn';

  @override
  String get statusServing => 'In progress';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusSkipped => 'Skipped';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get profileTitle => 'Profile';

  @override
  String get patientDefaultName => 'Patient Account';

  @override
  String get activeAccountBadge => 'Active';

  @override
  String get inactiveAccountBadge => 'Inactive';

  @override
  String get accountNotLoadedBadge => 'Account info not loaded';

  @override
  String get phoneProfileLabel => 'Phone Number';

  @override
  String get notAssigned => 'Not assigned';

  @override
  String get userRoleProfileLabel => 'User Role';

  @override
  String patientRoleValue(String role) {
    return 'Patient ($role)';
  }

  @override
  String get patientRoleFallback => 'Patient';

  @override
  String get pushNotificationsProfileLabel => 'Push Notifications';

  @override
  String get pushNotificationsActiveValue => 'Active (FCM)';

  @override
  String get systemProfileLabel => 'System';

  @override
  String get appVersionProfileLabel => 'App Version';

  @override
  String get languageSectionTitle => 'App Language';

  @override
  String get languageUzbek => 'O‘zbekcha';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

  @override
  String get logoutButton => 'Log Out';

  @override
  String get logoutDialogTitle => 'Log Out';

  @override
  String get logoutDialogContent =>
      'Are you sure you want to log out of your account?';

  @override
  String get authNextStep =>
      'Authentication will be connected in the next step.';

  @override
  String get remindersTitle => 'My Reminders';

  @override
  String get newReminderTooltip => 'New Reminder';

  @override
  String get addReminderButton => 'Add Reminder';

  @override
  String get noRemindersTitle => 'No reminders yet';

  @override
  String get noRemindersDesc =>
      'Don\'t forget your dental visits and check-ups.\nSet a personal reminder for a date and time convenient for you.';

  @override
  String get editReminderModalTitle => 'Edit Reminder';

  @override
  String get addReminderModalTitle => 'Add New Reminder';

  @override
  String get reminderDateLabel => 'Date';

  @override
  String get reminderTimeLabel => 'Time';

  @override
  String get reminderNoteLabel => 'Short Note (optional)';

  @override
  String get reminderNoteHint => 'e.g. Dental check-up';

  @override
  String get reminderFutureError => 'Reminder time must be in the future.';

  @override
  String get reminderUpdatedSuccess => 'Reminder updated successfully.';

  @override
  String get reminderCreatedSuccess => 'New reminder saved and scheduled.';

  @override
  String get deleteReminderDialogTitle => 'Delete Reminder';

  @override
  String get deleteReminderDialogContent =>
      'Are you sure you want to delete this reminder?';

  @override
  String get reminderDeletedSuccess => 'Reminder deleted.';

  @override
  String get reminderPastBadge => 'Past';

  @override
  String get reminderWaitingBadge => 'Upcoming';

  @override
  String get defaultReminderNotificationBody =>
      'Reminder for your dental appointment.';

  @override
  String get selectSpecializationTitle => 'Select Specialization';

  @override
  String get noSpecializationsTitle => 'No specializations found';

  @override
  String get noSpecializationsDesc =>
      'There are currently no active specializations in the clinic. Please check back later.';

  @override
  String get selectDoctorTitle => 'Select Doctor';

  @override
  String get noDoctorsTitle => 'No doctors found';

  @override
  String noDoctorsDesc(String specializationName) {
    return 'There are currently no active doctors for $specializationName.';
  }

  @override
  String specializationHeaderPrefix(String specializationName) {
    return 'Specialization: $specializationName';
  }

  @override
  String roomNumberDoctorFormat(String room) {
    return 'Room $room';
  }

  @override
  String get doctorQueueTitle => 'Queue Details';

  @override
  String get noQueueTodayTitle => 'No queue today';

  @override
  String noQueueTodayDesc(String doctorName) {
    return 'No queue is scheduled today for $doctorName. Please select another doctor or check back later.';
  }

  @override
  String get todayQueueHeader => 'Today\'s Queue Status';

  @override
  String get queueStatusPaused => 'Paused';

  @override
  String get queueStatusActive => 'Active';

  @override
  String get queueStatusActiveBadge => 'Queue active';

  @override
  String get currentlyServingLabel => 'Currently serving';

  @override
  String get waitingCountLabel => 'Waiting';

  @override
  String get calledCountLabel => 'Called';

  @override
  String get ifYouJoinNowLabel => 'If you join now';

  @override
  String get estimatedPositionLabel => 'Estimated position';

  @override
  String estimatedPositionValue(int position) {
    return '#$position';
  }

  @override
  String get queueTemporarilyPaused => 'Queue temporarily paused';

  @override
  String get todayQueueNotOpened => 'Today\'s queue has not been opened';

  @override
  String get queueUnavailableState => 'Queue unavailable';

  @override
  String get queueDateLabel => 'Date';

  @override
  String get admissionStatusLabel => 'Admission Status';

  @override
  String get admissionStatusPaused => 'Temporarily paused';

  @override
  String get admissionStatusServing => 'Admitting patients';

  @override
  String get joinQueueButton => 'Join Queue';

  @override
  String get queuePausedSnackbar => 'Queue is temporarily paused.';

  @override
  String get queueInactiveSnackbar => 'Queue is currently inactive.';

  @override
  String ticketJoinedSuccess(int ticketNumber) {
    return 'Successfully joined the queue! Ticket: №$ticketNumber';
  }

  @override
  String get conflictActiveTicketTitle => 'Active ticket exists';

  @override
  String get conflictCannotJoinTitle => 'Could not join queue';

  @override
  String get goToMyTicketButton => 'Go to My Ticket';

  @override
  String get errorOccurred => 'An error occurred';

  @override
  String get networkUnavailable =>
      'Unable to connect to server. Please check your internet connection.';

  @override
  String get sessionExpired => 'Session expired. Please log in again.';

  @override
  String get queueUnavailable => 'Queue not found.';

  @override
  String get alreadyJoinedError =>
      'You already have an active ticket in this queue.';

  @override
  String get loginInvalidCredentials => 'Invalid phone number or password.';

  @override
  String get loginAccountInactive => 'Account is inactive.';

  @override
  String get loginPatientOnly => 'This app is for patients only.';

  @override
  String get registerPhoneExists => 'This phone number is already registered.';

  @override
  String get doctorInactive => 'Doctor is currently inactive.';

  @override
  String unexpectedError(String error) {
    return 'An unexpected error occurred: $error';
  }

  @override
  String get scanQrTitle => 'Scan QR Code';

  @override
  String get scanQrInstructions =>
      'Point your camera at the clinic reception QR code';

  @override
  String get cameraPermissionRequired =>
      'Camera permission is required to scan the QR code.';

  @override
  String get cameraPermissionGrant => 'Grant Permission';

  @override
  String get checkInButtonText => 'Check In via QR';

  @override
  String get checkingInLoading => 'Checking in...';

  @override
  String get checkInSuccessSnackbar =>
      'Check-in successful! Your presence has been confirmed.';

  @override
  String get checkInFailedTitle => 'Check-in Failed';

  @override
  String get cancelTicketButton => 'Cancel Ticket';

  @override
  String get cancelConfirmTitle => 'Cancel this ticket?';

  @override
  String get cancelConfirmMessage =>
      'Are you sure you want to cancel your queue ticket? This action cannot be undone.';

  @override
  String get cancelConfirmYes => 'Yes, Cancel';

  @override
  String get cancelConfirmNo => 'No, Keep';

  @override
  String get cancellingTicketLoading => 'Cancelling ticket...';

  @override
  String get cancelSuccessSnackbar => 'Ticket successfully cancelled.';

  @override
  String get calledBannerTitle => 'It\'s your turn';

  @override
  String get calledBannerSubtitle => 'Please proceed to the designated room';

  @override
  String get servingBannerTitle => 'Reception in progress';

  @override
  String get servingBannerSubtitle => 'The doctor is currently seeing you';

  @override
  String get waitingCheckInPrompt =>
      'When you arrive at the clinic, scan the QR code at reception';

  @override
  String get enterCodeManually => 'Enter code manually';

  @override
  String get qrCodeInputHint => 'Enter QR token';

  @override
  String get submitButton => 'Submit';

  @override
  String get errorInvalidQrCode => 'Invalid or expired QR code.';

  @override
  String get errorNoWaitingTicketForClinic =>
      'No active waiting ticket found for this clinic.';

  @override
  String get errorTicketAlreadyCheckedIn =>
      'This queue ticket is already checked in.';

  @override
  String get errorCannotCancelOtherTicket =>
      'You cannot cancel another patient\'s ticket.';

  @override
  String get errorOnlyWaitingCalledCancellable =>
      'Only waiting or called tickets can be cancelled.';
}
