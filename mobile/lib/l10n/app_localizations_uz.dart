// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appTitle => 'Dental Queue';

  @override
  String get appSubtitle => 'Bemorlar uchun navbat tizimi';

  @override
  String get checkingSession => 'Xavfsiz sessiya tekshirilmoqda...';

  @override
  String get backTooltip => 'Ortga';

  @override
  String get refreshTooltip => 'Yangilash';

  @override
  String get retryButton => 'Qayta urinish';

  @override
  String get cancelButton => 'Bekor qilish';

  @override
  String get saveButton => 'Saqlash';

  @override
  String get updateButton => 'Yangilash';

  @override
  String get deleteButton => 'O‘chirish';

  @override
  String get editButton => 'Tahrirlash';

  @override
  String get viewButton => 'Ko‘rish';

  @override
  String get closeButton => 'Yopish';

  @override
  String get loadingText => 'Yuklanmoqda...';

  @override
  String get loginTitle => 'Kirish';

  @override
  String get loginButton => 'Kirish';

  @override
  String get noAccount => 'Hisobingiz yo‘qmi? ';

  @override
  String get registerLink => 'Ro‘yxatdan o‘tish';

  @override
  String get phoneLabel => 'Telefon raqam';

  @override
  String get phoneHint => '+998901234567';

  @override
  String get phoneRequired => 'Telefon raqamni kiriting';

  @override
  String get passwordLabel => 'Parol';

  @override
  String get passwordHint => 'Parolingizni kiriting';

  @override
  String get passwordRequired => 'Parolni kiriting';

  @override
  String get registerTitle => 'Ro‘yxatdan o‘tish';

  @override
  String get registerHeading => 'Bemor hisobini yaratish';

  @override
  String get registerSubtitle =>
      'Klinika navbat tizimidan to‘liq foydalanish uchun maʼlumotlaringizni kiriting.';

  @override
  String get fullNameLabel => 'Ism va familiya';

  @override
  String get fullNameHint => 'Masalan: Ali Valiyev';

  @override
  String get fullNameRequired => 'Ism va familiyangizni kiriting';

  @override
  String get passwordLabelWithMin => 'Parol (kamida 8 ta belgi)';

  @override
  String get newPasswordHint => 'Yangi parol kiriting';

  @override
  String get passwordMinLengthHelper =>
      'Parol uzunligi kamida 8 ta belgi bo‘lishi shart';

  @override
  String get passwordMinLengthError =>
      'Parol kamida 8 ta belgidan iborat bo‘lishi kerak';

  @override
  String get registerButton => 'Ro‘yxatdan o‘tish';

  @override
  String get haveAccount => 'Hisobingiz bormi? ';

  @override
  String get loginLink => 'Kirish';

  @override
  String get navHome => 'Asosiy';

  @override
  String get navMyQueue => 'Navbatim';

  @override
  String get navReminders => 'Eslatmalar';

  @override
  String get navProfile => 'Profil';

  @override
  String get greeting => 'Assalomu alaykum!';

  @override
  String get homeGreetingSubtitle =>
      'Stomatolog qabuliga tez va oson navbat oling.';

  @override
  String get homeJoinQueueButton => 'Navbatga yozilish';

  @override
  String get homeCurrentQueueSection => 'Joriy navbat holati';

  @override
  String get homeNoActiveQueueTitle => 'Faol navbatingiz yo‘q';

  @override
  String get homeNoActiveQueueDesc =>
      'Hozirda sizda hech qanday faol navbat mavjud emas. Qabulga yozilish uchun tugmani bosing.';

  @override
  String get homeRemindersSection => 'Shaxsiy eslatmalar';

  @override
  String get homeRemindersCardTitle => 'Tashrif eslatmalari';

  @override
  String get homeRemindersCardDesc => 'Stomatolog tekshiruvlarini unutmang';

  @override
  String get myQueueTitle => 'Mening navbatim';

  @override
  String get myQueueNoActiveTitle => 'Faol navbatingiz yo‘q';

  @override
  String get myQueueNoActiveDesc =>
      'Siz hozirda hech qanday shifokor navbatida emassiz. Navbat olish uchun quyidagi tugmani bosing.';

  @override
  String get ticketNumberLabel => 'Talon raqami';

  @override
  String get doctorLabel => 'Shifokor';

  @override
  String get specializationLabel => 'Mutaxassislik';

  @override
  String get roomLabel => 'Xona';

  @override
  String roomWithNumber(String room) {
    return 'Xona: $room';
  }

  @override
  String get queuePositionLabel => 'Tartib raqami';

  @override
  String get ticketTimeLabel => 'Olingan vaqti';

  @override
  String get checkedInStatusTitle => 'Klinikada ro‘yxatdan o‘tilgan';

  @override
  String get notCheckedInStatusTitle => 'Klinikada ro‘yxatdan o‘tilmagan';

  @override
  String get checkedInStatusDesc =>
      'Siz qabulxonada muvaffaqiyatli qayd etilgansiz. Iltimos, navbatingizni kuting.';

  @override
  String get notCheckedInStatusDesc =>
      'Klinikaga yetib kelganingizda, qabulxonada yoki QR-kod orqali kelganingizni tasdiqlang.';

  @override
  String get myQueueReminderTitle => 'Eslatma';

  @override
  String get myQueueReminderDesc =>
      'Navbatingiz kelganda telefoningizga bildirishnoma (push) yuboriladi. Sahifani pastga tortib istalgan paytda yangilashingiz mumkin.';

  @override
  String get featuresTitle => 'Navbat imkoniyatlari:';

  @override
  String get featureTicketAndSpec => 'Talon raqami va shifokor mutaxassisligi';

  @override
  String get featureLiveQueue =>
      'Jonli navbat tartibi va oldingizdagi odamlar soni';

  @override
  String get featureCheckIn =>
      'Klinikaga kelganda QR yoki qabulxonada check-in qilish';

  @override
  String get featurePushNotifications =>
      'Navbatingiz kelganda darhol push-xabarnoma olish';

  @override
  String peopleAhead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Oldingizda $count kishi bor',
      zero: 'Oldingizda hech kim yo‘q',
    );
    return '$_temp0';
  }

  @override
  String get statusWaiting => 'Kutilmoqda';

  @override
  String get statusCalled => 'Navbatingiz keldi';

  @override
  String get statusServing => 'Qabul davom etmoqda';

  @override
  String get statusCompleted => 'Yakunlandi';

  @override
  String get statusSkipped => 'O‘tkazib yuborildi';

  @override
  String get statusCancelled => 'Bekor qilingan';

  @override
  String get profileTitle => 'Profil';

  @override
  String get patientDefaultName => 'Bemor hisobi';

  @override
  String get activeAccountBadge => 'Faol hisob';

  @override
  String get inactiveAccountBadge => 'Nofaol';

  @override
  String get accountNotLoadedBadge => 'Hisob maʼlumotlari yuklanmagan';

  @override
  String get phoneProfileLabel => 'Telefon raqam';

  @override
  String get notAssigned => 'Biriktirilmagan';

  @override
  String get userRoleProfileLabel => 'Foydalanuvchi roli';

  @override
  String patientRoleValue(String role) {
    return 'Bemor ($role)';
  }

  @override
  String get patientRoleFallback => 'Bemor (Patient)';

  @override
  String get pushNotificationsProfileLabel => 'Push-bildirishnomalar';

  @override
  String get pushNotificationsActiveValue => 'Faol (FCM)';

  @override
  String get systemProfileLabel => 'Tizim';

  @override
  String get appVersionProfileLabel => 'Ilova versiyasi';

  @override
  String get languageSectionTitle => 'Ilova tili';

  @override
  String get languageUzbek => 'O‘zbekcha';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

  @override
  String get logoutButton => 'Tizimdan chiqish';

  @override
  String get logoutDialogTitle => 'Tizimdan chiqish';

  @override
  String get logoutDialogContent =>
      'Haqiqatan ham hisobingizdan chiqmoqchimisiz?';

  @override
  String get authNextStep => 'Autentifikatsiya keyingi bosqichda ulanadi.';

  @override
  String get remindersTitle => 'Eslatmalarim';

  @override
  String get newReminderTooltip => 'Yangi eslatma';

  @override
  String get addReminderButton => 'Eslatma qo‘shish';

  @override
  String get noRemindersTitle => 'Hozircha eslatmalar yo‘q';

  @override
  String get noRemindersDesc =>
      'Stomatolog ko‘rigi yoki tashrifingizni unutmang.\nO‘zingiz uchun qulay sana va vaqtga eslatma o‘rnating.';

  @override
  String get editReminderModalTitle => 'Eslatmani tahrirlash';

  @override
  String get addReminderModalTitle => 'Yangi eslatma qo‘shish';

  @override
  String get reminderDateLabel => 'Sana';

  @override
  String get reminderTimeLabel => 'Vaqt';

  @override
  String get reminderNoteLabel => 'Qisqa eslatma (ixtiyoriy)';

  @override
  String get reminderNoteHint => 'Masalan: Tish tekshiruvi';

  @override
  String get reminderFutureError => 'Eslatma vaqti kelajakda bo‘lishi kerak.';

  @override
  String get reminderUpdatedSuccess => 'Eslatma muvaffaqiyatli yangilandi.';

  @override
  String get reminderCreatedSuccess =>
      'Yangi eslatma saqlandi va rejalashtirildi.';

  @override
  String get deleteReminderDialogTitle => 'Eslatmani o‘chirish';

  @override
  String get deleteReminderDialogContent =>
      'Haqiqatan ham ushbu eslatmani o‘chirmoqchimisiz?';

  @override
  String get reminderDeletedSuccess => 'Eslatma o‘chirildi.';

  @override
  String get reminderPastBadge => 'O‘tgan';

  @override
  String get reminderWaitingBadge => 'Kutilmoqda';

  @override
  String get defaultReminderNotificationBody =>
      'Stomatolog tashrifingiz uchun eslatma.';

  @override
  String get selectSpecializationTitle => 'Mutaxassislikni tanlash';

  @override
  String get noSpecializationsTitle => 'Mutaxassisliklar topilmadi';

  @override
  String get noSpecializationsDesc =>
      'Hozirda klinikada faol mutaxassisliklar mavjud emas. Iltimos, keyinroq qayta tekshirib ko‘ring.';

  @override
  String get selectDoctorTitle => 'Shifokorni tanlash';

  @override
  String get noDoctorsTitle => 'Shifokorlar topilmadi';

  @override
  String noDoctorsDesc(String specializationName) {
    return '$specializationName mutaxassisligi bo‘yicha hozirda faol shifokorlar mavjud emas.';
  }

  @override
  String specializationHeaderPrefix(String specializationName) {
    return 'Mutaxassislik: $specializationName';
  }

  @override
  String roomNumberDoctorFormat(String room) {
    return '$room-xona';
  }

  @override
  String get doctorQueueTitle => 'Navbat maʼlumotlari';

  @override
  String get noQueueTodayTitle => 'Bugun navbat mavjud emas';

  @override
  String noQueueTodayDesc(String doctorName) {
    return 'Bugun $doctorName uchun navbat ochilmagan. Iltimos, boshqa shifokorni tanlang yoki keyinroq tekshirib ko‘ring.';
  }

  @override
  String get todayQueueHeader => 'Bugungi navbat holati';

  @override
  String get queueStatusPaused => 'Pauza';

  @override
  String get queueStatusActive => 'Faol';

  @override
  String get queueStatusActiveBadge => 'Navbat faol';

  @override
  String get currentlyServingLabel => 'Hozir qabulda';

  @override
  String get waitingCountLabel => 'Kutayotganlar';

  @override
  String get calledCountLabel => 'Chaqirilganlar';

  @override
  String get ifYouJoinNowLabel => 'Agar hozir qo‘shilsangiz';

  @override
  String get estimatedPositionLabel => 'Taxminiy o‘rningiz';

  @override
  String estimatedPositionValue(int position) {
    return '#$position';
  }

  @override
  String get queueTemporarilyPaused => 'Navbat vaqtincha to‘xtatilgan';

  @override
  String get todayQueueNotOpened => 'Bugun navbat ochilmagan';

  @override
  String get queueUnavailableState => 'Navbat mavjud emas';

  @override
  String get queueDateLabel => 'Sana';

  @override
  String get admissionStatusLabel => 'Qabul holati';

  @override
  String get admissionStatusPaused => 'Vaqtincha to‘xtatilgan';

  @override
  String get admissionStatusServing => 'Bemorlar qabul qilinmoqda';

  @override
  String get joinQueueButton => 'Navbatga qo‘shilish';

  @override
  String get queuePausedSnackbar => 'Navbat vaqtincha to‘xtatilgan.';

  @override
  String get queueInactiveSnackbar => 'Navbat hozirda faol emas.';

  @override
  String ticketJoinedSuccess(int ticketNumber) {
    return 'Navbatga muvaffaqiyatli yozildingiz! Talon: №$ticketNumber';
  }

  @override
  String get conflictActiveTicketTitle => 'Faol navbat mavjud';

  @override
  String get conflictCannotJoinTitle => 'Navbatga qo‘shilib bo‘lmadi';

  @override
  String get goToMyTicketButton => 'Navbatimga o‘tish';

  @override
  String get errorOccurred => 'Xatolik yuz berdi';

  @override
  String get networkUnavailable =>
      'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.';

  @override
  String get sessionExpired =>
      'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.';

  @override
  String get queueUnavailable => 'Navbat topilmadi.';

  @override
  String get alreadyJoinedError =>
      'Sizda allaqachon ushbu navbatda faol talon mavjud.';

  @override
  String get loginInvalidCredentials => 'Telefon raqam yoki parol noto‘g‘ri.';

  @override
  String get loginAccountInactive => 'Foydalanuvchi hisobi faol emas.';

  @override
  String get loginPatientOnly =>
      'Ushbu ilova faqat bemorlar uchun mo‘ljallangan.';

  @override
  String get registerPhoneExists =>
      'Ushbu telefon raqam allaqachon ro‘yxatdan o‘tgan.';

  @override
  String get doctorInactive => 'Shifokor hozirda nofaol holatda.';

  @override
  String unexpectedError(String error) {
    return 'Kutilmagan xatolik yuz berdi: $error';
  }

  @override
  String get scanQrTitle => 'QR-kodni skanerlash';

  @override
  String get scanQrInstructions =>
      'Klinika qabulxonasidagi QR-kodni kameraga qarating';

  @override
  String get cameraPermissionRequired =>
      'QR-kodni skanerlash uchun kamera ruxsati zarur.';

  @override
  String get cameraPermissionGrant => 'Ruxsat berish';

  @override
  String get checkInButtonText => 'QR orqali ro‘yxatdan o‘tish';

  @override
  String get checkingInLoading => 'Ro‘yxatdan o‘tkazilmoqda...';

  @override
  String get checkInSuccessSnackbar =>
      'Ro‘yxatdan muvaffaqiyatli o‘tdingiz! Navbatingiz kutish ro‘yxatida tasdiqlandi.';

  @override
  String get checkInFailedTitle => 'Ro‘yxatdan o‘tib bo‘lmadi';

  @override
  String get cancelTicketButton => 'Talonni bekor qilish';

  @override
  String get cancelConfirmTitle => 'Talonni bekor qilasizmi?';

  @override
  String get cancelConfirmMessage =>
      'Haqiqatan ham navbat talonini bekor qilmoqchimisiz? Ushbu amalni ortga qaytarib bo‘lmaydi.';

  @override
  String get cancelConfirmYes => 'Ha, bekor qilish';

  @override
  String get cancelConfirmNo => 'Yo‘q, qolsin';

  @override
  String get cancellingTicketLoading => 'Talon bekor qilinmoqda...';

  @override
  String get cancelSuccessSnackbar => 'Talon muvaffaqiyatli bekor qilindi.';

  @override
  String get calledBannerTitle => 'Navbatingiz keldi';

  @override
  String get calledBannerSubtitle => 'Iltimos, ko‘rsatilgan xonaga kiring';

  @override
  String get servingBannerTitle => 'Qabul davom etmoqda';

  @override
  String get servingBannerSubtitle => 'Shifokor ko‘rigi davom etmoqda';

  @override
  String get waitingCheckInPrompt =>
      'Klinikaga yetib kelganingizda, qabulxona QR-kodini skanerlang';

  @override
  String get enterCodeManually => 'Kodni qo‘lda kiritish';

  @override
  String get qrCodeInputHint => 'QR tokenini kiriting';

  @override
  String get submitButton => 'Yuborish';

  @override
  String get errorInvalidQrCode => 'Yaroqsiz yoki muddati o‘tgan QR-kod.';

  @override
  String get errorNoWaitingTicketForClinic =>
      'Ushbu klinika uchun kutilayotgan faol navbat taloni topilmadi.';

  @override
  String get errorTicketAlreadyCheckedIn =>
      'Ushbu navbat taloni allaqachon ro‘yxatdan o‘tkazilgan.';

  @override
  String get errorCannotCancelOtherTicket =>
      'Boshqa bemorning navbat talonini bekor qilish taqiqlanadi.';

  @override
  String get errorOnlyWaitingCalledCancellable =>
      'Faqat kutilayotgan yoki chaqirilgan talonlar bekor qilinishi mumkin.';

  @override
  String get skippedBannerTitle => 'Taloningiz o‘tkazib yuborildi';

  @override
  String get skippedBannerSubtitle =>
      'Taloningiz vaqtincha chetlatilgan. Navbatni faqat qabulxona qayta tiklashi mumkin.';

  @override
  String get fgNotifCalled => 'Navbatingiz keldi! Iltimos, qabulga kiring.';

  @override
  String get fgNotifSkipped =>
      'Taloningiz o‘tkazib yuborildi. Qayta tiklash uchun qabulxonaga murojaat qiling.';

  @override
  String get fgNotifRestored => 'Taloningiz navbatga qayta tiklandi.';

  @override
  String get fgNotifMissedTurn =>
      'Navbatingiz o‘tkazildi va navbat oxiriga ko‘chirildi.';

  @override
  String get remainingTimeLabel => 'Qolgan vaqt';

  @override
  String get pausedCountdownBadge => 'To‘xtatilgan';
}
