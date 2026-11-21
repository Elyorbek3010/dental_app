import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('uz'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In uz, this message translates to:
  /// **'Dental Queue'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Bemorlar uchun navbat tizimi'**
  String get appSubtitle;

  /// No description provided for @checkingSession.
  ///
  /// In uz, this message translates to:
  /// **'Xavfsiz sessiya tekshirilmoqda...'**
  String get checkingSession;

  /// No description provided for @backTooltip.
  ///
  /// In uz, this message translates to:
  /// **'Ortga'**
  String get backTooltip;

  /// No description provided for @refreshTooltip.
  ///
  /// In uz, this message translates to:
  /// **'Yangilash'**
  String get refreshTooltip;

  /// No description provided for @retryButton.
  ///
  /// In uz, this message translates to:
  /// **'Qayta urinish'**
  String get retryButton;

  /// No description provided for @cancelButton.
  ///
  /// In uz, this message translates to:
  /// **'Bekor qilish'**
  String get cancelButton;

  /// No description provided for @saveButton.
  ///
  /// In uz, this message translates to:
  /// **'Saqlash'**
  String get saveButton;

  /// No description provided for @updateButton.
  ///
  /// In uz, this message translates to:
  /// **'Yangilash'**
  String get updateButton;

  /// No description provided for @deleteButton.
  ///
  /// In uz, this message translates to:
  /// **'O‘chirish'**
  String get deleteButton;

  /// No description provided for @editButton.
  ///
  /// In uz, this message translates to:
  /// **'Tahrirlash'**
  String get editButton;

  /// No description provided for @viewButton.
  ///
  /// In uz, this message translates to:
  /// **'Ko‘rish'**
  String get viewButton;

  /// No description provided for @closeButton.
  ///
  /// In uz, this message translates to:
  /// **'Yopish'**
  String get closeButton;

  /// No description provided for @loadingText.
  ///
  /// In uz, this message translates to:
  /// **'Yuklanmoqda...'**
  String get loadingText;

  /// No description provided for @loginTitle.
  ///
  /// In uz, this message translates to:
  /// **'Kirish'**
  String get loginTitle;

  /// No description provided for @loginButton.
  ///
  /// In uz, this message translates to:
  /// **'Kirish'**
  String get loginButton;

  /// No description provided for @noAccount.
  ///
  /// In uz, this message translates to:
  /// **'Hisobingiz yo‘qmi? '**
  String get noAccount;

  /// No description provided for @registerLink.
  ///
  /// In uz, this message translates to:
  /// **'Ro‘yxatdan o‘tish'**
  String get registerLink;

  /// No description provided for @phoneLabel.
  ///
  /// In uz, this message translates to:
  /// **'Telefon raqam'**
  String get phoneLabel;

  /// No description provided for @phoneHint.
  ///
  /// In uz, this message translates to:
  /// **'+998901234567'**
  String get phoneHint;

  /// No description provided for @phoneRequired.
  ///
  /// In uz, this message translates to:
  /// **'Telefon raqamni kiriting'**
  String get phoneRequired;

  /// No description provided for @passwordLabel.
  ///
  /// In uz, this message translates to:
  /// **'Parol'**
  String get passwordLabel;

  /// No description provided for @passwordHint.
  ///
  /// In uz, this message translates to:
  /// **'Parolingizni kiriting'**
  String get passwordHint;

  /// No description provided for @passwordRequired.
  ///
  /// In uz, this message translates to:
  /// **'Parolni kiriting'**
  String get passwordRequired;

  /// No description provided for @registerTitle.
  ///
  /// In uz, this message translates to:
  /// **'Ro‘yxatdan o‘tish'**
  String get registerTitle;

  /// No description provided for @registerHeading.
  ///
  /// In uz, this message translates to:
  /// **'Bemor hisobini yaratish'**
  String get registerHeading;

  /// No description provided for @registerSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Klinika navbat tizimidan to‘liq foydalanish uchun maʼlumotlaringizni kiriting.'**
  String get registerSubtitle;

  /// No description provided for @fullNameLabel.
  ///
  /// In uz, this message translates to:
  /// **'Ism va familiya'**
  String get fullNameLabel;

  /// No description provided for @fullNameHint.
  ///
  /// In uz, this message translates to:
  /// **'Masalan: Ali Valiyev'**
  String get fullNameHint;

  /// No description provided for @fullNameRequired.
  ///
  /// In uz, this message translates to:
  /// **'Ism va familiyangizni kiriting'**
  String get fullNameRequired;

  /// No description provided for @passwordLabelWithMin.
  ///
  /// In uz, this message translates to:
  /// **'Parol (kamida 8 ta belgi)'**
  String get passwordLabelWithMin;

  /// No description provided for @newPasswordHint.
  ///
  /// In uz, this message translates to:
  /// **'Yangi parol kiriting'**
  String get newPasswordHint;

  /// No description provided for @passwordMinLengthHelper.
  ///
  /// In uz, this message translates to:
  /// **'Parol uzunligi kamida 8 ta belgi bo‘lishi shart'**
  String get passwordMinLengthHelper;

  /// No description provided for @passwordMinLengthError.
  ///
  /// In uz, this message translates to:
  /// **'Parol kamida 8 ta belgidan iborat bo‘lishi kerak'**
  String get passwordMinLengthError;

  /// No description provided for @registerButton.
  ///
  /// In uz, this message translates to:
  /// **'Ro‘yxatdan o‘tish'**
  String get registerButton;

  /// No description provided for @haveAccount.
  ///
  /// In uz, this message translates to:
  /// **'Hisobingiz bormi? '**
  String get haveAccount;

  /// No description provided for @loginLink.
  ///
  /// In uz, this message translates to:
  /// **'Kirish'**
  String get loginLink;

  /// No description provided for @navHome.
  ///
  /// In uz, this message translates to:
  /// **'Asosiy'**
  String get navHome;

  /// No description provided for @navMyQueue.
  ///
  /// In uz, this message translates to:
  /// **'Navbatim'**
  String get navMyQueue;

  /// No description provided for @navReminders.
  ///
  /// In uz, this message translates to:
  /// **'Eslatmalar'**
  String get navReminders;

  /// No description provided for @navProfile.
  ///
  /// In uz, this message translates to:
  /// **'Profil'**
  String get navProfile;

  /// No description provided for @greeting.
  ///
  /// In uz, this message translates to:
  /// **'Assalomu alaykum!'**
  String get greeting;

  /// No description provided for @homeGreetingSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Stomatolog qabuliga tez va oson navbat oling.'**
  String get homeGreetingSubtitle;

  /// No description provided for @homeJoinQueueButton.
  ///
  /// In uz, this message translates to:
  /// **'Navbatga yozilish'**
  String get homeJoinQueueButton;

  /// No description provided for @homeCurrentQueueSection.
  ///
  /// In uz, this message translates to:
  /// **'Joriy navbat holati'**
  String get homeCurrentQueueSection;

  /// No description provided for @homeNoActiveQueueTitle.
  ///
  /// In uz, this message translates to:
  /// **'Faol navbatingiz yo‘q'**
  String get homeNoActiveQueueTitle;

  /// No description provided for @homeNoActiveQueueDesc.
  ///
  /// In uz, this message translates to:
  /// **'Hozirda sizda hech qanday faol navbat mavjud emas. Qabulga yozilish uchun tugmani bosing.'**
  String get homeNoActiveQueueDesc;

  /// No description provided for @homeRemindersSection.
  ///
  /// In uz, this message translates to:
  /// **'Shaxsiy eslatmalar'**
  String get homeRemindersSection;

  /// No description provided for @homeRemindersCardTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tashrif eslatmalari'**
  String get homeRemindersCardTitle;

  /// No description provided for @homeRemindersCardDesc.
  ///
  /// In uz, this message translates to:
  /// **'Stomatolog tekshiruvlarini unutmang'**
  String get homeRemindersCardDesc;

  /// No description provided for @myQueueTitle.
  ///
  /// In uz, this message translates to:
  /// **'Mening navbatim'**
  String get myQueueTitle;

  /// No description provided for @myQueueNoActiveTitle.
  ///
  /// In uz, this message translates to:
  /// **'Faol navbatingiz yo‘q'**
  String get myQueueNoActiveTitle;

  /// No description provided for @myQueueNoActiveDesc.
  ///
  /// In uz, this message translates to:
  /// **'Siz hozirda hech qanday shifokor navbatida emassiz. Navbat olish uchun quyidagi tugmani bosing.'**
  String get myQueueNoActiveDesc;

  /// No description provided for @ticketNumberLabel.
  ///
  /// In uz, this message translates to:
  /// **'Talon raqami'**
  String get ticketNumberLabel;

  /// No description provided for @doctorLabel.
  ///
  /// In uz, this message translates to:
  /// **'Shifokor'**
  String get doctorLabel;

  /// No description provided for @specializationLabel.
  ///
  /// In uz, this message translates to:
  /// **'Mutaxassislik'**
  String get specializationLabel;

  /// No description provided for @roomLabel.
  ///
  /// In uz, this message translates to:
  /// **'Xona'**
  String get roomLabel;

  /// No description provided for @roomWithNumber.
  ///
  /// In uz, this message translates to:
  /// **'Xona: {room}'**
  String roomWithNumber(String room);

  /// No description provided for @queuePositionLabel.
  ///
  /// In uz, this message translates to:
  /// **'Tartib raqami'**
  String get queuePositionLabel;

  /// No description provided for @ticketTimeLabel.
  ///
  /// In uz, this message translates to:
  /// **'Olingan vaqti'**
  String get ticketTimeLabel;

  /// No description provided for @checkedInStatusTitle.
  ///
  /// In uz, this message translates to:
  /// **'Klinikada ro‘yxatdan o‘tilgan'**
  String get checkedInStatusTitle;

  /// No description provided for @notCheckedInStatusTitle.
  ///
  /// In uz, this message translates to:
  /// **'Klinikada ro‘yxatdan o‘tilmagan'**
  String get notCheckedInStatusTitle;

  /// No description provided for @checkedInStatusDesc.
  ///
  /// In uz, this message translates to:
  /// **'Siz qabulxonada muvaffaqiyatli qayd etilgansiz. Iltimos, navbatingizni kuting.'**
  String get checkedInStatusDesc;

  /// No description provided for @notCheckedInStatusDesc.
  ///
  /// In uz, this message translates to:
  /// **'Klinikaga yetib kelganingizda, qabulxonada yoki QR-kod orqali kelganingizni tasdiqlang.'**
  String get notCheckedInStatusDesc;

  /// No description provided for @myQueueReminderTitle.
  ///
  /// In uz, this message translates to:
  /// **'Eslatma'**
  String get myQueueReminderTitle;

  /// No description provided for @myQueueReminderDesc.
  ///
  /// In uz, this message translates to:
  /// **'Navbatingiz kelganda telefoningizga bildirishnoma (push) yuboriladi. Sahifani pastga tortib istalgan paytda yangilashingiz mumkin.'**
  String get myQueueReminderDesc;

  /// No description provided for @featuresTitle.
  ///
  /// In uz, this message translates to:
  /// **'Navbat imkoniyatlari:'**
  String get featuresTitle;

  /// No description provided for @featureTicketAndSpec.
  ///
  /// In uz, this message translates to:
  /// **'Talon raqami va shifokor mutaxassisligi'**
  String get featureTicketAndSpec;

  /// No description provided for @featureLiveQueue.
  ///
  /// In uz, this message translates to:
  /// **'Jonli navbat tartibi va oldingizdagi odamlar soni'**
  String get featureLiveQueue;

  /// No description provided for @featureCheckIn.
  ///
  /// In uz, this message translates to:
  /// **'Klinikaga kelganda QR yoki qabulxonada check-in qilish'**
  String get featureCheckIn;

  /// No description provided for @featurePushNotifications.
  ///
  /// In uz, this message translates to:
  /// **'Navbatingiz kelganda darhol push-xabarnoma olish'**
  String get featurePushNotifications;

  /// Number of people ahead in the queue
  ///
  /// In uz, this message translates to:
  /// **'{count, plural, =0{Oldingizda hech kim yo‘q} other{Oldingizda {count} kishi bor}}'**
  String peopleAhead(int count);

  /// No description provided for @statusWaiting.
  ///
  /// In uz, this message translates to:
  /// **'Kutilmoqda'**
  String get statusWaiting;

  /// No description provided for @statusCalled.
  ///
  /// In uz, this message translates to:
  /// **'Navbatingiz keldi'**
  String get statusCalled;

  /// No description provided for @statusServing.
  ///
  /// In uz, this message translates to:
  /// **'Qabul davom etmoqda'**
  String get statusServing;

  /// No description provided for @statusCompleted.
  ///
  /// In uz, this message translates to:
  /// **'Yakunlandi'**
  String get statusCompleted;

  /// No description provided for @statusSkipped.
  ///
  /// In uz, this message translates to:
  /// **'O‘tkazib yuborildi'**
  String get statusSkipped;

  /// No description provided for @statusCancelled.
  ///
  /// In uz, this message translates to:
  /// **'Bekor qilingan'**
  String get statusCancelled;

  /// No description provided for @profileTitle.
  ///
  /// In uz, this message translates to:
  /// **'Profil'**
  String get profileTitle;

  /// No description provided for @patientDefaultName.
  ///
  /// In uz, this message translates to:
  /// **'Bemor hisobi'**
  String get patientDefaultName;

  /// No description provided for @activeAccountBadge.
  ///
  /// In uz, this message translates to:
  /// **'Faol hisob'**
  String get activeAccountBadge;

  /// No description provided for @inactiveAccountBadge.
  ///
  /// In uz, this message translates to:
  /// **'Nofaol'**
  String get inactiveAccountBadge;

  /// No description provided for @accountNotLoadedBadge.
  ///
  /// In uz, this message translates to:
  /// **'Hisob maʼlumotlari yuklanmagan'**
  String get accountNotLoadedBadge;

  /// No description provided for @phoneProfileLabel.
  ///
  /// In uz, this message translates to:
  /// **'Telefon raqam'**
  String get phoneProfileLabel;

  /// No description provided for @notAssigned.
  ///
  /// In uz, this message translates to:
  /// **'Biriktirilmagan'**
  String get notAssigned;

  /// No description provided for @userRoleProfileLabel.
  ///
  /// In uz, this message translates to:
  /// **'Foydalanuvchi roli'**
  String get userRoleProfileLabel;

  /// No description provided for @patientRoleValue.
  ///
  /// In uz, this message translates to:
  /// **'Bemor ({role})'**
  String patientRoleValue(String role);

  /// No description provided for @patientRoleFallback.
  ///
  /// In uz, this message translates to:
  /// **'Bemor (Patient)'**
  String get patientRoleFallback;

  /// No description provided for @pushNotificationsProfileLabel.
  ///
  /// In uz, this message translates to:
  /// **'Push-bildirishnomalar'**
  String get pushNotificationsProfileLabel;

  /// No description provided for @pushNotificationsActiveValue.
  ///
  /// In uz, this message translates to:
  /// **'Faol (FCM)'**
  String get pushNotificationsActiveValue;

  /// No description provided for @systemProfileLabel.
  ///
  /// In uz, this message translates to:
  /// **'Tizim'**
  String get systemProfileLabel;

  /// No description provided for @appVersionProfileLabel.
  ///
  /// In uz, this message translates to:
  /// **'Ilova versiyasi'**
  String get appVersionProfileLabel;

  /// No description provided for @languageSectionTitle.
  ///
  /// In uz, this message translates to:
  /// **'Ilova tili'**
  String get languageSectionTitle;

  /// No description provided for @languageUzbek.
  ///
  /// In uz, this message translates to:
  /// **'O‘zbekcha'**
  String get languageUzbek;

  /// No description provided for @languageRussian.
  ///
  /// In uz, this message translates to:
  /// **'Русский'**
  String get languageRussian;

  /// No description provided for @languageEnglish.
  ///
  /// In uz, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @logoutButton.
  ///
  /// In uz, this message translates to:
  /// **'Tizimdan chiqish'**
  String get logoutButton;

  /// No description provided for @logoutDialogTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tizimdan chiqish'**
  String get logoutDialogTitle;

  /// No description provided for @logoutDialogContent.
  ///
  /// In uz, this message translates to:
  /// **'Haqiqatan ham hisobingizdan chiqmoqchimisiz?'**
  String get logoutDialogContent;

  /// No description provided for @authNextStep.
  ///
  /// In uz, this message translates to:
  /// **'Autentifikatsiya keyingi bosqichda ulanadi.'**
  String get authNextStep;

  /// No description provided for @remindersTitle.
  ///
  /// In uz, this message translates to:
  /// **'Eslatmalarim'**
  String get remindersTitle;

  /// No description provided for @newReminderTooltip.
  ///
  /// In uz, this message translates to:
  /// **'Yangi eslatma'**
  String get newReminderTooltip;

  /// No description provided for @addReminderButton.
  ///
  /// In uz, this message translates to:
  /// **'Eslatma qo‘shish'**
  String get addReminderButton;

  /// No description provided for @noRemindersTitle.
  ///
  /// In uz, this message translates to:
  /// **'Hozircha eslatmalar yo‘q'**
  String get noRemindersTitle;

  /// No description provided for @noRemindersDesc.
  ///
  /// In uz, this message translates to:
  /// **'Stomatolog ko‘rigi yoki tashrifingizni unutmang.\nO‘zingiz uchun qulay sana va vaqtga eslatma o‘rnating.'**
  String get noRemindersDesc;

  /// No description provided for @editReminderModalTitle.
  ///
  /// In uz, this message translates to:
  /// **'Eslatmani tahrirlash'**
  String get editReminderModalTitle;

  /// No description provided for @addReminderModalTitle.
  ///
  /// In uz, this message translates to:
  /// **'Yangi eslatma qo‘shish'**
  String get addReminderModalTitle;

  /// No description provided for @reminderDateLabel.
  ///
  /// In uz, this message translates to:
  /// **'Sana'**
  String get reminderDateLabel;

  /// No description provided for @reminderTimeLabel.
  ///
  /// In uz, this message translates to:
  /// **'Vaqt'**
  String get reminderTimeLabel;

  /// No description provided for @reminderNoteLabel.
  ///
  /// In uz, this message translates to:
  /// **'Qisqa eslatma (ixtiyoriy)'**
  String get reminderNoteLabel;

  /// No description provided for @reminderNoteHint.
  ///
  /// In uz, this message translates to:
  /// **'Masalan: Tish tekshiruvi'**
  String get reminderNoteHint;

  /// No description provided for @reminderFutureError.
  ///
  /// In uz, this message translates to:
  /// **'Eslatma vaqti kelajakda bo‘lishi kerak.'**
  String get reminderFutureError;

  /// No description provided for @reminderUpdatedSuccess.
  ///
  /// In uz, this message translates to:
  /// **'Eslatma muvaffaqiyatli yangilandi.'**
  String get reminderUpdatedSuccess;

  /// No description provided for @reminderCreatedSuccess.
  ///
  /// In uz, this message translates to:
  /// **'Yangi eslatma saqlandi va rejalashtirildi.'**
  String get reminderCreatedSuccess;

  /// No description provided for @deleteReminderDialogTitle.
  ///
  /// In uz, this message translates to:
  /// **'Eslatmani o‘chirish'**
  String get deleteReminderDialogTitle;

  /// No description provided for @deleteReminderDialogContent.
  ///
  /// In uz, this message translates to:
  /// **'Haqiqatan ham ushbu eslatmani o‘chirmoqchimisiz?'**
  String get deleteReminderDialogContent;

  /// No description provided for @reminderDeletedSuccess.
  ///
  /// In uz, this message translates to:
  /// **'Eslatma o‘chirildi.'**
  String get reminderDeletedSuccess;

  /// No description provided for @reminderPastBadge.
  ///
  /// In uz, this message translates to:
  /// **'O‘tgan'**
  String get reminderPastBadge;

  /// No description provided for @reminderWaitingBadge.
  ///
  /// In uz, this message translates to:
  /// **'Kutilmoqda'**
  String get reminderWaitingBadge;

  /// No description provided for @defaultReminderNotificationBody.
  ///
  /// In uz, this message translates to:
  /// **'Stomatolog tashrifingiz uchun eslatma.'**
  String get defaultReminderNotificationBody;

  /// No description provided for @selectSpecializationTitle.
  ///
  /// In uz, this message translates to:
  /// **'Mutaxassislikni tanlash'**
  String get selectSpecializationTitle;

  /// No description provided for @noSpecializationsTitle.
  ///
  /// In uz, this message translates to:
  /// **'Mutaxassisliklar topilmadi'**
  String get noSpecializationsTitle;

  /// No description provided for @noSpecializationsDesc.
  ///
  /// In uz, this message translates to:
  /// **'Hozirda klinikada faol mutaxassisliklar mavjud emas. Iltimos, keyinroq qayta tekshirib ko‘ring.'**
  String get noSpecializationsDesc;

  /// No description provided for @selectDoctorTitle.
  ///
  /// In uz, this message translates to:
  /// **'Shifokorni tanlash'**
  String get selectDoctorTitle;

  /// No description provided for @noDoctorsTitle.
  ///
  /// In uz, this message translates to:
  /// **'Shifokorlar topilmadi'**
  String get noDoctorsTitle;

  /// No description provided for @noDoctorsDesc.
  ///
  /// In uz, this message translates to:
  /// **'{specializationName} mutaxassisligi bo‘yicha hozirda faol shifokorlar mavjud emas.'**
  String noDoctorsDesc(String specializationName);

  /// No description provided for @specializationHeaderPrefix.
  ///
  /// In uz, this message translates to:
  /// **'Mutaxassislik: {specializationName}'**
  String specializationHeaderPrefix(String specializationName);

  /// No description provided for @roomNumberDoctorFormat.
  ///
  /// In uz, this message translates to:
  /// **'{room}-xona'**
  String roomNumberDoctorFormat(String room);

  /// No description provided for @doctorQueueTitle.
  ///
  /// In uz, this message translates to:
  /// **'Navbat maʼlumotlari'**
  String get doctorQueueTitle;

  /// No description provided for @noQueueTodayTitle.
  ///
  /// In uz, this message translates to:
  /// **'Bugun navbat mavjud emas'**
  String get noQueueTodayTitle;

  /// No description provided for @noQueueTodayDesc.
  ///
  /// In uz, this message translates to:
  /// **'Bugun {doctorName} uchun navbat ochilmagan. Iltimos, boshqa shifokorni tanlang yoki keyinroq tekshirib ko‘ring.'**
  String noQueueTodayDesc(String doctorName);

  /// No description provided for @todayQueueHeader.
  ///
  /// In uz, this message translates to:
  /// **'Bugungi navbat holati'**
  String get todayQueueHeader;

  /// No description provided for @queueStatusPaused.
  ///
  /// In uz, this message translates to:
  /// **'Pauza'**
  String get queueStatusPaused;

  /// No description provided for @queueStatusActive.
  ///
  /// In uz, this message translates to:
  /// **'Faol'**
  String get queueStatusActive;

  /// No description provided for @queueStatusActiveBadge.
  ///
  /// In uz, this message translates to:
  /// **'Navbat faol'**
  String get queueStatusActiveBadge;

  /// No description provided for @currentlyServingLabel.
  ///
  /// In uz, this message translates to:
  /// **'Hozir qabulda'**
  String get currentlyServingLabel;

  /// No description provided for @waitingCountLabel.
  ///
  /// In uz, this message translates to:
  /// **'Kutayotganlar'**
  String get waitingCountLabel;

  /// No description provided for @calledCountLabel.
  ///
  /// In uz, this message translates to:
  /// **'Chaqirilganlar'**
  String get calledCountLabel;

  /// No description provided for @ifYouJoinNowLabel.
  ///
  /// In uz, this message translates to:
  /// **'Agar hozir qo‘shilsangiz'**
  String get ifYouJoinNowLabel;

  /// No description provided for @estimatedPositionLabel.
  ///
  /// In uz, this message translates to:
  /// **'Taxminiy o‘rningiz'**
  String get estimatedPositionLabel;

  /// No description provided for @estimatedPositionValue.
  ///
  /// In uz, this message translates to:
  /// **'#{position}'**
  String estimatedPositionValue(int position);

  /// No description provided for @queueTemporarilyPaused.
  ///
  /// In uz, this message translates to:
  /// **'Navbat vaqtincha to‘xtatilgan'**
  String get queueTemporarilyPaused;

  /// No description provided for @todayQueueNotOpened.
  ///
  /// In uz, this message translates to:
  /// **'Bugun navbat ochilmagan'**
  String get todayQueueNotOpened;

  /// No description provided for @queueUnavailableState.
  ///
  /// In uz, this message translates to:
  /// **'Navbat mavjud emas'**
  String get queueUnavailableState;

  /// No description provided for @queueDateLabel.
  ///
  /// In uz, this message translates to:
  /// **'Sana'**
  String get queueDateLabel;

  /// No description provided for @admissionStatusLabel.
  ///
  /// In uz, this message translates to:
  /// **'Qabul holati'**
  String get admissionStatusLabel;

  /// No description provided for @admissionStatusPaused.
  ///
  /// In uz, this message translates to:
  /// **'Vaqtincha to‘xtatilgan'**
  String get admissionStatusPaused;

  /// No description provided for @admissionStatusServing.
  ///
  /// In uz, this message translates to:
  /// **'Bemorlar qabul qilinmoqda'**
  String get admissionStatusServing;

  /// No description provided for @joinQueueButton.
  ///
  /// In uz, this message translates to:
  /// **'Navbatga qo‘shilish'**
  String get joinQueueButton;

  /// No description provided for @queuePausedSnackbar.
  ///
  /// In uz, this message translates to:
  /// **'Navbat vaqtincha to‘xtatilgan.'**
  String get queuePausedSnackbar;

  /// No description provided for @queueInactiveSnackbar.
  ///
  /// In uz, this message translates to:
  /// **'Navbat hozirda faol emas.'**
  String get queueInactiveSnackbar;

  /// No description provided for @ticketJoinedSuccess.
  ///
  /// In uz, this message translates to:
  /// **'Navbatga muvaffaqiyatli yozildingiz! Talon: №{ticketNumber}'**
  String ticketJoinedSuccess(int ticketNumber);

  /// No description provided for @conflictActiveTicketTitle.
  ///
  /// In uz, this message translates to:
  /// **'Faol navbat mavjud'**
  String get conflictActiveTicketTitle;

  /// No description provided for @conflictCannotJoinTitle.
  ///
  /// In uz, this message translates to:
  /// **'Navbatga qo‘shilib bo‘lmadi'**
  String get conflictCannotJoinTitle;

  /// No description provided for @goToMyTicketButton.
  ///
  /// In uz, this message translates to:
  /// **'Navbatimga o‘tish'**
  String get goToMyTicketButton;

  /// No description provided for @errorOccurred.
  ///
  /// In uz, this message translates to:
  /// **'Xatolik yuz berdi'**
  String get errorOccurred;

  /// No description provided for @networkUnavailable.
  ///
  /// In uz, this message translates to:
  /// **'Serverga ulanib bo‘lmadi. Internet aloqasini tekshiring.'**
  String get networkUnavailable;

  /// No description provided for @sessionExpired.
  ///
  /// In uz, this message translates to:
  /// **'Autentifikatsiya muddati tugagan. Iltimos, qaytadan kiring.'**
  String get sessionExpired;

  /// No description provided for @queueUnavailable.
  ///
  /// In uz, this message translates to:
  /// **'Navbat topilmadi.'**
  String get queueUnavailable;

  /// No description provided for @alreadyJoinedError.
  ///
  /// In uz, this message translates to:
  /// **'Sizda allaqachon ushbu navbatda faol talon mavjud.'**
  String get alreadyJoinedError;

  /// No description provided for @loginInvalidCredentials.
  ///
  /// In uz, this message translates to:
  /// **'Telefon raqam yoki parol noto‘g‘ri.'**
  String get loginInvalidCredentials;

  /// No description provided for @loginAccountInactive.
  ///
  /// In uz, this message translates to:
  /// **'Foydalanuvchi hisobi faol emas.'**
  String get loginAccountInactive;

  /// No description provided for @loginPatientOnly.
  ///
  /// In uz, this message translates to:
  /// **'Ushbu ilova faqat bemorlar uchun mo‘ljallangan.'**
  String get loginPatientOnly;

  /// No description provided for @registerPhoneExists.
  ///
  /// In uz, this message translates to:
  /// **'Ushbu telefon raqam allaqachon ro‘yxatdan o‘tgan.'**
  String get registerPhoneExists;

  /// No description provided for @doctorInactive.
  ///
  /// In uz, this message translates to:
  /// **'Shifokor hozirda nofaol holatda.'**
  String get doctorInactive;

  /// No description provided for @unexpectedError.
  ///
  /// In uz, this message translates to:
  /// **'Kutilmagan xatolik yuz berdi: {error}'**
  String unexpectedError(String error);

  /// No description provided for @scanQrTitle.
  ///
  /// In uz, this message translates to:
  /// **'QR-kodni skanerlash'**
  String get scanQrTitle;

  /// No description provided for @scanQrInstructions.
  ///
  /// In uz, this message translates to:
  /// **'Klinika qabulxonasidagi QR-kodni kameraga qarating'**
  String get scanQrInstructions;

  /// No description provided for @cameraPermissionRequired.
  ///
  /// In uz, this message translates to:
  /// **'QR-kodni skanerlash uchun kamera ruxsati zarur.'**
  String get cameraPermissionRequired;

  /// No description provided for @cameraPermissionGrant.
  ///
  /// In uz, this message translates to:
  /// **'Ruxsat berish'**
  String get cameraPermissionGrant;

  /// No description provided for @checkInButtonText.
  ///
  /// In uz, this message translates to:
  /// **'QR orqali ro‘yxatdan o‘tish'**
  String get checkInButtonText;

  /// No description provided for @checkingInLoading.
  ///
  /// In uz, this message translates to:
  /// **'Ro‘yxatdan o‘tkazilmoqda...'**
  String get checkingInLoading;

  /// No description provided for @checkInSuccessSnackbar.
  ///
  /// In uz, this message translates to:
  /// **'Ro‘yxatdan muvaffaqiyatli o‘tdingiz! Navbatingiz kutish ro‘yxatida tasdiqlandi.'**
  String get checkInSuccessSnackbar;

  /// No description provided for @checkInFailedTitle.
  ///
  /// In uz, this message translates to:
  /// **'Ro‘yxatdan o‘tib bo‘lmadi'**
  String get checkInFailedTitle;

  /// No description provided for @cancelTicketButton.
  ///
  /// In uz, this message translates to:
  /// **'Talonni bekor qilish'**
  String get cancelTicketButton;

  /// No description provided for @cancelConfirmTitle.
  ///
  /// In uz, this message translates to:
  /// **'Talonni bekor qilasizmi?'**
  String get cancelConfirmTitle;

  /// No description provided for @cancelConfirmMessage.
  ///
  /// In uz, this message translates to:
  /// **'Haqiqatan ham navbat talonini bekor qilmoqchimisiz? Ushbu amalni ortga qaytarib bo‘lmaydi.'**
  String get cancelConfirmMessage;

  /// No description provided for @cancelConfirmYes.
  ///
  /// In uz, this message translates to:
  /// **'Ha, bekor qilish'**
  String get cancelConfirmYes;

  /// No description provided for @cancelConfirmNo.
  ///
  /// In uz, this message translates to:
  /// **'Yo‘q, qolsin'**
  String get cancelConfirmNo;

  /// No description provided for @cancellingTicketLoading.
  ///
  /// In uz, this message translates to:
  /// **'Talon bekor qilinmoqda...'**
  String get cancellingTicketLoading;

  /// No description provided for @cancelSuccessSnackbar.
  ///
  /// In uz, this message translates to:
  /// **'Talon muvaffaqiyatli bekor qilindi.'**
  String get cancelSuccessSnackbar;

  /// No description provided for @calledBannerTitle.
  ///
  /// In uz, this message translates to:
  /// **'Navbatingiz keldi'**
  String get calledBannerTitle;

  /// No description provided for @calledBannerSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Iltimos, ko‘rsatilgan xonaga kiring'**
  String get calledBannerSubtitle;

  /// No description provided for @servingBannerTitle.
  ///
  /// In uz, this message translates to:
  /// **'Qabul davom etmoqda'**
  String get servingBannerTitle;

  /// No description provided for @servingBannerSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Shifokor ko‘rigi davom etmoqda'**
  String get servingBannerSubtitle;

  /// No description provided for @waitingCheckInPrompt.
  ///
  /// In uz, this message translates to:
  /// **'Klinikaga yetib kelganingizda, qabulxona QR-kodini skanerlang'**
  String get waitingCheckInPrompt;

  /// No description provided for @enterCodeManually.
  ///
  /// In uz, this message translates to:
  /// **'Kodni qo‘lda kiritish'**
  String get enterCodeManually;

  /// No description provided for @qrCodeInputHint.
  ///
  /// In uz, this message translates to:
  /// **'QR tokenini kiriting'**
  String get qrCodeInputHint;

  /// No description provided for @submitButton.
  ///
  /// In uz, this message translates to:
  /// **'Yuborish'**
  String get submitButton;

  /// No description provided for @errorInvalidQrCode.
  ///
  /// In uz, this message translates to:
  /// **'Yaroqsiz yoki muddati o‘tgan QR-kod.'**
  String get errorInvalidQrCode;

  /// No description provided for @errorNoWaitingTicketForClinic.
  ///
  /// In uz, this message translates to:
  /// **'Ushbu klinika uchun kutilayotgan faol navbat taloni topilmadi.'**
  String get errorNoWaitingTicketForClinic;

  /// No description provided for @errorTicketAlreadyCheckedIn.
  ///
  /// In uz, this message translates to:
  /// **'Ushbu navbat taloni allaqachon ro‘yxatdan o‘tkazilgan.'**
  String get errorTicketAlreadyCheckedIn;

  /// No description provided for @errorCannotCancelOtherTicket.
  ///
  /// In uz, this message translates to:
  /// **'Boshqa bemorning navbat talonini bekor qilish taqiqlanadi.'**
  String get errorCannotCancelOtherTicket;

  /// No description provided for @errorOnlyWaitingCalledCancellable.
  ///
  /// In uz, this message translates to:
  /// **'Faqat kutilayotgan yoki chaqirilgan talonlar bekor qilinishi mumkin.'**
  String get errorOnlyWaitingCalledCancellable;

  /// No description provided for @skippedBannerTitle.
  ///
  /// In uz, this message translates to:
  /// **'Taloningiz o‘tkazib yuborildi'**
  String get skippedBannerTitle;

  /// No description provided for @skippedBannerSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Taloningiz vaqtincha chetlatilgan. Navbatni faqat qabulxona qayta tiklashi mumkin.'**
  String get skippedBannerSubtitle;

  /// No description provided for @fgNotifCalled.
  ///
  /// In uz, this message translates to:
  /// **'Navbatingiz keldi! Iltimos, qabulga kiring.'**
  String get fgNotifCalled;

  /// No description provided for @fgNotifSkipped.
  ///
  /// In uz, this message translates to:
  /// **'Taloningiz o‘tkazib yuborildi. Qayta tiklash uchun qabulxonaga murojaat qiling.'**
  String get fgNotifSkipped;

  /// No description provided for @fgNotifRestored.
  ///
  /// In uz, this message translates to:
  /// **'Taloningiz navbatga qayta tiklandi.'**
  String get fgNotifRestored;

  /// No description provided for @fgNotifMissedTurn.
  ///
  /// In uz, this message translates to:
  /// **'Navbatingiz o‘tkazildi va navbat oxiriga ko‘chirildi.'**
  String get fgNotifMissedTurn;

  /// No description provided for @remainingTimeLabel.
  ///
  /// In uz, this message translates to:
  /// **'Qolgan vaqt'**
  String get remainingTimeLabel;

  /// No description provided for @pausedCountdownBadge.
  ///
  /// In uz, this message translates to:
  /// **'To‘xtatilgan'**
  String get pausedCountdownBadge;

  /// No description provided for @alreadyJoinedSpecializationError.
  ///
  /// In uz, this message translates to:
  /// **'Sizda ushbu mutaxassislik bo‘yicha allaqachon faol talon mavjud.'**
  String get alreadyJoinedSpecializationError;

  /// No description provided for @queuePausedBadge.
  ///
  /// In uz, this message translates to:
  /// **'Navbat vaqtincha to‘xtatilgan'**
  String get queuePausedBadge;

  /// No description provided for @syncConnectionWarning.
  ///
  /// In uz, this message translates to:
  /// **'Aloqa uzildi. Oxirgi maʼlumotlar ko‘rsatilmoqda, qayta ulanilmoqda...'**
  String get syncConnectionWarning;

  /// No description provided for @themeSectionTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tashqi ko‘rinish'**
  String get themeSectionTitle;

  /// No description provided for @themeLight.
  ///
  /// In uz, this message translates to:
  /// **'Yorug‘'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In uz, this message translates to:
  /// **'Tungi'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In uz, this message translates to:
  /// **'Tizim'**
  String get themeSystem;

  /// No description provided for @quickAccessTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tezkor xizmatlar'**
  String get quickAccessTitle;

  /// No description provided for @activeVisitStatusTitle.
  ///
  /// In uz, this message translates to:
  /// **'Faol tashrif'**
  String get activeVisitStatusTitle;

  /// No description provided for @viewLiveQueueLabel.
  ///
  /// In uz, this message translates to:
  /// **'Jonli navbat'**
  String get viewLiveQueueLabel;

  /// No description provided for @clinicPortalBadge.
  ///
  /// In uz, this message translates to:
  /// **'Stomatologiya klinikasi'**
  String get clinicPortalBadge;

  /// No description provided for @searchSpecialtiesHint.
  ///
  /// In uz, this message translates to:
  /// **'Mutaxassislikni qidirish...'**
  String get searchSpecialtiesHint;

  /// No description provided for @chooseCareSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Shifokorlarni ko‘rish uchun tanlang'**
  String get chooseCareSubtitle;

  /// No description provided for @queueClosedForNewPatients.
  ///
  /// In uz, this message translates to:
  /// **'Yangi bemorlar uchun navbat yopilgan.'**
  String get queueClosedForNewPatients;

  /// No description provided for @queueStatusClosing.
  ///
  /// In uz, this message translates to:
  /// **'Qabul yopilgan'**
  String get queueStatusClosing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
