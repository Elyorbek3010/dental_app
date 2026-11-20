// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Dental Queue';

  @override
  String get appSubtitle => 'Система очередей для пациентов';

  @override
  String get checkingSession => 'Проверка безопасной сессии...';

  @override
  String get backTooltip => 'Назад';

  @override
  String get refreshTooltip => 'Обновить';

  @override
  String get retryButton => 'Повторить';

  @override
  String get cancelButton => 'Отмена';

  @override
  String get saveButton => 'Сохранить';

  @override
  String get updateButton => 'Обновить';

  @override
  String get deleteButton => 'Удалить';

  @override
  String get editButton => 'Редактировать';

  @override
  String get viewButton => 'Просмотр';

  @override
  String get closeButton => 'Закрыть';

  @override
  String get loadingText => 'Загрузка...';

  @override
  String get loginTitle => 'Вход';

  @override
  String get loginButton => 'Войти';

  @override
  String get noAccount => 'Нет аккаунта? ';

  @override
  String get registerLink => 'Регистрация';

  @override
  String get phoneLabel => 'Номер телефона';

  @override
  String get phoneHint => '+998901234567';

  @override
  String get phoneRequired => 'Введите номер телефона';

  @override
  String get passwordLabel => 'Пароль';

  @override
  String get passwordHint => 'Введите ваш пароль';

  @override
  String get passwordRequired => 'Введите пароль';

  @override
  String get registerTitle => 'Регистрация';

  @override
  String get registerHeading => 'Создание аккаунта пациента';

  @override
  String get registerSubtitle =>
      'Введите данные для полного доступа к системе очередей клиники.';

  @override
  String get fullNameLabel => 'Имя и фамилия';

  @override
  String get fullNameHint => 'Например: Али Валиев';

  @override
  String get fullNameRequired => 'Введите имя и фамилию';

  @override
  String get passwordLabelWithMin => 'Пароль (не менее 8 символов)';

  @override
  String get newPasswordHint => 'Введите новый пароль';

  @override
  String get passwordMinLengthHelper =>
      'Длина пароля должна быть не менее 8 символов';

  @override
  String get passwordMinLengthError =>
      'Пароль должен состоять минимум из 8 символов';

  @override
  String get registerButton => 'Зарегистрироваться';

  @override
  String get haveAccount => 'Уже есть аккаунт? ';

  @override
  String get loginLink => 'Войти';

  @override
  String get navHome => 'Главная';

  @override
  String get navMyQueue => 'Моя очередь';

  @override
  String get navReminders => 'Напоминания';

  @override
  String get navProfile => 'Профиль';

  @override
  String get greeting => 'Здравствуйте!';

  @override
  String get homeGreetingSubtitle =>
      'Быстрая и удобная запись в очередь к стоматологу.';

  @override
  String get homeJoinQueueButton => 'Записаться в очередь';

  @override
  String get homeCurrentQueueSection => 'Текущий статус очереди';

  @override
  String get homeNoActiveQueueTitle => 'У вас нет активной очереди';

  @override
  String get homeNoActiveQueueDesc =>
      'В данный момент у вас нет активной очереди. Нажмите кнопку, чтобы записаться на прием.';

  @override
  String get homeRemindersSection => 'Личные напоминания';

  @override
  String get homeRemindersCardTitle => 'Напоминания о визитах';

  @override
  String get homeRemindersCardDesc => 'Не забывайте о приеме у стоматолога';

  @override
  String get myQueueTitle => 'Моя очередь';

  @override
  String get myQueueNoActiveTitle => 'У вас нет активной очереди';

  @override
  String get myQueueNoActiveDesc =>
      'Вы пока не состоите в очереди ни к одному врачу. Нажмите кнопку ниже, чтобы занять очередь.';

  @override
  String get ticketNumberLabel => 'Номер талона';

  @override
  String get doctorLabel => 'Врач';

  @override
  String get specializationLabel => 'Специальность';

  @override
  String get roomLabel => 'Кабинет';

  @override
  String roomWithNumber(String room) {
    return 'Кабинет: $room';
  }

  @override
  String get queuePositionLabel => 'Порядковый номер';

  @override
  String get ticketTimeLabel => 'Время получения';

  @override
  String get checkedInStatusTitle => 'Зарегистрирован в клинике';

  @override
  String get notCheckedInStatusTitle => 'Не зарегистрирован в клинике';

  @override
  String get checkedInStatusDesc =>
      'Вы успешно отметились на ресепшене. Пожалуйста, ожидайте своей очереди.';

  @override
  String get notCheckedInStatusDesc =>
      'По прибытии в клинику подтвердите визит на стойке регистрации или через QR-код.';

  @override
  String get myQueueReminderTitle => 'Напоминание';

  @override
  String get myQueueReminderDesc =>
      'Когда подойдет ваша очередь, на ваш телефон поступит push-уведомление. Вы можете обновить страницу в любое время свайпом вниз.';

  @override
  String get featuresTitle => 'Возможности очереди:';

  @override
  String get featureTicketAndSpec => 'Номер талона и специальность врача';

  @override
  String get featureLiveQueue =>
      'Живой порядок очереди и количество людей перед вами';

  @override
  String get featureCheckIn =>
      'Check-in по прибытии в клинику через QR или ресепшен';

  @override
  String get featurePushNotifications =>
      'Мгновенное push-уведомление о наступлении вашей очереди';

  @override
  String peopleAhead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Перед вами $count человек',
      many: 'Перед вами $count человек',
      few: 'Перед вами $count человека',
      one: 'Перед вами 1 человек',
      zero: 'Перед вами никого нет',
    );
    return '$_temp0';
  }

  @override
  String get statusWaiting => 'Ожидание';

  @override
  String get statusCalled => 'Ваша очередь';

  @override
  String get statusServing => 'Идет прием';

  @override
  String get statusCompleted => 'Завершен';

  @override
  String get statusSkipped => 'Пропущен';

  @override
  String get statusCancelled => 'Отменен';

  @override
  String get profileTitle => 'Профиль';

  @override
  String get patientDefaultName => 'Аккаунт пациента';

  @override
  String get activeAccountBadge => 'Активен';

  @override
  String get inactiveAccountBadge => 'Неактивен';

  @override
  String get accountNotLoadedBadge => 'Данные аккаунта не загружены';

  @override
  String get phoneProfileLabel => 'Номер телефона';

  @override
  String get notAssigned => 'Не указан';

  @override
  String get userRoleProfileLabel => 'Роль пользователя';

  @override
  String patientRoleValue(String role) {
    return 'Пациент ($role)';
  }

  @override
  String get patientRoleFallback => 'Пациент (Patient)';

  @override
  String get pushNotificationsProfileLabel => 'Push-уведомления';

  @override
  String get pushNotificationsActiveValue => 'Активны (FCM)';

  @override
  String get systemProfileLabel => 'Система';

  @override
  String get appVersionProfileLabel => 'Версия приложения';

  @override
  String get languageSectionTitle => 'Язык приложения';

  @override
  String get languageUzbek => 'O‘zbekcha';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

  @override
  String get logoutButton => 'Выйти из системы';

  @override
  String get logoutDialogTitle => 'Выход из системы';

  @override
  String get logoutDialogContent =>
      'Вы уверены, что хотите выйти из своего аккаунта?';

  @override
  String get authNextStep =>
      'Аутентификация будет подключена на следующем этапе.';

  @override
  String get remindersTitle => 'Мои напоминания';

  @override
  String get newReminderTooltip => 'Новое напоминание';

  @override
  String get addReminderButton => 'Добавить напоминание';

  @override
  String get noRemindersTitle => 'Пока нет напоминаний';

  @override
  String get noRemindersDesc =>
      'Не забывайте об осмотре или визите к стоматологу.\nУстановите напоминание на удобную дату и время.';

  @override
  String get editReminderModalTitle => 'Редактировать напоминание';

  @override
  String get addReminderModalTitle => 'Добавить новое напоминание';

  @override
  String get reminderDateLabel => 'Дата';

  @override
  String get reminderTimeLabel => 'Время';

  @override
  String get reminderNoteLabel => 'Краткая заметка (необязательно)';

  @override
  String get reminderNoteHint => 'Например: Осмотр у стоматолога';

  @override
  String get reminderFutureError => 'Время напоминания должно быть в будущем.';

  @override
  String get reminderUpdatedSuccess => 'Напоминание успешно обновлено.';

  @override
  String get reminderCreatedSuccess =>
      'Новое напоминание сохранено и запланировано.';

  @override
  String get deleteReminderDialogTitle => 'Удаление напоминания';

  @override
  String get deleteReminderDialogContent =>
      'Вы уверены, что хотите удалить это напоминание?';

  @override
  String get reminderDeletedSuccess => 'Напоминание удалено.';

  @override
  String get reminderPastBadge => 'Прошедшее';

  @override
  String get reminderWaitingBadge => 'Ожидается';

  @override
  String get defaultReminderNotificationBody =>
      'Напоминание о визите к стоматологу.';

  @override
  String get selectSpecializationTitle => 'Выбор специальности';

  @override
  String get noSpecializationsTitle => 'Специальности не найдены';

  @override
  String get noSpecializationsDesc =>
      'В настоящее время в клинике нет активных специальностей. Пожалуйста, проверьте позже.';

  @override
  String get selectDoctorTitle => 'Выбор врача';

  @override
  String get noDoctorsTitle => 'Врачи не найдены';

  @override
  String noDoctorsDesc(String specializationName) {
    return 'По специальности $specializationName в настоящее время нет активных врачей.';
  }

  @override
  String specializationHeaderPrefix(String specializationName) {
    return 'Специальность: $specializationName';
  }

  @override
  String roomNumberDoctorFormat(String room) {
    return 'Кабинет $room';
  }

  @override
  String get doctorQueueTitle => 'Информация об очереди';

  @override
  String get noQueueTodayTitle => 'Сегодня очереди нет';

  @override
  String noQueueTodayDesc(String doctorName) {
    return 'Сегодня очередь к врачу $doctorName не открыта. Пожалуйста, выберите другого врача или проверьте позже.';
  }

  @override
  String get todayQueueHeader => 'Сегодняшнее состояние очереди';

  @override
  String get queueStatusPaused => 'Пауза';

  @override
  String get queueStatusActive => 'Активна';

  @override
  String get queueStatusActiveBadge => 'Очередь активна';

  @override
  String get currentlyServingLabel => 'Сейчас на приёме';

  @override
  String get waitingCountLabel => 'В ожидании';

  @override
  String get calledCountLabel => 'Вызваны';

  @override
  String get ifYouJoinNowLabel => 'Если вы войдёте сейчас';

  @override
  String get estimatedPositionLabel => 'Примерное место в очереди';

  @override
  String estimatedPositionValue(int position) {
    return '#$position';
  }

  @override
  String get queueTemporarilyPaused => 'Очередь временно приостановлена';

  @override
  String get todayQueueNotOpened => 'Сегодня очередь не открыта';

  @override
  String get queueUnavailableState => 'Очередь недоступна';

  @override
  String get queueDateLabel => 'Дата';

  @override
  String get admissionStatusLabel => 'Статус приема';

  @override
  String get admissionStatusPaused => 'Временно приостановлен';

  @override
  String get admissionStatusServing => 'Идет прием пациентов';

  @override
  String get joinQueueButton => 'Занять очередь';

  @override
  String get queuePausedSnackbar => 'Очередь временно приостановлена.';

  @override
  String get queueInactiveSnackbar => 'Очередь сейчас не активна.';

  @override
  String ticketJoinedSuccess(int ticketNumber) {
    return 'Вы успешно записались в очередь! Талон: №$ticketNumber';
  }

  @override
  String get conflictActiveTicketTitle => 'Есть активная очередь';

  @override
  String get conflictCannotJoinTitle => 'Не удалось занять очередь';

  @override
  String get goToMyTicketButton => 'Перейти к талону';

  @override
  String get errorOccurred => 'Произошла ошибка';

  @override
  String get networkUnavailable =>
      'Не удалось подключиться к серверу. Проверьте интернет-соединение.';

  @override
  String get sessionExpired =>
      'Срок действия сессии истек. Пожалуйста, войдите снова.';

  @override
  String get queueUnavailable => 'Очередь не найдена.';

  @override
  String get alreadyJoinedError =>
      'У вас уже есть активный талон в этой очереди.';

  @override
  String get loginInvalidCredentials => 'Неверный номер телефона или пароль.';

  @override
  String get loginAccountInactive => 'Учетная запись неактивна.';

  @override
  String get loginPatientOnly =>
      'Это приложение предназначено только для пациентов.';

  @override
  String get registerPhoneExists => 'Этот номер телефона уже зарегистрирован.';

  @override
  String get doctorInactive => 'Врач в настоящее время неактивен.';

  @override
  String unexpectedError(String error) {
    return 'Произошла непредвиденная ошибка: $error';
  }

  @override
  String get scanQrTitle => 'Сканирование QR-кода';

  @override
  String get scanQrInstructions =>
      'Наведите камеру на QR-код в регистратуре клиники';

  @override
  String get cameraPermissionRequired =>
      'Для сканирования QR-кода требуется разрешение на использование камеры.';

  @override
  String get cameraPermissionGrant => 'Предоставить доступ';

  @override
  String get checkInButtonText => 'Подтвердить прибытие по QR';

  @override
  String get checkingInLoading => 'Подтверждение прибытия...';

  @override
  String get checkInSuccessSnackbar =>
      'Вы успешно зарегистрировали прибытие! Ваш статус подтвержден.';

  @override
  String get checkInFailedTitle => 'Не удалось подтвердить прибытие';

  @override
  String get cancelTicketButton => 'Отменить талон';

  @override
  String get cancelConfirmTitle => 'Отменить этот талон?';

  @override
  String get cancelConfirmMessage =>
      'Вы уверены, что хотите отменить талон в очереди? Это действие нельзя отменить.';

  @override
  String get cancelConfirmYes => 'Да, отменить';

  @override
  String get cancelConfirmNo => 'Нет, оставить';

  @override
  String get cancellingTicketLoading => 'Отмена талона...';

  @override
  String get cancelSuccessSnackbar => 'Талон успешно отменен.';

  @override
  String get calledBannerTitle => 'Ваша очередь подошла';

  @override
  String get calledBannerSubtitle => 'Пожалуйста, пройдите в указанный кабинет';

  @override
  String get servingBannerTitle => 'Идет прием';

  @override
  String get servingBannerSubtitle => 'Врач проводит осмотр';

  @override
  String get waitingCheckInPrompt =>
      'Когда прибудете в клинику, отсканируйте QR-код в регистратуре';

  @override
  String get enterCodeManually => 'Ввести код вручную';

  @override
  String get qrCodeInputHint => 'Введите QR-токен';

  @override
  String get submitButton => 'Отправить';

  @override
  String get errorInvalidQrCode => 'Недействительный или просроченный QR-код.';

  @override
  String get errorNoWaitingTicketForClinic =>
      'Для этой клиники не найден активный талон в очереди ожидания.';

  @override
  String get errorTicketAlreadyCheckedIn => 'Этот талон уже зарегистрирован.';

  @override
  String get errorCannotCancelOtherTicket =>
      'Запрещено отменять талон другого пациента.';

  @override
  String get errorOnlyWaitingCalledCancellable =>
      'Отменить можно только ожидающие или вызванные талоны.';

  @override
  String get skippedBannerTitle => 'Ваш талон пропущен';

  @override
  String get skippedBannerSubtitle =>
      'Ваш талон временно отложен. Восстановить его в очереди может только регистратура.';

  @override
  String get fgNotifCalled =>
      'Ваша очередь подошла! Пожалуйста, пройдите в кабинет.';

  @override
  String get fgNotifSkipped =>
      'Ваш талон пропущен. Обратитесь в регистратуру для восстановления.';

  @override
  String get fgNotifRestored => 'Ваш талон восстановлен в очереди.';

  @override
  String get fgNotifMissedTurn =>
      'Ваша очередь прошла, талон перемещен в конец очереди.';

  @override
  String get remainingTimeLabel => 'Осталось времени';

  @override
  String get pausedCountdownBadge => 'Пауза';

  @override
  String get alreadyJoinedSpecializationError =>
      'У вас уже есть активный талон по данной специализации.';

  @override
  String get queuePausedBadge => 'Очередь приостановлена';

  @override
  String get syncConnectionWarning =>
      'Нет связи с сервером. Показаны последние данные, повторное подключение...';
}
