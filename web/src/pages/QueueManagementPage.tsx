import React, { useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  BellRing,
  CheckCircle,
  CheckCircle2,
  Clock,
  DoorClosed,
  FastForward,
  PauseCircle,
  Phone,
  PlayCircle,
  RotateCcw,
  Sparkles,
  UserCheck,
  UserPlus,
  Users,
  XCircle,
} from 'lucide-react';
import {
  addWalkInPatient,
  callNextPatient,
  callPatient,
  cancelPatient,
  completePatient,
  fetchQueueTickets,
  fetchReceptionTodayQueues,
  manualCheckInPatient,
  missTurnPatient,
  pauseQueue,
  resumeQueue,
  restorePatient,
  servePatient,
  skipPatient,
} from '../api/reception';
import { useI18n } from '../i18n/useI18n';
import { formatCountdownMmSs, useSmartCallCountdown } from '../hooks/useSmartCallCountdown';
import type { QueueTicket, ReceptionQueueOverview } from '../types/reception';
import { StatusBadge } from '../components/common/StatusBadge';
import { ConfirmModal } from '../components/common/ConfirmModal';
import { WalkInModal } from '../components/common/WalkInModal';
import { AlertBanner } from '../components/common/AlertBanner';

export const QueueManagementPage: React.FC = () => {
  const { t, language } = useI18n();
  const [searchParams, setSearchParams] = useSearchParams();
  const queueIdParam = searchParams.get('queueId');

  const [todayQueues, setTodayQueues] = useState<ReceptionQueueOverview[]>([]);
  const [selectedQueueId, setSelectedQueueId] = useState<number | null>(() => {
    return queueIdParam ? parseInt(queueIdParam, 10) : null;
  });

  const [tickets, setTickets] = useState<QueueTicket[]>([]);
  const [ticketsFetchedAtMs, setTicketsFetchedAtMs] = useState<number | null>(null);
  const [isLoadingQueues, setIsLoadingQueues] = useState<boolean>(true);
  const [isLoadingTickets, setIsLoadingTickets] = useState<boolean>(false);
  const [actionInProgress, setActionInProgress] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ type: 'error' | 'success'; message: string } | null>(null);

  // Modals state
  const [isWalkInOpen, setIsWalkInOpen] = useState(false);
  const [walkInError, setWalkInError] = useState<string | null>(null);
  const [confirmModalState, setConfirmModalState] = useState<{
    isOpen: boolean;
    title: string;
    message: string;
    confirmLabel?: string;
    isDestructive?: boolean;
    onConfirm: () => Promise<void>;
  }>({
    isOpen: false,
    title: '',
    message: '',
    onConfirm: async () => {},
  });

  const currentActiveQueue = todayQueues.find((q) => q.queue_id === selectedQueueId);
  const currentCalledTicket = tickets.find((tk) => tk.status === 'CALLED');
  const remainingSeconds = useSmartCallCountdown({
    callDeadlineAt: currentCalledTicket?.call_deadline_at,
    pausedRemainingSeconds: currentCalledTicket?.paused_remaining_seconds,
    serverTime: currentCalledTicket?.server_time,
    fetchedAtMs: ticketsFetchedAtMs,
    isPaused: currentActiveQueue?.is_paused ?? false,
  });

  // Decode backend error messages into friendly localized messages
  const parseBackendError = useCallback((err: unknown): string => {
    if (err instanceof Error) {
      const msg = err.message.toLowerCase();
      if (msg.includes('no checked-in patient')) return t.errorNoCheckedInPatient;
      if (msg.includes('active patient') || msg.includes('already has an active')) return t.errorQueueHasActivePatient;
      if (msg.includes('paused')) return t.errorQueuePaused;
      if (msg.includes('inactive')) return t.errorQueueInactive;
      if (msg.includes('only waiting')) return t.errorOnlyWaitingCanBeCalled;
      if (msg.includes('only called')) return t.errorOnlyCalledCanBeServed;
      if (msg.includes('only serving')) return t.errorOnlyServingCanBeCompleted;
      if (msg.includes('already checked in')) return t.errorTicketAlreadyCheckedIn;
      return err.message;
    }
    return t.errorGeneric;
  }, [t]);

  // Load available queues today
  const loadQueuesList = useCallback(async () => {
    try {
      const queues = await fetchReceptionTodayQueues();
      setTodayQueues(queues);

      if (queues.length > 0) {
        if (!selectedQueueId || !queues.some((q) => q.queue_id === selectedQueueId)) {
          const firstQueueId = queues[0].queue_id;
          setSelectedQueueId(firstQueueId);
          setSearchParams({ queueId: String(firstQueueId) }, { replace: true });
        }
      }
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setIsLoadingQueues(false);
    }
  }, [parseBackendError, selectedQueueId, setSearchParams]);

  // Load tickets for the currently selected queue
  const loadTickets = useCallback(async (queueId: number, isSilent = false) => {
    if (!isSilent) setIsLoadingTickets(true);
    try {
      const ticketList = await fetchQueueTickets(queueId);
      setTickets(ticketList);
      setTicketsFetchedAtMs(Date.now());
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      if (!isSilent) setIsLoadingTickets(false);
    }
  }, [parseBackendError]);

  useEffect(() => {
    let isCancelled = false;

    async function init() {
      try {
        const queues = await fetchReceptionTodayQueues();
        if (isCancelled) return;
        setTodayQueues(queues);

        let activeId = selectedQueueId;
        if (queues.length > 0) {
          if (!activeId || !queues.some((q) => q.queue_id === activeId)) {
            activeId = queues[0].queue_id;
            setSelectedQueueId(activeId);
            setSearchParams({ queueId: String(activeId) }, { replace: true });
          }
        }

        if (activeId) {
          const ticketList = await fetchQueueTickets(activeId);
          if (isCancelled) return;
          setTickets(ticketList);
          setTicketsFetchedAtMs(Date.now());
        }
      } catch (err) {
        if (!isCancelled) {
          setNotice({ type: 'error', message: parseBackendError(err) });
        }
      } finally {
        if (!isCancelled) {
          setIsLoadingQueues(false);
        }
      }
    }

    init();

    const handleRefresh = () => {
      loadQueuesList();
      if (selectedQueueId) {
        loadTickets(selectedQueueId, true);
      }
    };

    window.addEventListener('reception:refresh', handleRefresh);
    return () => {
      isCancelled = true;
      window.removeEventListener('reception:refresh', handleRefresh);
    };
  }, [language, parseBackendError, selectedQueueId, setSearchParams, loadQueuesList, loadTickets]);

  const activeQueue = todayQueues.find((q) => q.queue_id === selectedQueueId);

  // Group tickets by lifecycle stage
  const servingTicket = tickets.find((t) => t.status === 'SERVING');
  const calledTicket = tickets.find((t) => t.status === 'CALLED');
  const waitingTickets = tickets
    .filter((t) => t.status === 'WAITING')
    .sort((a, b) => a.queue_position - b.queue_position);
  const completedTickets = tickets.filter((t) => t.status === 'COMPLETED');
  const inactiveTickets = tickets.filter(
    (t) => t.status === 'SKIPPED' || t.status === 'CANCELLED'
  );

  // Actions
  const handleSmartCall = async () => {
    if (!selectedQueueId) return;
    setActionInProgress('smart-call');
    setNotice(null);
    try {
      const called = await callNextPatient(selectedQueueId);
      setNotice({
        type: 'success',
        message: `${t.statusCalled}: #${called.ticket_number} - ${called.patient_name}`,
      });
      await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setActionInProgress(null);
    }
  };

  const handleManualCall = async (ticket: QueueTicket) => {
    if (!selectedQueueId) return;
    setActionInProgress(`call-${ticket.id}`);
    setNotice(null);
    try {
      await callPatient(selectedQueueId, ticket.id);
      setNotice({
        type: 'success',
        message: `${t.statusCalled}: #${ticket.ticket_number} - ${ticket.patient_name}`,
      });
      await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setActionInProgress(null);
    }
  };

  const handleServe = async (ticket: QueueTicket) => {
    if (!selectedQueueId) return;
    setActionInProgress(`serve-${ticket.id}`);
    setNotice(null);
    try {
      await servePatient(selectedQueueId, ticket.id);
      setNotice({
        type: 'success',
        message: `${t.statusServing}: #${ticket.ticket_number} - ${ticket.patient_name}`,
      });
      await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setActionInProgress(null);
    }
  };

  const handleComplete = async (ticket: QueueTicket) => {
    if (!selectedQueueId) return;
    setActionInProgress(`complete-${ticket.id}`);
    setNotice(null);
    try {
      await completePatient(selectedQueueId, ticket.id);
      setNotice({
        type: 'success',
        message: `${t.statusCompleted}: #${ticket.ticket_number} - ${ticket.patient_name}`,
      });
      await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setActionInProgress(null);
    }
  };

  const handleSkipPrompt = (ticket: QueueTicket) => {
    setConfirmModalState({
      isOpen: true,
      title: t.skipTicketConfirmTitle,
      message: `${t.ticketNumber} #${ticket.ticket_number} (${ticket.patient_name}): ${t.skipTicketConfirmMessage}`,
      confirmLabel: t.skipPatient,
      isDestructive: false,
      onConfirm: async () => {
        if (!selectedQueueId) return;
        setActionInProgress(`skip-${ticket.id}`);
        try {
          await skipPatient(selectedQueueId, ticket.id);
          setConfirmModalState((prev) => ({ ...prev, isOpen: false }));
          await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
        } catch (err) {
          setNotice({ type: 'error', message: parseBackendError(err) });
        } finally {
          setActionInProgress(null);
        }
      },
    });
  };

  const handleRestore = async (ticket: QueueTicket) => {
    if (!selectedQueueId) return;
    setActionInProgress(`restore-${ticket.id}`);
    setNotice(null);
    try {
      await restorePatient(selectedQueueId, ticket.id);
      setNotice({
        type: 'success',
        message: `${t.restorePatient}: #${ticket.ticket_number} - ${ticket.patient_name}`,
      });
      await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setActionInProgress(null);
    }
  };

  const handleCancelPrompt = (ticket: QueueTicket) => {
    setConfirmModalState({
      isOpen: true,
      title: t.cancelTicketConfirmTitle,
      message: `${t.ticketNumber} #${ticket.ticket_number} (${ticket.patient_name}): ${t.cancelTicketConfirmMessage}`,
      confirmLabel: t.cancelTicket,
      isDestructive: true,
      onConfirm: async () => {
        if (!selectedQueueId) return;
        setActionInProgress(`cancel-${ticket.id}`);
        try {
          await cancelPatient(selectedQueueId, ticket.id);
          setConfirmModalState((prev) => ({ ...prev, isOpen: false }));
          await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
        } catch (err) {
          setNotice({ type: 'error', message: parseBackendError(err) });
        } finally {
          setActionInProgress(null);
        }
      },
    });
  };

  const handleManualCheckIn = async (ticket: QueueTicket) => {
    if (!selectedQueueId) return;
    setActionInProgress(`checkin-${ticket.id}`);
    setNotice(null);
    try {
      await manualCheckInPatient(selectedQueueId, ticket.id);
      setNotice({
        type: 'success',
        message: `${t.checkedIn}: #${ticket.ticket_number} - ${ticket.patient_name}`,
      });
      await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setActionInProgress(null);
    }
  };

  const handleMissTurnPrompt = (ticket: QueueTicket) => {
    setConfirmModalState({
      isOpen: true,
      title: t.missTurnConfirmTitle,
      message: `${t.ticketNumber} #${ticket.ticket_number} (${ticket.patient_name}): ${t.missTurnConfirmMessage}`,
      confirmLabel: t.missTurn,
      isDestructive: false,
      onConfirm: async () => {
        if (!selectedQueueId) return;
        setActionInProgress(`missturn-${ticket.id}`);
        try {
          await missTurnPatient(selectedQueueId, ticket.id);
          setConfirmModalState((prev) => ({ ...prev, isOpen: false }));
          await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
        } catch (err) {
          setNotice({ type: 'error', message: parseBackendError(err) });
        } finally {
          setActionInProgress(null);
        }
      },
    });
  };

  const handlePauseResumeQueue = async () => {
    if (!activeQueue) return;
    setActionInProgress('toggle-pause');
    setNotice(null);
    try {
      if (activeQueue.is_paused) {
        await resumeQueue(activeQueue.queue_id);
      } else {
        await pauseQueue(activeQueue.queue_id);
      }
      await Promise.all([loadQueuesList(), loadTickets(activeQueue.queue_id, true)]);
    } catch (err) {
      setNotice({ type: 'error', message: parseBackendError(err) });
    } finally {
      setActionInProgress(null);
    }
  };

  const handleAddWalkIn = async (patientName: string, patientPhone?: string) => {
    if (!selectedQueueId) return;
    setWalkInError(null);
    setActionInProgress('add-walk-in');
    try {
      const newTicket = await addWalkInPatient(selectedQueueId, {
        patient_name: patientName,
        patient_phone: patientPhone,
      });
      setNotice({
        type: 'success',
        message: `${t.walkInSuccess}: #${newTicket.ticket_number} - ${newTicket.patient_name}`,
      });
      await Promise.all([loadTickets(selectedQueueId, true), loadQueuesList()]);
    } catch (err) {
      const parsed = parseBackendError(err);
      setWalkInError(parsed);
      throw err;
    } finally {
      setActionInProgress(null);
    }
  };

  if (isLoadingQueues) {
    return (
      <div className="p-16 text-center">
        <div className="inline-block h-8 w-8 animate-spin rounded-full border-3 border-indigo-600 border-t-transparent" />
        <p className="mt-2 text-xs text-zinc-500 dark:text-zinc-400">{t.loading}</p>
      </div>
    );
  }

  if (todayQueues.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-zinc-300 p-12 text-center dark:border-zinc-800 bg-white/50 dark:bg-zinc-900/50">
        <Users className="mx-auto h-12 w-12 text-zinc-400 mb-3" />
        <h3 className="text-base font-bold text-zinc-800 dark:text-zinc-200">
          {t.noQueuesToday}
        </h3>
        <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400 max-w-md mx-auto">
          {t.noQueuesHint}
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-7xl mx-auto font-sans pb-12">
      {/* Top Controls: Queue Selector & Primary Actions */}
      <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
        {/* Doctor Queue Tabs / Dropdown */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1 lg:pb-0">
          {todayQueues.map((q) => {
            const isSelected = q.queue_id === selectedQueueId;
            return (
              <button
                key={q.queue_id}
                type="button"
                onClick={() => {
                  setSelectedQueueId(q.queue_id);
                  setSearchParams({ queueId: String(q.queue_id) }, { replace: true });
                }}
                className={`flex items-center gap-2.5 px-4 py-2 rounded-xl text-xs font-semibold whitespace-nowrap transition-all cursor-pointer ${
                  isSelected
                    ? 'bg-indigo-600 text-white shadow-sm'
                    : 'bg-white text-zinc-700 border border-zinc-200 hover:bg-zinc-50 dark:bg-zinc-800 dark:text-zinc-300 dark:border-zinc-700'
                }`}
              >
                <span>{q.doctor.full_name}</span>
                <span
                  className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold ${
                    isSelected
                      ? 'bg-indigo-700 text-indigo-100'
                      : 'bg-zinc-100 text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300'
                  }`}
                >
                  {q.waiting_count}
                </span>
                {q.is_paused && (
                  <span className="h-2 w-2 rounded-full bg-amber-400 animate-pulse" />
                )}
              </button>
            );
          })}
        </div>

        {/* Global Action Buttons */}
        <div className="flex items-center gap-3">
          {/* Pause / Resume Button */}
          {activeQueue && (
            <button
              type="button"
              onClick={handlePauseResumeQueue}
              disabled={actionInProgress !== null}
              className={`inline-flex items-center gap-1.5 rounded-xl border px-3.5 py-2 text-xs font-semibold shadow-2xs transition-colors cursor-pointer disabled:opacity-50 ${
                activeQueue.is_paused
                  ? 'border-emerald-200 bg-emerald-50 text-emerald-700 hover:bg-emerald-100 dark:border-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300'
                  : 'border-amber-200 bg-amber-50 text-amber-700 hover:bg-amber-100 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-300'
              }`}
            >
              {activeQueue.is_paused ? (
                <>
                  <PlayCircle className="h-4 w-4" />
                  {t.resumeQueue}
                </>
              ) : (
                <>
                  <PauseCircle className="h-4 w-4" />
                  {t.pauseQueue}
                </>
              )}
            </button>
          )}

          {/* Add Walk-In Patient */}
          <button
            type="button"
            onClick={() => setIsWalkInOpen(true)}
            disabled={actionInProgress !== null || activeQueue?.is_paused}
            className="inline-flex items-center gap-1.5 rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-xs font-semibold text-zinc-700 shadow-2xs hover:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200 dark:hover:bg-zinc-700 disabled:opacity-50 cursor-pointer"
          >
            <UserPlus className="h-4 w-4 text-zinc-500" />
            {t.addWalkIn}
          </button>

          {/* Smart CALL Button */}
          <button
            type="button"
            onClick={handleSmartCall}
            disabled={
              actionInProgress !== null ||
              activeQueue?.is_paused ||
              waitingTickets.length === 0 ||
              !!calledTicket ||
              !!servingTicket
            }
            className="inline-flex items-center gap-2 rounded-xl bg-indigo-600 px-4 py-2 text-xs font-bold text-white shadow-md shadow-indigo-500/20 hover:bg-indigo-700 disabled:opacity-50 transition-all cursor-pointer"
          >
            {actionInProgress === 'smart-call' ? (
              <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-white border-t-transparent" />
            ) : (
              <Sparkles className="h-4 w-4" />
            )}
            {actionInProgress === 'smart-call' ? t.smartCalling : t.smartCall}
          </button>
        </div>
      </div>

      {notice && (
        <AlertBanner
          type={notice.type}
          message={notice.message}
          onClose={() => setNotice(null)}
        />
      )}

      {/* Selected Queue Info Bar */}
      {activeQueue && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-zinc-200 bg-white p-4 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-indigo-50 text-indigo-700 dark:bg-indigo-950/60 dark:text-indigo-300 font-bold">
              {activeQueue.doctor.full_name.charAt(0)}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-sm font-bold text-zinc-900 dark:text-zinc-100">
                  {activeQueue.doctor.full_name}
                </h3>
                <StatusBadge
                  status={activeQueue.is_paused ? 'PAUSED' : 'ACTIVE'}
                  size="sm"
                />
              </div>
              <p className="text-xs text-zinc-500 dark:text-zinc-400">
                {activeQueue.specialization.name}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-4 text-xs">
            <span className="inline-flex items-center gap-1.5 rounded-lg bg-zinc-100 px-2.5 py-1 font-medium text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
              <DoorClosed className="h-3.5 w-3.5 text-zinc-400" />
              {activeQueue.doctor.room_number ? `${t.room} ${activeQueue.doctor.room_number}` : '—'}
            </span>
            <span className="text-zinc-500">
              {t.waitingCount}: <b className="text-zinc-900 dark:text-zinc-100">{waitingTickets.length}</b>
            </span>
            <span className="text-zinc-500">
              {t.completedCount}: <b className="text-zinc-900 dark:text-zinc-100">{completedTickets.length}</b>
            </span>
          </div>
        </div>
      )}

      {/* Active Patients Stage (SERVING & CALLED) */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        {/* Currently CALLED Patient */}
        <div
          className={`rounded-2xl border p-5 shadow-2xs transition-all ${
            calledTicket
              ? 'border-amber-300 bg-amber-50/30 dark:border-amber-900/50 dark:bg-amber-950/10'
              : 'border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900'
          }`}
        >
          <div className="flex items-center justify-between border-b border-zinc-100 pb-3 dark:border-zinc-800">
            <div className="flex items-center gap-2">
              <BellRing
                className={`h-4 w-4 ${
                  calledTicket ? 'text-amber-500 animate-bounce' : 'text-zinc-400'
                }`}
              />
              <span className="text-xs font-bold uppercase tracking-wider text-zinc-700 dark:text-zinc-300">
                {t.currentlyCalled}
              </span>
            </div>
            {calledTicket && (
              <div className="flex items-center gap-2">
                {remainingSeconds !== null && (
                  <span
                    className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-mono font-bold tabular-nums border ${
                      activeQueue?.is_paused
                        ? 'border-amber-300 bg-amber-100/80 text-amber-800 dark:border-amber-800 dark:bg-amber-950/60 dark:text-amber-300'
                        : remainingSeconds <= 15
                          ? 'border-rose-300 bg-rose-50 text-rose-700 dark:border-rose-800 dark:bg-rose-950/50 dark:text-rose-300'
                          : 'border-amber-300 bg-white text-amber-700 dark:border-amber-800 dark:bg-zinc-800 dark:text-amber-300'
                    }`}
                  >
                    <Clock className="h-3.5 w-3.5" />
                    <span>{formatCountdownMmSs(remainingSeconds)}</span>
                    {activeQueue?.is_paused && (
                      <span className="font-sans text-[10px] uppercase tracking-wider">
                        ({t.pausedCountdownBadge})
                      </span>
                    )}
                  </span>
                )}
                <StatusBadge status="CALLED" size="sm" />
              </div>
            )}
          </div>

          {calledTicket ? (
            <div className="mt-4 flex flex-col justify-between h-[calc(100%-2.5rem)]">
              <div>
                <div className="flex items-baseline gap-3">
                  <span className="text-3xl font-black text-amber-600 dark:text-amber-400 tracking-tight">
                    #{calledTicket.ticket_number}
                  </span>
                  <span className="text-base font-bold text-zinc-900 dark:text-zinc-100">
                    {calledTicket.patient_name}
                  </span>
                </div>

                <div className="mt-2 flex flex-wrap items-center gap-3 text-xs text-zinc-500">
                  {calledTicket.patient_phone && (
                    <span className="inline-flex items-center gap-1">
                      <Phone className="h-3.5 w-3.5 text-zinc-400" />
                      {calledTicket.patient_phone}
                    </span>
                  )}
                  <span>
                    {calledTicket.source === 'WALK_IN' ? t.sourceWalkIn : t.sourceOnline}
                  </span>
                </div>
              </div>

              {/* CALLED Actions */}
              <div className="mt-6 pt-3 border-t border-amber-200/50 dark:border-amber-900/30 space-y-2">
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    onClick={() => handleServe(calledTicket)}
                    disabled={actionInProgress !== null}
                    className="inline-flex items-center gap-1.5 rounded-xl bg-emerald-600 px-3.5 py-1.5 text-xs font-bold text-white shadow-xs hover:bg-emerald-700 disabled:opacity-50 transition-colors cursor-pointer"
                  >
                    <UserCheck className="h-3.5 w-3.5" />
                    {t.servePatient}
                  </button>

                  <button
                    type="button"
                    onClick={() => handleManualCall(calledTicket)}
                    disabled={actionInProgress !== null || calledTicket.status === 'CALLED'}
                    title={t.callAgainDisabledHint}
                    className="inline-flex items-center gap-1.5 rounded-xl border border-amber-300 bg-white px-3 py-1.5 text-xs font-semibold text-amber-800 hover:bg-amber-50 dark:border-amber-800 dark:bg-zinc-800 dark:text-amber-300 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                  >
                    <BellRing className="h-3.5 w-3.5" />
                    {t.callAgain}
                  </button>

                  <button
                    type="button"
                    onClick={() => handleSkipPrompt(calledTicket)}
                    disabled={actionInProgress !== null}
                    className="inline-flex items-center gap-1.5 rounded-xl border border-zinc-200 bg-white px-3 py-1.5 text-xs font-semibold text-zinc-600 hover:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 disabled:opacity-50 transition-colors"
                  >
                    <FastForward className="h-3.5 w-3.5" />
                    {t.skipPatient}
                  </button>

                  <button
                    type="button"
                    onClick={() => handleCancelPrompt(calledTicket)}
                    disabled={actionInProgress !== null}
                    className="inline-flex items-center gap-1.5 rounded-xl border border-rose-200 bg-white px-2.5 py-1.5 text-xs font-semibold text-rose-600 hover:bg-rose-50 dark:border-rose-900/60 dark:bg-zinc-800 dark:text-rose-400 disabled:opacity-50 transition-colors"
                  >
                    <XCircle className="h-3.5 w-3.5" />
                    {t.cancelTicket}
                  </button>
                </div>

                <p className="text-[11px] font-medium text-amber-800/80 dark:text-amber-300/80">
                  {t.callAgainDisabledHint}
                </p>
              </div>
            </div>
          ) : (
            <div className="py-10 text-center text-zinc-400 text-xs">
              <BellRing className="mx-auto h-7 w-7 text-zinc-300 mb-1" />
              {t.noPatientCalled}
            </div>
          )}
        </div>

        {/* Currently SERVING Patient */}
        <div
          className={`rounded-2xl border p-5 shadow-2xs transition-all ${
            servingTicket
              ? 'border-emerald-300 bg-emerald-50/30 dark:border-emerald-900/50 dark:bg-emerald-950/10'
              : 'border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900'
          }`}
        >
          <div className="flex items-center justify-between border-b border-zinc-100 pb-3 dark:border-zinc-800">
            <div className="flex items-center gap-2">
              <UserCheck
                className={`h-4 w-4 ${
                  servingTicket ? 'text-emerald-500' : 'text-zinc-400'
                }`}
              />
              <span className="text-xs font-bold uppercase tracking-wider text-zinc-700 dark:text-zinc-300">
                {t.currentlyServing}
              </span>
            </div>
            {servingTicket && <StatusBadge status="SERVING" size="sm" />}
          </div>

          {servingTicket ? (
            <div className="mt-4 flex flex-col justify-between h-[calc(100%-2.5rem)]">
              <div>
                <div className="flex items-baseline gap-3">
                  <span className="text-3xl font-black text-emerald-600 dark:text-emerald-400 tracking-tight">
                    #{servingTicket.ticket_number}
                  </span>
                  <span className="text-base font-bold text-zinc-900 dark:text-zinc-100">
                    {servingTicket.patient_name}
                  </span>
                </div>

                <div className="mt-2 flex flex-wrap items-center gap-3 text-xs text-zinc-500">
                  {servingTicket.patient_phone && (
                    <span className="inline-flex items-center gap-1">
                      <Phone className="h-3.5 w-3.5 text-zinc-400" />
                      {servingTicket.patient_phone}
                    </span>
                  )}
                  <span>
                    {servingTicket.source === 'WALK_IN' ? t.sourceWalkIn : t.sourceOnline}
                  </span>
                </div>
              </div>

              {/* SERVING Actions */}
              <div className="mt-6 flex items-center gap-3 pt-3 border-t border-emerald-200/50 dark:border-emerald-900/30">
                <button
                  type="button"
                  onClick={() => handleComplete(servingTicket)}
                  disabled={actionInProgress !== null}
                  className="inline-flex items-center gap-1.5 rounded-xl bg-zinc-900 px-4 py-2 text-xs font-bold text-white shadow-xs hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-200 disabled:opacity-50 transition-colors cursor-pointer"
                >
                  <CheckCircle className="h-3.5 w-3.5" />
                  {t.completePatient}
                </button>
              </div>
            </div>
          ) : (
            <div className="py-10 text-center text-zinc-400 text-xs">
              <UserCheck className="mx-auto h-7 w-7 text-zinc-300 mb-1" />
              {t.noPatientInService}
            </div>
          )}
        </div>
      </div>

      {/* Waiting Room Table */}
      <div className="rounded-2xl border border-zinc-200 bg-white shadow-2xs overflow-hidden dark:border-zinc-800 dark:bg-zinc-900">
        <div className="border-b border-zinc-200 bg-zinc-50/50 px-6 py-4 dark:border-zinc-800 dark:bg-zinc-900/50 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-blue-500" />
            <h3 className="text-sm font-bold text-zinc-900 dark:text-zinc-100">
              {t.waitingPatients}
            </h3>
            <span className="rounded-full bg-blue-100 px-2 py-0.5 text-xs font-bold text-blue-700 dark:bg-blue-950 dark:text-blue-300">
              {waitingTickets.length}
            </span>
          </div>
        </div>

        {isLoadingTickets ? (
          <div className="p-12 text-center">
            <div className="inline-block h-7 w-7 animate-spin rounded-full border-2 border-indigo-600 border-t-transparent" />
            <p className="mt-2 text-xs text-zinc-500 dark:text-zinc-400">{t.loading}</p>
          </div>
        ) : waitingTickets.length === 0 ? (
          <div className="p-10 text-center text-zinc-400 text-xs">
            <Clock className="mx-auto h-8 w-8 text-zinc-300 mb-1" />
            {t.noWaitingPatients}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-zinc-200 bg-zinc-50 text-[11px] font-bold uppercase tracking-wider text-zinc-500 dark:border-zinc-800 dark:bg-zinc-800/40 dark:text-zinc-400">
                <tr>
                  <th scope="col" className="px-5 py-3 text-center">
                    {t.position}
                  </th>
                  <th scope="col" className="px-5 py-3">
                    {t.ticketNumber}
                  </th>
                  <th scope="col" className="px-5 py-3">
                    {t.patientName}
                  </th>
                  <th scope="col" className="px-5 py-3">
                    {t.patientPhone}
                  </th>
                  <th scope="col" className="px-5 py-3">
                    {t.source}
                  </th>
                  <th scope="col" className="px-5 py-3">
                    {t.checkInState}
                  </th>
                  <th scope="col" className="px-5 py-3 text-center">
                    {t.missedTurnsCount}
                  </th>
                  <th scope="col" className="px-5 py-3 text-right">
                    {t.actions}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
                {waitingTickets.map((ticket, index) => {
                  const isCheckedIn = ticket.checked_in_at !== null;
                  const isBusy = actionInProgress === `call-${ticket.id}` ||
                    actionInProgress === `checkin-${ticket.id}` ||
                    actionInProgress === `missturn-${ticket.id}` ||
                    actionInProgress === `skip-${ticket.id}` ||
                    actionInProgress === `cancel-${ticket.id}`;

                  return (
                    <tr
                      key={ticket.id}
                      className="hover:bg-zinc-50/80 dark:hover:bg-zinc-800/50 transition-colors"
                    >
                      {/* Position */}
                      <td className="px-5 py-3.5 text-center font-bold text-zinc-400 text-xs whitespace-nowrap">
                        {index + 1}
                      </td>

                      {/* Ticket Number */}
                      <td className="px-5 py-3.5 font-black text-indigo-600 dark:text-indigo-400 whitespace-nowrap">
                        #{ticket.ticket_number}
                      </td>

                      {/* Patient Name */}
                      <td className="px-5 py-3.5 font-semibold text-zinc-900 dark:text-zinc-100 whitespace-nowrap">
                        {ticket.patient_name}
                      </td>

                      {/* Phone */}
                      <td className="px-5 py-3.5 text-zinc-500 whitespace-nowrap">
                        {ticket.patient_phone || '—'}
                      </td>

                      {/* Source */}
                      <td className="px-5 py-3.5 whitespace-nowrap text-xs">
                        {ticket.source === 'WALK_IN' ? (
                          <span className="inline-flex items-center rounded-md bg-purple-50 px-2 py-0.5 font-semibold text-purple-700 dark:bg-purple-950/40 dark:text-purple-300">
                            {t.sourceWalkIn}
                          </span>
                        ) : (
                          <span className="inline-flex items-center rounded-md bg-zinc-100 px-2 py-0.5 font-medium text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                            {t.sourceOnline}
                          </span>
                        )}
                      </td>

                      {/* Check-In State */}
                      <td className="px-5 py-3.5 whitespace-nowrap">
                        {isCheckedIn ? (
                          <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-0.5 text-xs font-semibold text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300">
                            <CheckCircle2 className="h-3 w-3 text-emerald-600" />
                            {t.checkedIn}
                            {ticket.check_in_method && (
                              <span className="text-[10px] text-emerald-500 uppercase">
                                ({ticket.check_in_method})
                              </span>
                            )}
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700 dark:bg-amber-950/40 dark:text-amber-300">
                            <Clock className="h-3 w-3 text-amber-500" />
                            {t.notCheckedIn}
                          </span>
                        )}
                      </td>

                      {/* Missed Turns */}
                      <td className="px-5 py-3.5 text-center whitespace-nowrap">
                        {ticket.missed_turns > 0 ? (
                          <span className="inline-flex items-center justify-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-bold text-amber-800 dark:bg-amber-900 dark:text-amber-200">
                            {ticket.missed_turns}
                          </span>
                        ) : (
                          <span className="text-xs text-zinc-400">0</span>
                        )}
                      </td>

                      {/* Actions */}
                      <td className="px-5 py-3.5 text-right whitespace-nowrap">
                        <div className="flex items-center justify-end gap-1.5">
                          {/* Manual Call */}
                          <button
                            type="button"
                            title={t.manualCall}
                            onClick={() => handleManualCall(ticket)}
                            disabled={
                              isBusy ||
                              actionInProgress !== null ||
                              activeQueue?.is_paused ||
                              !!calledTicket ||
                              !!servingTicket
                            }
                            className="inline-flex items-center gap-1 rounded-lg bg-indigo-50 px-2.5 py-1 text-xs font-bold text-indigo-700 hover:bg-indigo-100 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                          >
                            <BellRing className="h-3.5 w-3.5" />
                            <span>{t.manualCall}</span>
                          </button>

                          {/* Manual Check-in (if online and not yet checked in) */}
                          {!isCheckedIn && ticket.source === 'ONLINE' && (
                            <button
                              type="button"
                              title={t.manualCheckIn}
                              onClick={() => handleManualCheckIn(ticket)}
                              disabled={isBusy || actionInProgress !== null}
                              className="inline-flex items-center gap-1 rounded-lg border border-emerald-200 bg-white px-2 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-50 disabled:opacity-40 transition-colors"
                            >
                              <CheckCircle className="h-3.5 w-3.5" />
                              <span className="hidden xl:inline">{t.manualCheckIn}</span>
                            </button>
                          )}

                          {/* Miss Turn (if waiting & not checked in) */}
                          {!isCheckedIn && (
                            <button
                              type="button"
                              title={t.missTurn}
                              onClick={() => handleMissTurnPrompt(ticket)}
                              disabled={isBusy || actionInProgress !== null}
                              className="inline-flex items-center gap-1 rounded-lg border border-amber-200 bg-white px-2 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-50 disabled:opacity-40 transition-colors"
                            >
                              <FastForward className="h-3.5 w-3.5" />
                              <span className="hidden xl:inline">{t.missTurn}</span>
                            </button>
                          )}

                          {/* Skip */}
                          <button
                            type="button"
                            title={t.skipPatient}
                            onClick={() => handleSkipPrompt(ticket)}
                            disabled={isBusy || actionInProgress !== null}
                            className="inline-flex items-center rounded-lg p-1 text-zinc-500 hover:bg-zinc-100 hover:text-zinc-700 disabled:opacity-40"
                          >
                            <FastForward className="h-4 w-4" />
                          </button>

                          {/* Cancel */}
                          <button
                            type="button"
                            title={t.cancelTicket}
                            onClick={() => handleCancelPrompt(ticket)}
                            disabled={isBusy || actionInProgress !== null}
                            className="inline-flex items-center rounded-lg p-1 text-rose-500 hover:bg-rose-50 hover:text-rose-700 disabled:opacity-40"
                          >
                            <XCircle className="h-4 w-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Completed Patients Section */}
      {completedTickets.length > 0 && (
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
          <div className="flex items-center justify-between border-b border-zinc-100 pb-3 dark:border-zinc-800">
            <div className="flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4 text-emerald-600 dark:text-emerald-400" />
              <span className="font-bold text-xs uppercase tracking-wider text-zinc-700 dark:text-zinc-300">
                {t.completedCount} ({completedTickets.length})
              </span>
            </div>
          </div>

          <div className="mt-3 divide-y divide-zinc-100 dark:divide-zinc-800">
            {completedTickets.map((ticket) => (
              <div
                key={ticket.id}
                className="py-3 flex items-center justify-between gap-3 text-xs"
              >
                <div className="flex items-center gap-3">
                  <span className="font-black text-zinc-500">
                    #{ticket.ticket_number}
                  </span>
                  <span className="font-semibold text-zinc-800 dark:text-zinc-200">
                    {ticket.patient_name}
                  </span>
                  <span
                    className={`rounded-md px-2 py-0.5 text-[10px] font-bold uppercase ${
                      ticket.source === 'ONLINE'
                        ? 'bg-sky-50 text-sky-700 dark:bg-sky-950/50 dark:text-sky-300'
                        : 'bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300'
                    }`}
                  >
                    {ticket.source === 'ONLINE' ? t.sourceOnline : t.sourceWalkIn}
                  </span>
                  <StatusBadge status={ticket.status} size="sm" />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Inactive / Skipped / Cancelled Section */}
      {inactiveTickets.length > 0 && (
        <details className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900 group">
          <summary className="flex items-center justify-between cursor-pointer list-none font-bold text-xs uppercase tracking-wider text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200">
            <span>
              {t.inactivePatients} ({inactiveTickets.length})
            </span>
            <span className="text-xs transition-transform group-open:rotate-180">▼</span>
          </summary>

          <div className="mt-4 divide-y divide-zinc-100 dark:divide-zinc-800">
            {inactiveTickets.map((ticket) => (
              <div
                key={ticket.id}
                className="py-3 flex items-center justify-between gap-3 text-xs"
              >
                <div className="flex items-center gap-3">
                  <span className="font-black text-zinc-400">
                    #{ticket.ticket_number}
                  </span>
                  <span className="font-semibold text-zinc-800 dark:text-zinc-200">
                    {ticket.patient_name}
                  </span>
                  <StatusBadge status={ticket.status} size="sm" />
                </div>

                <div className="flex items-center gap-2">
                  {ticket.status === 'SKIPPED' && (
                    <button
                      type="button"
                      onClick={() => handleRestore(ticket)}
                      disabled={actionInProgress !== null}
                      className="inline-flex items-center gap-1 rounded-lg border border-indigo-200 bg-indigo-50/50 px-2.5 py-1 text-xs font-semibold text-indigo-700 hover:bg-indigo-100 disabled:opacity-50"
                    >
                      <RotateCcw className="h-3.5 w-3.5" />
                      {t.restorePatient}
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </details>
      )}

      {/* Confirmation Modal */}
      <ConfirmModal
        isOpen={confirmModalState.isOpen}
        title={confirmModalState.title}
        message={confirmModalState.message}
        confirmLabel={confirmModalState.confirmLabel}
        isDestructive={confirmModalState.isDestructive}
        isLoading={actionInProgress !== null}
        onConfirm={confirmModalState.onConfirm}
        onCancel={() => setConfirmModalState((prev) => ({ ...prev, isOpen: false }))}
      />

      {/* Walk-In Modal */}
      <WalkInModal
        isOpen={isWalkInOpen}
        isLoading={actionInProgress === 'add-walk-in'}
        error={walkInError}
        onClose={() => {
          setIsWalkInOpen(false);
          setWalkInError(null);
        }}
        onSubmit={handleAddWalkIn}
      />
    </div>
  );
};
