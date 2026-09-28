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
  addWalkIn: string;
  callAgain: string;
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
}
