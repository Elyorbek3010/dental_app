export type Language = 'uz' | 'ru' | 'en';

export interface TranslationDictionary {
  // Navigation & Common
  appTitle: string;
  receptionPortal: string;
  dashboard: string;
  todayQueues: string;
  queueManagement: string;
  logout: string;
  logoutConfirmTitle: string;
  logoutConfirmMessage: string;
  cancel: string;
  confirm: string;
  refresh: string;
  loading: string;
  error: string;
  success: string;
  connected: string;
  reconnecting: string;
  live: string;
  allDoctors: string;
  noData: string;

  // Authentication
  loginTitle: string;
  loginSubtitle: string;
  phoneLabel: string;
  phonePlaceholder: string;
  passwordLabel: string;
  passwordPlaceholder: string;
  loginButton: string;
  loggingIn: string;
  loginErrorInvalid: string;
  loginErrorPatientDenied: string;
  loginErrorInactive: string;
  loginErrorNetwork: string;
  sessionExpired: string;

  // Header & Roles
  roleReceptionist: string;
  roleAdmin: string;
  clinicLabel: string;
  unassignedClinic: string;

  // Queue States
  queueStateNotOpen: string;
  queueStateActive: string;
  queueStatePaused: string;
  openQueue: string;
  openingQueue: string;
  openQueueSuccess: string;
  openQueueAlreadyExists: string;
  pauseQueue: string;
  resumeQueue: string;
  pauseQueueConfirmTitle: string;
  pauseQueueConfirmMessage: string;
  resumeQueueConfirmTitle: string;
  resumeQueueConfirmMessage: string;

  // Stats & Overview
  totalQueues: string;
  waitingCount: string;
  calledCount: string;
  servingCount: string;
  completedCount: string;
  totalWaiting: string;
  totalCalled: string;
  totalServing: string;
  totalCompleted: string;
  doctorsOverviewTitle: string;
  doctorsOverviewSubtitle: string;

  // Table & Details
  doctor: string;
  specialization: string;
  room: string;
  status: string;
  actions: string;
  manageQueue: string;
  noQueuesToday: string;
  noQueuesHint: string;
  noDoctorsFound: string;

  // Queue Management Screen
  selectQueuePrompt: string;
  currentlyServing: string;
  noPatientInService: string;
  currentlyCalled: string;
  noPatientCalled: string;
  waitingPatients: string;
  noWaitingPatients: string;
  inactivePatients: string;
  smartCall: string;
  smartCalling: string;
  smartCallMode: string;
  smartCallModeAutomatic: string;
  smartCallModeManual: string;
  smartCallModeAutoNotice: string;
  smartCallModeManualNotice: string;
  autoCalledNextSuffix: string;
  manualCall: string;
  addWalkIn: string;
  callAgain: string;
  callAgainDisabledHint: string;
  servePatient: string;
  completePatient: string;
  skipPatient: string;
  restorePatient: string;
  cancelTicket: string;
  manualCheckIn: string;
  missTurn: string;
  ticketNumber: string;
  position: string;
  patientName: string;
  patientPhone: string;
  source: string;
  checkInState: string;
  missedTurnsCount: string;
  checkedIn: string;
  notCheckedIn: string;
  sourceOnline: string;
  sourceWalkIn: string;
  checkInMethodQr: string;
  checkInMethodReception: string;
  checkInMethodWalkIn: string;

  // Ticket Action Confirmations
  cancelTicketConfirmTitle: string;
  cancelTicketConfirmMessage: string;
  skipTicketConfirmTitle: string;
  skipTicketConfirmMessage: string;
  missTurnConfirmTitle: string;
  missTurnConfirmMessage: string;

  // Walk-In Modal
  walkInModalTitle: string;
  walkInModalSubtitle: string;
  fullNameLabel: string;
  fullNamePlaceholder: string;
  fullNameRequired: string;
  phoneOptionalLabel: string;
  addWalkInSubmit: string;
  addingWalkIn: string;
  walkInSuccess: string;

