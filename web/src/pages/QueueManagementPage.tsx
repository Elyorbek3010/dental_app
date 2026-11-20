import React, { useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  BellRing,
  CheckCircle,
  CheckCircle2,
  Clock,
  DoorClosed,
  FastForward,
  Layers,
  PauseCircle,
  Phone,
  PlayCircle,
  RotateCcw,
  Search,
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
import { useSmartCallCountdown } from '../hooks/useSmartCallCountdown';
import type { QueueTicket, ReceptionQueueOverview } from '../types/reception';
import { AlertBanner } from '../components/common/AlertBanner';
import { AppButton } from '../components/common/AppButton';
import { ConfirmModal } from '../components/common/ConfirmModal';
import { CountdownRing } from '../components/common/CountdownRing';
import { EmptyState } from '../components/common/EmptyState';
import { LoadingSkeleton } from '../components/common/LoadingSkeleton';
import { StatusBadge } from '../components/common/StatusBadge';
import { WalkInModal } from '../components/common/WalkInModal';

type QueueListTab = 'WAITING' | 'COMPLETED' | 'INACTIVE';

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
  const [searchQuery, setSearchQuery] = useState('');
  const [checkInFilter, setCheckInFilter] = useState<'ALL' | 'CHECKED_IN' | 'NOT_CHECKED_IN'>('ALL');
  const [activeListTab, setActiveListTab] = useState<QueueListTab>('WAITING');
  const [notice, setNotice] = useState<{ type: 'error' | 'success'; message: string } | null>(null);

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

  const parseBackendError = useCallback(
    (err: unknown): string => {
      if (err instanceof Error) {
        const msg = err.message.toLowerCase();
        if (msg.includes('no checked-in patient')) return t.errorNoCheckedInPatient;
        if (msg.includes('active patient') || msg.includes('already has an active')) {
          return t.errorQueueHasActivePatient;
        }
        if (msg.includes('paused')) return t.errorQueuePaused;
        if (msg.includes('inactive')) return t.errorQueueInactive;
        if (msg.includes('only waiting')) return t.errorOnlyWaitingCanBeCalled;
        if (msg.includes('only called')) return t.errorOnlyCalledCanBeServed;
        if (msg.includes('only serving')) return t.errorOnlyServingCanBeCompleted;
        if (msg.includes('already checked in')) return t.errorTicketAlreadyCheckedIn;
        return err.message;
      }
      return t.errorGeneric;
    },
    [t]
  );

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

  const loadTickets = useCallback(
    async (queueId: number, isSilent = false) => {
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
    },
    [parseBackendError]
  );

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

  const servingTicket = tickets.find((tk) => tk.status === 'SERVING');
  const calledTicket = tickets.find((tk) => tk.status === 'CALLED');
  const waitingTickets = tickets
    .filter((tk) => tk.status === 'WAITING')
    .sort((a, b) => a.queue_position - b.queue_position);
  const completedTickets = tickets.filter((tk) => tk.status === 'COMPLETED');
  const inactiveTickets = tickets.filter(
    (tk) => tk.status === 'SKIPPED' || tk.status === 'CANCELLED'
  );

  const filteredWaitingTickets = waitingTickets.filter((ticket) => {
    const isCheckedIn = ticket.checked_in_at !== null;
    if (checkInFilter === 'CHECKED_IN' && !isCheckedIn) return false;
    if (checkInFilter === 'NOT_CHECKED_IN' && isCheckedIn) return false;
    if (!searchQuery.trim()) return true;
    const term = searchQuery.toLowerCase();
    return (
      ticket.patient_name.toLowerCase().includes(term) ||
      (ticket.patient_phone || '').toLowerCase().includes(term) ||
      String(ticket.ticket_number).includes(term)
    );
  });

  // Operational Actions (existing API + rules preserved)
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
      <div className="max-w-7xl mx-auto">
        <LoadingSkeleton cards={2} rows={5} />
      </div>
    );
  }

  if (todayQueues.length === 0) {
    return (
      <div className="max-w-7xl mx-auto">
        <EmptyState title={t.noQueuesToday} description={t.noQueuesHint} />
      </div>
    );
  }

  return (
    <div className="space-y-3 lg:space-y-0 lg:h-[calc(100vh-6rem)] lg:flex lg:flex-col lg:gap-2.5 max-w-7xl mx-auto animate-dental-in">
      {/* Compact Top Control Bar: Doctor Tabs + Status + Walk-in / Pause */}
      <div className="shrink-0 flex flex-col md:flex-row md:items-center md:justify-between gap-2 rounded-2xl border border-[#DCE9EE] bg-white px-3.5 py-2 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
        <div className="flex items-center gap-2 overflow-x-auto pb-1 lg:pb-0 min-w-0">
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
                className={`flex items-center gap-2 px-3.5 py-1.5 rounded-xl text-xs font-semibold whitespace-nowrap transition-all cursor-pointer ${
                  isSelected
                    ? 'bg-[#0D9488] text-white shadow-xs dark:bg-[#14B8A6] dark:text-[#07131D]'
                    : 'bg-[#F5FAFB] text-[#14283F] border border-[#DCE9EE] hover:bg-[#EDF6F8] dark:bg-[#0B1728]/60 dark:text-[#F1F5F9] dark:border-[#253F5B] dark:hover:bg-[#1A3047]'
                }`}
              >
                <span>{q.doctor.full_name}</span>
                <span
                  className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold tabular-nums ${
                    isSelected
                      ? 'bg-white/20 text-white dark:bg-[#0B1728]/25 dark:text-[#07131D]'
                      : 'bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]'
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

        <div className="flex flex-wrap items-center gap-2 shrink-0">
          {activeQueue && (
            <>
              <span className="inline-flex items-center gap-1.5 rounded-lg bg-[#EDF6F8] px-2.5 py-1 text-xs font-semibold text-[#14283F] dark:bg-[#1A3047] dark:text-[#F1F5F9]">
                <DoorClosed className="h-3.5 w-3.5 text-[#0284C7] dark:text-[#38BDF8]" />
                {activeQueue.doctor.room_number ? `${t.room} ${activeQueue.doctor.room_number}` : '—'}
              </span>
              <StatusBadge
                status={activeQueue.is_paused ? 'PAUSED' : 'ACTIVE'}
                size="sm"
              />
              <button
                type="button"
                onClick={handlePauseResumeQueue}
                disabled={actionInProgress !== null}
                className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-semibold shadow-2xs transition-colors cursor-pointer disabled:opacity-50 ${
                  activeQueue.is_paused
                    ? 'border-emerald-200 bg-emerald-50 text-emerald-700 hover:bg-emerald-100 dark:border-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300'
                    : 'border-amber-200 bg-amber-50 text-amber-800 hover:bg-amber-100 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-300'
                }`}
              >
                {activeQueue.is_paused ? (
                  <>
                    <PlayCircle className="h-3.5 w-3.5" />
                    {t.resumeQueue}
                  </>
                ) : (
                  <>
                    <PauseCircle className="h-3.5 w-3.5" />
                    {t.pauseQueue}
                  </>
                )}
              </button>
            </>
          )}

          <AppButton
            variant="secondary"
            size="sm"
            disabled={actionInProgress !== null || activeQueue?.is_paused}
            onClick={() => setIsWalkInOpen(true)}
            icon={<UserPlus className="h-3.5 w-3.5 text-[#0284C7] dark:text-[#38BDF8]" />}
          >
            {t.addWalkIn}
          </AppButton>
        </div>
      </div>

      {notice && (
        <AlertBanner
          type={notice.type}
          message={notice.message}
          onClose={() => setNotice(null)}
        />
      )}

      {/* Primary Two-Column Operational Cockpit */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-3.5 items-stretch lg:flex-1 lg:min-h-0">
        {/* Left: Current Patient Focus Stage (CALLED + SERVING) */}
        <div className="lg:col-span-6 flex flex-col gap-2.5 lg:min-h-0 lg:overflow-y-auto">
          {/* Currently CALLED Card */}
          <div
            className={`rounded-2xl border p-4 shadow-2xs flex flex-col justify-between transition-all ${
              calledTicket
                ? 'border-amber-300/80 bg-white dark:border-amber-700/55 dark:bg-[#12243A]'
                : 'border-[#DCE9EE] bg-white dark:border-[#253F5B] dark:bg-[#12243A]'
            }`}
          >
            <div>
              <div className="flex items-center justify-between gap-2 pb-2.5 border-b border-[#DCE9EE] dark:border-[#253F5B]">
                <div className="flex items-center gap-2">
                  <BellRing
                    className={`h-4 w-4 ${
                      calledTicket ? 'text-amber-500' : 'text-[#64748B] dark:text-[#A5B4C7]'
                    }`}
                  />
                  <span className="text-xs font-bold uppercase tracking-wider text-[#14283F] dark:text-[#F1F5F9]">
                    {t.currentlyCalled}
                  </span>
                </div>
                {calledTicket && <StatusBadge status="CALLED" size="sm" />}
              </div>

              {calledTicket ? (
                <div className="mt-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div className="min-w-0 space-y-1">
                    <div className="flex items-baseline gap-2.5">
                      <span className="text-3xl sm:text-4xl font-black font-mono tabular-nums text-[#14283F] dark:text-[#F1F5F9] tracking-tight">
                        #{String(calledTicket.ticket_number).padStart(3, '0')}
                      </span>
                      <span
                        className="text-base font-bold text-[#14283F] dark:text-[#F1F5F9] truncate"
                        title={calledTicket.patient_name}
                      >
                        {calledTicket.patient_name}
                      </span>
                    </div>

                    <div className="flex flex-wrap items-center gap-2 text-xs text-[#64748B] dark:text-[#A5B4C7]">
                      {activeQueue && (
                        <span className="font-semibold text-[#0F766E] dark:text-[#2DD4BF]">
                          {activeQueue.specialization.name} • {activeQueue.doctor.full_name}
                        </span>
                      )}
                      {calledTicket.patient_phone && (
                        <span className="inline-flex items-center gap-1">
                          <Phone className="h-3 w-3" />
                          {calledTicket.patient_phone}
                        </span>
                      )}
                      <span className="rounded-md bg-[#EDF6F8] px-2 py-0.5 text-[11px] font-semibold text-[#14283F] dark:bg-[#1A3047] dark:text-[#F1F5F9]">
                        {calledTicket.source === 'WALK_IN' ? t.sourceWalkIn : t.sourceOnline}
                      </span>
                    </div>
                  </div>

                  {remainingSeconds !== null && (
                    <div className="shrink-0">
                      <CountdownRing
                        remainingSeconds={remainingSeconds}
                        isPaused={activeQueue?.is_paused ?? false}
                        label={t.remainingTimeLabel}
                        pausedLabel={t.pausedCountdownBadge}
                        size="md"
                      />
                    </div>
                  )}
                </div>
              ) : (
                <div className="py-4 text-center text-[#64748B] dark:text-[#A5B4C7] text-xs">
                  <BellRing className="mx-auto h-5 w-5 opacity-40 mb-1" />
                  {t.noPatientCalled}
                </div>
              )}
            </div>

            {calledTicket && (
              <div className="mt-3 pt-2.5 border-t border-[#DCE9EE] dark:border-[#253F5B] space-y-2">
                <AppButton
                  variant="primary"
                  size="sm"
                  className="w-full"
                  disabled={actionInProgress !== null}
                  onClick={() => handleServe(calledTicket)}
                  icon={<UserCheck className="h-4 w-4" />}
                >
                  {t.servePatient}
                </AppButton>

                <div className="grid grid-cols-3 gap-2">
                  <AppButton
                    variant="secondary"
                    size="xs"
                    disabled={actionInProgress !== null || calledTicket.status === 'CALLED'}
                    title={t.callAgainDisabledHint}
                    onClick={() => handleManualCall(calledTicket)}
                    icon={<BellRing className="h-3.5 w-3.5 text-amber-500" />}
                  >
                    {t.callAgain}
                  </AppButton>
                  <AppButton
                    variant="secondary"
                    size="xs"
                    disabled={actionInProgress !== null}
                    onClick={() => handleSkipPrompt(calledTicket)}
                    icon={<FastForward className="h-3.5 w-3.5" />}
                  >
                    {t.skipPatient}
                  </AppButton>
                  <AppButton
                    variant="ghost"
                    size="xs"
                    disabled={actionInProgress !== null}
                    onClick={() => handleCancelPrompt(calledTicket)}
                    className="text-rose-600 hover:bg-rose-50 dark:text-rose-400 dark:hover:bg-rose-950/40"
                    icon={<XCircle className="h-3.5 w-3.5" />}
                  >
                    {t.cancelTicket}
                  </AppButton>
                </div>
              </div>
            )}
          </div>

          {/* Currently SERVING Compact Card */}
          <div
            className={`rounded-2xl border p-4 shadow-2xs flex flex-col justify-between transition-all ${
              servingTicket
                ? 'border-[#0D9488]/45 bg-[#DDF7F0]/35 dark:border-[#2DD4BF]/35 dark:bg-[#102E35]'
                : 'border-[#DCE9EE] bg-white dark:border-[#253F5B] dark:bg-[#12243A]'
            }`}
          >
            <div className="flex items-center justify-between gap-2 pb-2 border-b border-[#DCE9EE]/80 dark:border-[#253F5B]/80">
              <div className="flex items-center gap-2">
                <UserCheck
                  className={`h-4 w-4 ${
                    servingTicket
                      ? 'text-[#0D9488] dark:text-[#2DD4BF]'
                      : 'text-[#64748B] dark:text-[#A5B4C7]'
                  }`}
                />
                <span className="text-xs font-bold uppercase tracking-wider text-[#14283F] dark:text-[#F1F5F9]">
                  {t.currentlyServing}
                </span>
              </div>
              {servingTicket && <StatusBadge status="SERVING" size="sm" />}
            </div>

            {servingTicket ? (
              <div className="mt-2.5 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex items-baseline gap-2.5">
                    <span className="text-2xl font-black font-mono tabular-nums text-[#0F766E] dark:text-[#2DD4BF]">
                      #{String(servingTicket.ticket_number).padStart(3, '0')}
                    </span>
                    <span
                      className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9] truncate"
                      title={servingTicket.patient_name}
                    >
                      {servingTicket.patient_name}
                    </span>
                  </div>
                  <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-[#64748B] dark:text-[#A5B4C7]">
                    {servingTicket.patient_phone && (
                      <span className="inline-flex items-center gap-1">
                        <Phone className="h-3 w-3" />
                        {servingTicket.patient_phone}
                      </span>
                    )}
                    <span className="rounded-md bg-white/80 px-2 py-0.5 text-[11px] font-semibold text-[#14283F] dark:bg-[#12243A] dark:text-[#F1F5F9]">
                      {servingTicket.source === 'WALK_IN' ? t.sourceWalkIn : t.sourceOnline}
                    </span>
                  </div>
                </div>

                <AppButton
                  variant="primary"
                  size="sm"
                  disabled={actionInProgress !== null}
                  onClick={() => handleComplete(servingTicket)}
                  icon={<CheckCircle className="h-3.5 w-3.5" />}
                >
                  {t.completePatient}
                </AppButton>
              </div>
            ) : (
              <div className="py-3 text-center text-[#64748B] dark:text-[#A5B4C7] text-xs">
                {t.noPatientInService}
              </div>
            )}
          </div>
        </div>

        {/* Right: Tabbed Queue Stream (Waiting / Completed / Skipped) + Pinned Smart Call Next */}
        <div className="lg:col-span-6 rounded-2xl border border-[#DCE9EE] bg-white shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A] flex flex-col overflow-hidden lg:h-full lg:min-h-0">
          {/* Card Header Tabs & Filter */}
          <div className="shrink-0 px-3.5 py-2.5 border-b border-[#DCE9EE] bg-[#F5FAFB]/70 dark:border-[#253F5B] dark:bg-[#0B1728]/40 space-y-2">
            <div className="flex items-center justify-between gap-2 overflow-x-auto">
              <div
                role="tablist"
                aria-label={t.waitingPatients}
                className="inline-flex items-center rounded-xl border border-[#DCE9EE] bg-white p-0.5 dark:border-[#253F5B] dark:bg-[#12243A] whitespace-nowrap"
              >
                <button
                  type="button"
                  role="tab"
                  aria-selected={activeListTab === 'WAITING'}
                  onClick={() => setActiveListTab('WAITING')}
                  className={`inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-[11px] font-semibold transition-colors cursor-pointer whitespace-nowrap ${
                    activeListTab === 'WAITING'
                      ? 'bg-[#0D9488] text-white dark:bg-[#14B8A6] dark:text-[#07131D]'
                      : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                  }`}
                >
                  <span>{t.waitingCount}</span>
                  <span className="tabular-nums opacity-85">({waitingTickets.length})</span>
                </button>

                <button
                  type="button"
                  role="tab"
                  aria-selected={activeListTab === 'COMPLETED'}
                  onClick={() => setActiveListTab('COMPLETED')}
                  className={`inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-[11px] font-semibold transition-colors cursor-pointer whitespace-nowrap ${
                    activeListTab === 'COMPLETED'
                      ? 'bg-[#0D9488] text-white dark:bg-[#14B8A6] dark:text-[#07131D]'
                      : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                  }`}
                >
                  <span>{t.completedCount}</span>
                  <span className="tabular-nums opacity-85">({completedTickets.length})</span>
                </button>

                <button
                  type="button"
                  role="tab"
                  aria-selected={activeListTab === 'INACTIVE'}
                  onClick={() => setActiveListTab('INACTIVE')}
                  className={`inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-[11px] font-semibold transition-colors cursor-pointer whitespace-nowrap ${
                    activeListTab === 'INACTIVE'
                      ? 'bg-[#0D9488] text-white dark:bg-[#14B8A6] dark:text-[#07131D]'
                      : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                  }`}
                >
                  <span>{t.inactivePatients}</span>
                  <span className="tabular-nums opacity-85">({inactiveTickets.length})</span>
                </button>
              </div>
            </div>

            {activeListTab === 'WAITING' && (
              <div className="flex flex-col sm:flex-row gap-2">
                <div className="relative flex-1">
                  <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder={t.searchPatientsPlaceholder}
                    className="w-full rounded-xl border border-[#DCE9EE] bg-white py-1.5 pl-8 pr-3 text-xs text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                  />
                </div>

                <select
                  value={checkInFilter}
                  onChange={(e) =>
                    setCheckInFilter(e.target.value as 'ALL' | 'CHECKED_IN' | 'NOT_CHECKED_IN')
                  }
                  aria-label={t.checkInState}
                  className="rounded-xl border border-[#DCE9EE] bg-white px-3 py-1.5 text-xs font-semibold text-[#14283F] focus:border-[#0D9488] focus:outline-hidden dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:[&_option]:bg-[#12243A] dark:[&_option]:text-[#F1F5F9]"
                >
                  <option value="ALL">{t.allStatuses}</option>
                  <option value="CHECKED_IN">{t.checkedIn}</option>
                  <option value="NOT_CHECKED_IN">{t.notCheckedIn}</option>
                </select>
              </div>
            )}
          </div>

          {/* Independently Scrollable List Area (Patients only) */}
          <div className="flex-1 min-h-0 p-3 space-y-2 max-h-[380px] lg:max-h-none overflow-y-auto">
            {isLoadingTickets ? (
              <LoadingSkeleton rows={4} />
            ) : activeListTab === 'WAITING' ? (
              filteredWaitingTickets.length === 0 ? (
                <EmptyState title={t.noWaitingPatients} compact />
              ) : (
                filteredWaitingTickets.map((ticket, index) => {
                  const isCheckedIn = ticket.checked_in_at !== null;
                  const isBusy =
                    actionInProgress === `call-${ticket.id}` ||
                    actionInProgress === `checkin-${ticket.id}` ||
                    actionInProgress === `missturn-${ticket.id}` ||
                    actionInProgress === `skip-${ticket.id}` ||
                    actionInProgress === `cancel-${ticket.id}`;

                  return (
                    <div
                      key={ticket.id}
                      className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 rounded-xl border border-[#DCE9EE] bg-[#F5FAFB]/55 px-3 py-2.5 hover:border-[#0D9488]/40 hover:bg-white transition-colors dark:border-[#253F5B] dark:bg-[#0B1728]/50 dark:hover:border-[#2DD4BF]/40 dark:hover:bg-[#1A3047]/65"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <div className="flex h-9 min-w-13 shrink-0 items-center justify-center rounded-xl bg-[#DDF7F0] px-2 font-mono text-xs font-black tabular-nums text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
                          #{String(ticket.ticket_number).padStart(3, '0')}
                        </div>

                        <div className="min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <span
                              className="text-xs sm:text-sm font-bold text-[#14283F] dark:text-[#F1F5F9] truncate"
                              title={ticket.patient_name}
                            >
                              {ticket.patient_name}
                            </span>
                            <span className="text-[10px] font-bold text-[#64748B] dark:text-[#A5B4C7] tabular-nums">
                              #{index + 1}
                            </span>
                            {ticket.missed_turns > 0 && (
                              <span className="rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-bold text-amber-800 dark:bg-amber-950 dark:text-amber-300">
                                ↻ {ticket.missed_turns}
                              </span>
                            )}
                          </div>

                          <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-[#64748B] dark:text-[#A5B4C7] truncate">
                            {isCheckedIn ? (
                              <span className="inline-flex items-center gap-1 font-semibold text-emerald-700 dark:text-emerald-300 shrink-0">
                                <CheckCircle2 className="h-3 w-3" />
                                {t.checkedIn}
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1 text-amber-700 dark:text-amber-300 shrink-0">
                                <Clock className="h-3 w-3" />
                                {t.notCheckedIn}
                              </span>
                            )}
                            <span className="shrink-0">• {ticket.source === 'WALK_IN' ? t.sourceWalkIn : t.sourceOnline}</span>
                            {ticket.patient_phone && <span className="hidden sm:inline tabular-nums truncate">• {ticket.patient_phone}</span>}
                          </div>
                        </div>
                      </div>

                      <div className="flex flex-wrap items-center justify-end gap-1.5 shrink-0">
                        {isCheckedIn && (
                          <span className="rounded-lg bg-emerald-50 px-2 py-1 text-[11px] font-bold text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300">
                            {t.patientReadyBadge}
                          </span>
                        )}

                        <AppButton
                          variant="blue"
                          size="xs"
                          title={t.manualCall}
                          disabled={
                            isBusy ||
                            actionInProgress !== null ||
                            activeQueue?.is_paused ||
                            !!calledTicket ||
                            !!servingTicket
                          }
                          onClick={() => handleManualCall(ticket)}
                          icon={<BellRing className="h-3.5 w-3.5" />}
                        >
                          {t.manualCall}
                        </AppButton>

                        {!isCheckedIn && ticket.source === 'ONLINE' && (
                          <AppButton
                            variant="secondary"
                            size="xs"
                            title={t.manualCheckIn}
                            disabled={isBusy || actionInProgress !== null}
                            onClick={() => handleManualCheckIn(ticket)}
                            icon={<CheckCircle className="h-3.5 w-3.5 text-emerald-600 dark:text-emerald-400" />}
                          />
                        )}

                        {!isCheckedIn && (
                          <AppButton
                            variant="secondary"
                            size="xs"
                            title={t.missTurn}
                            disabled={isBusy || actionInProgress !== null}
                            onClick={() => handleMissTurnPrompt(ticket)}
                            icon={<FastForward className="h-3.5 w-3.5 text-amber-500" />}
                          />
                        )}

                        <button
                          type="button"
                          title={t.skipPatient}
                          onClick={() => handleSkipPrompt(ticket)}
                          disabled={isBusy || actionInProgress !== null}
                          className="inline-flex items-center rounded-lg p-1.5 text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:bg-[#1A3047] dark:hover:text-[#F1F5F9] disabled:opacity-40 cursor-pointer"
                        >
                          <FastForward className="h-4 w-4" />
                        </button>

                        <button
                          type="button"
                          title={t.cancelTicket}
                          onClick={() => handleCancelPrompt(ticket)}
                          disabled={isBusy || actionInProgress !== null}
                          className="inline-flex items-center rounded-lg p-1.5 text-rose-500 hover:bg-rose-50 hover:text-rose-700 dark:hover:bg-rose-950/40 disabled:opacity-40 cursor-pointer"
                        >
                          <XCircle className="h-4 w-4" />
                        </button>
                      </div>
                    </div>
                  );
                })
              )
            ) : activeListTab === 'COMPLETED' ? (
              completedTickets.length === 0 ? (
                <EmptyState title={t.noData} compact />
              ) : (
                completedTickets.map((ticket) => (
                  <div
                    key={ticket.id}
                    className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-[#DCE9EE] bg-[#F5FAFB]/55 p-3 text-xs dark:border-[#253F5B] dark:bg-[#0B1728]/50"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <span className="font-mono font-black tabular-nums text-[#0F766E] dark:text-[#2DD4BF]">
                        #{String(ticket.ticket_number).padStart(3, '0')}
                      </span>
                      <span className="font-semibold text-[#14283F] dark:text-[#F1F5F9] truncate">
                        {ticket.patient_name}
                      </span>
                      <span className="rounded-md bg-[#E0F2FE] px-2 py-0.5 text-[10px] font-bold uppercase text-[#0369A1] dark:bg-[#10324F] dark:text-[#38BDF8]">
                        {ticket.source === 'ONLINE' ? t.sourceOnline : t.sourceWalkIn}
                      </span>
                    </div>
                    <StatusBadge status={ticket.status} size="sm" />
                  </div>
                ))
              )
            ) : inactiveTickets.length === 0 ? (
              <EmptyState title={t.noData} compact />
            ) : (
              inactiveTickets.map((ticket) => (
                <div
                  key={ticket.id}
                  className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-[#DCE9EE] bg-[#F5FAFB]/55 p-3 text-xs dark:border-[#253F5B] dark:bg-[#0B1728]/50"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <span className="font-mono font-black tabular-nums text-[#64748B] dark:text-[#A5B4C7]">
                      #{String(ticket.ticket_number).padStart(3, '0')}
                    </span>
                    <span className="font-semibold text-[#14283F] dark:text-[#F1F5F9] truncate">
                      {ticket.patient_name}
                    </span>
                    <StatusBadge status={ticket.status} size="sm" />
                  </div>

                  {ticket.status === 'SKIPPED' && (
                    <AppButton
                      variant="secondary"
                      size="xs"
                      disabled={actionInProgress !== null}
                      onClick={() => handleRestore(ticket)}
                      icon={<RotateCcw className="h-3.5 w-3.5 text-[#0D9488] dark:text-[#2DD4BF]" />}
                    >
                      {t.restorePatient}
                    </AppButton>
                  )}
                </div>
              ))
            )}
          </div>

          {/* Pinned Bottom Primary CTA: Smart Call Next */}
          <div className="shrink-0 p-3 border-t border-[#DCE9EE] bg-[#F5FAFB]/80 dark:border-[#253F5B] dark:bg-[#0B1728]/60">
            <AppButton
              variant="primary"
              size="md"
              className="w-full"
              loading={actionInProgress === 'smart-call'}
              disabled={
                actionInProgress !== null ||
                activeQueue?.is_paused ||
                waitingTickets.length === 0 ||
                !!calledTicket ||
                !!servingTicket
              }
              onClick={handleSmartCall}
              icon={<Sparkles className="h-4 w-4" />}
            >
              {actionInProgress === 'smart-call' ? t.smartCalling : t.smartCall}
            </AppButton>
          </div>
        </div>
      </div>

      {/* Bottom Compact 4-Card KPI Strip (Image 1 Style) */}
      <div className="shrink-0 grid grid-cols-2 lg:grid-cols-4 gap-2.5">
        <div className="flex items-center gap-3 rounded-2xl border border-[#DCE9EE] bg-white px-3.5 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-[#EDF6F8] text-[#14283F] dark:bg-[#1A3047] dark:text-[#F1F5F9]">
            <Layers className="h-4 w-4" />
          </div>
          <div>
            <p className="text-base font-black tabular-nums leading-tight text-[#14283F] dark:text-[#F1F5F9]">
              {tickets.length}
            </p>
            <p className="text-[11px] font-medium text-[#64748B] dark:text-[#A5B4C7]">
              {t.adminKpiTotalTickets}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3 rounded-2xl border border-[#DCE9EE] bg-white px-3.5 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-[#E0F2FE] text-[#0369A1] dark:bg-[#10324F] dark:text-[#38BDF8]">
            <Clock className="h-4 w-4" />
          </div>
          <div>
            <p className="text-base font-black tabular-nums leading-tight text-[#14283F] dark:text-[#F1F5F9]">
              {waitingTickets.length}
            </p>
            <p className="text-[11px] font-medium text-[#64748B] dark:text-[#A5B4C7]">
              {t.waitingCount}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3 rounded-2xl border border-[#DCE9EE] bg-white px-3.5 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
            <Users className="h-4 w-4" />
          </div>
          <div>
            <p className="text-base font-black tabular-nums leading-tight text-[#14283F] dark:text-[#F1F5F9]">
              {servingTicket ? 1 : 0}
            </p>
            <p className="text-[11px] font-medium text-[#64748B] dark:text-[#A5B4C7]">
              {t.servingCount}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3 rounded-2xl border border-[#DCE9EE] bg-white px-3.5 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-emerald-50 text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300">
            <CheckCircle2 className="h-4 w-4" />
          </div>
          <div>
            <p className="text-base font-black tabular-nums leading-tight text-[#14283F] dark:text-[#F1F5F9]">
              {completedTickets.length}
            </p>
            <p className="text-[11px] font-medium text-[#64748B] dark:text-[#A5B4C7]">
              {t.completedCount}
            </p>
          </div>
        </div>
      </div>

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