  // Ticket Statuses
  statusWaiting: string;
  statusCalled: string;
  statusServing: string;
  statusCompleted: string;
  statusSkipped: string;
  statusCancelled: string;

  // Backend Error Messages
  errorNoCheckedInPatient: string;
  errorQueueHasActivePatient: string;
  errorQueuePaused: string;
  errorQueueInactive: string;
  errorOnlyWaitingCanBeCalled: string;
  errorOnlyCalledCanBeServed: string;
  errorOnlyServingCanBeCompleted: string;
  errorTicketAlreadyCheckedIn: string;
  errorWalkInAlreadyCheckedIn: string;
  errorTicketNotFound: string;
  errorQueueNotFound: string;
  errorGeneric: string;

  // Admin Navigation & Common
  adminPortal: string;
  adminNavDashboard: string;
  adminNavSpecializations: string;
  adminNavDoctors: string;
  adminNavReceptionists: string;
  adminNavAnalytics: string;
  adminClinicSettings: string;
  adminClinicName: string;
  adminSmartCallTimeoutLabel: string;
  adminSmartCallTimeoutHelp: string;
  adminSmartCallTimeoutInvalid: string;
  adminClinicUpdateSuccess: string;
  remainingTimeLabel: string;
  pausedCountdownBadge: string;
  adminEditClinic: string;
  adminSave: string;
  adminSaving: string;
  adminSearch: string;
  adminFilterAll: string;

  // Admin Specializations
  adminSpecializationsTitle: string;
  adminSpecializationsSubtitle: string;
  adminAddSpecialization: string;
  adminEditSpecialization: string;
  adminSpecNameUz: string;
  adminSpecNameRu: string;
  adminSpecNameEn: string;
  adminSpecNameUzReq: string;
  adminSpecStatus: string;
  adminSpecActive: string;
  adminSpecInactive: string;
  adminSpecActivate: string;
  adminSpecDeactivate: string;
  adminSpecDeactivateConfirmTitle: string;
  adminSpecDeactivateConfirmMsg: string;
  adminSpecActivateConfirmTitle: string;
  adminSpecActivateConfirmMsg: string;
  adminSpecSaveSuccess: string;
  adminSpecEmpty: string;

  // Admin Doctors
  adminDoctorsTitle: string;
  adminDoctorsSubtitle: string;
  adminAddDoctor: string;
  adminEditDoctor: string;
  adminDoctorFullName: string;
  adminDoctorFullNameReq: string;
  adminDoctorSpecSelect: string;
  adminDoctorSpecReq: string;
  adminDoctorRoom: string;
  adminDoctorStatus: string;
  adminDoctorActive: string;
  adminDoctorInactive: string;
  adminDoctorActivate: string;
  adminDoctorDeactivate: string;
  adminDoctorDeactivateConfirmTitle: string;
  adminDoctorDeactivateConfirmMsg: string;
  adminDoctorActivateConfirmTitle: string;
  adminDoctorActivateConfirmMsg: string;
  adminDoctorSaveSuccess: string;
  adminDoctorEmpty: string;

  // Admin Receptionists
  adminReceptionistsTitle: string;
  adminReceptionistsSubtitle: string;
  adminAddReceptionist: string;
  adminEditReceptionist: string;
  adminReceptionistName: string;
  adminReceptionistNameReq: string;
  adminReceptionistPhone: string;
  adminReceptionistPhoneReq: string;
  adminReceptionistPassword: string;
  adminReceptionistPasswordReq: string;
  adminReceptionistPasswordHint: string;
  adminReceptionistResetPassword: string;
  adminReceptionistStatus: string;
  adminReceptionistActive: string;
  adminReceptionistInactive: string;
  adminReceptionistActivate: string;
  adminReceptionistDeactivate: string;
  adminReceptionistDeactivateConfirmTitle: string;
  adminReceptionistDeactivateConfirmMsg: string;
  adminReceptionistActivateConfirmTitle: string;
  adminReceptionistActivateConfirmMsg: string;
  adminReceptionistSaveSuccess: string;
  adminReceptionistEmpty: string;
  adminReceptionistPhoneExists: string;

  // Admin Analytics & Overview
  adminOverviewTitle: string;
  adminOverviewSubtitle: string;
  adminAnalyticsTitle: string;
  adminAnalyticsSubtitle: string;
  adminKpiActiveDoctors: string;
  adminKpiActiveSpecializations: string;
  adminKpiActiveReceptionists: string;
  adminKpiTodayQueues: string;
  adminKpiTotalTickets: string;
  adminKpiWaiting: string;
  adminKpiCalled: string;
  adminKpiServing: string;
  adminKpiCompleted: string;
  adminKpiSkipped: string;
  adminKpiCancelled: string;
  adminTodayDoctorQueues: string;
  adminDoctorQueueStatusOpen: string;
  adminDoctorQueueStatusClosed: string;
  adminNoQueuesToday: string;
  adminProgressTitle: string;
  adminProgressSummaryTemplate: string;
  adminShareSummaryTemplate: string;
  adminNoTicketsIssuedToday: string;
  adminActiveInQueueLabel: string;
  adminSkippedCancelledLabel: string;
  adminFilterOpen: string;
  adminFilterClosed: string;
  adminViewCards: string;
  adminViewTable: string;
  adminSearchDoctorPlaceholder: string;
  adminNoDoctorsMatchFilter: string;
  adminTicketsSuffix: string;
  queueProgressColumn: string;
  patientReadyBadge: string;
  todayShortLabel: string;

  // Theme & UI Controls
  themeLabel: string;
  themeLight: string;
  themeDark: string;
  themeSystem: string;
  showClinicQr: string;
  clinicQrTitle: string;
  clinicQrSubtitle: string;
  clinicQrExpiresIn: string;
  clinicQrExpired: string;
  clinicQrRefresh: string;
  clinicQrEnlarge: string;
  clinicQrReduce: string;
  clinicQrSecurityNote: string;
  searchPatientsPlaceholder: string;
  allStatuses: string;
  skippedCount: string;
  adminCompletionRate: string;

  // Shift Lifecycle Controls & Messages
  shiftStatusOpen: string;
  shiftStatusClosing: string;
  shiftStatusFinished: string;
  startShift: string;
  stopNewTickets: string;
  reopenAdmissions: string;
  finishShift: string;
  finishShiftConfirmTitle: string;
  finishShiftConfirmMessage: string;
  finishShiftSkippedWarning: string;
  finishShiftBlockedHint: string;
  shiftStopAdmissionsNotice: string;
  shiftReopenAdmissionsNotice: string;
  shiftFinishedNotice: string;
  shiftClosingBannerHint: string;
  shiftPausedBannerHint: string;
  shiftStartedAtLabel: string;
  errorClosingNewPatients: string;

  // Admin Doctor Performance & History
  adminNavDoctorHistory: string;
  adminDoctorHistoryTitle: string;
  adminDoctorHistorySubtitle: string;
  completedTodayLabel: string;
  completedWeekLabel: string;
  completedMonthLabel: string;
  completedYearLabel: string;
  completedAllTimeLabel: string;
  completedSelectedRangeLabel: string;
  periodToday: string;
  periodWeek: string;
  periodMonth: string;
  periodYear: string;
  periodCustom: string;
  periodAllTime: string;
  exportCsv: string;
  exportingCsv: string;
  doctorPerformanceSummaryTitle: string;
  shiftHistoryTitle: string;
  shiftDurationLabel: string;
  totalIssuedLabel: string;
  avgShiftDurationLabel: string;
  currentShiftLabel: string;
  noShiftActive: string;
  legacyNoTimestampNote: string;
  legacyDurationLabel: string;
  filterBySpecialization: string;
  allSpecializations: string;
  dateFromLabel: string;
  dateToLabel: string;
  noShiftHistoryFound: string;
  shiftStartTimeCol: string;
  shiftEndTimeCol: string;
}
