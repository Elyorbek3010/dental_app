import React, { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Activity,
  DoorClosed,
  PauseCircle,
  PlayCircle,
  Search,
  Users,
} from 'lucide-react';
import { fetchReceptionTodayQueues, pauseQueue, resumeQueue } from '../api/reception';
import { useI18n } from '../i18n/useI18n';
import type { ReceptionQueueOverview } from '../types/reception';
import { AlertBanner } from '../components/common/AlertBanner';
import { AppButton } from '../components/common/AppButton';
import { ConfirmModal } from '../components/common/ConfirmModal';
import { EmptyState } from '../components/common/EmptyState';
import { LoadingSkeleton } from '../components/common/LoadingSkeleton';
import { PageHeader } from '../components/common/PageHeader';
import { StatusBadge } from '../components/common/StatusBadge';

export const TodayQueuesPage: React.FC = () => {
  const { t, language } = useI18n();
  const navigate = useNavigate();

  const [queues, setQueues] = useState<ReceptionQueueOverview[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [notice, setNotice] = useState<{ type: 'error' | 'success'; message: string } | null>(null);

  const [targetQueue, setTargetQueue] = useState<ReceptionQueueOverview | null>(null);
  const [isPauseAction, setIsPauseAction] = useState<boolean>(false);
  const [isProcessing, setIsProcessing] = useState<boolean>(false);

  const loadQueues = useCallback(
    async (showLoading = false) => {
      if (showLoading) setIsLoading(true);
      try {
        const data = await fetchReceptionTodayQueues();
        setQueues(data);
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : t.errorGeneric;
        setNotice({ type: 'error', message: msg });
      } finally {
        setIsLoading(false);
      }
    },
    [t.errorGeneric]
  );

  useEffect(() => {
    let isCancelled = false;

    fetchReceptionTodayQueues()
      .then((data) => {
        if (!isCancelled) {
          setQueues(data);
        }
      })
      .catch((err: unknown) => {
        if (!isCancelled) {
          const msg = err instanceof Error ? err.message : t.errorGeneric;
          setNotice({ type: 'error', message: msg });
        }
      })
      .finally(() => {
        if (!isCancelled) {
          setIsLoading(false);
        }
      });

    const handleRefresh = () => {
      loadQueues(false);
    };

    window.addEventListener('reception:refresh', handleRefresh);
    return () => {
      isCancelled = true;
      window.removeEventListener('reception:refresh', handleRefresh);
    };
  }, [language, loadQueues, t.errorGeneric]);

  const handleTogglePause = async () => {
    if (!targetQueue) return;
    setIsProcessing(true);
    try {
      if (isPauseAction) {
        await pauseQueue(targetQueue.queue_id);
      } else {
        await resumeQueue(targetQueue.queue_id);
      }
      setTargetQueue(null);
      await loadQueues();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : t.errorGeneric;
      setNotice({ type: 'error', message: msg });
    } finally {
      setIsProcessing(false);
    }
  };

  const filteredQueues = queues.filter((q) => {
    if (!searchQuery.trim()) return true;
    const term = searchQuery.toLowerCase();
    return (
      q.doctor.full_name.toLowerCase().includes(term) ||
      q.specialization.name.toLowerCase().includes(term) ||
      (q.doctor.room_number || '').toLowerCase().includes(term)
    );
  });

  return (
    <div className="space-y-4 max-w-7xl mx-auto animate-dental-in">
      <PageHeader
        title={t.todayQueues}
        subtitle={t.doctorsOverviewSubtitle}
        icon={<Activity className="h-5 w-5" />}
        actions={
          queues.length > 0 ? (
            <div className="relative w-full sm:w-64">
              <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={t.adminSearch}
                className="w-full rounded-xl border border-[#DCE9EE] bg-white py-2 pl-9 pr-3 text-xs text-[#14283F] placeholder-[#64748B]/70 focus:border-[#0D9488] focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/60"
              />
            </div>
          ) : undefined
        }
      />

      {notice && (
        <AlertBanner
          type={notice.type}
          message={notice.message}
          onClose={() => setNotice(null)}
        />
      )}

      {isLoading ? (
        <LoadingSkeleton cards={3} rows={0} />
      ) : filteredQueues.length === 0 ? (
        <EmptyState
          title={t.noQueuesToday}
          description={t.noQueuesHint}
          action={
            <AppButton variant="primary" size="sm" onClick={() => navigate('/reception')}>
              {t.dashboard}
            </AppButton>
          }
        />
      ) : (
        <div className="lg:max-h-[calc(100vh-12rem)] lg:overflow-y-auto pr-0.5 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-5">
          {filteredQueues.map((q) => (
            <div
              key={q.queue_id}
              className={`flex flex-col justify-between rounded-2xl border bg-white p-5 shadow-2xs transition-all dark:bg-[#12243A] ${
                q.is_paused
                  ? 'border-amber-300/80 dark:border-amber-800/60'
                  : 'border-[#DCE9EE] hover:border-[#0D9488]/50 dark:border-[#253F5B] dark:hover:border-[#2DD4BF]/50'
              }`}
            >
              <div>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <h3
                      className="text-base font-bold text-[#14283F] dark:text-[#F1F5F9] truncate"
                      title={q.doctor.full_name}
                    >
                      {q.doctor.full_name}
                    </h3>
                    <p className="text-xs font-medium text-[#0F766E] dark:text-[#2DD4BF] mt-0.5 truncate">
                      {q.specialization.name}
                    </p>
                  </div>
                  <div className="flex flex-wrap items-center justify-end gap-1">
                    <StatusBadge
                      status={q.shift_status === 'CLOSING' ? 'CLOSING' : 'OPEN'}
                      size="sm"
                    />
                    {q.is_paused && <StatusBadge status="PAUSED" size="sm" />}
                  </div>
                </div>

                <div className="mt-3 flex items-center gap-2">
                  <span className="inline-flex items-center gap-1.5 rounded-lg bg-[#EDF6F8] px-2.5 py-1 text-xs font-medium text-[#14283F] dark:bg-[#1A3047] dark:text-[#F1F5F9]">
                    <DoorClosed className="h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
                    {q.doctor.room_number ? `${t.room} ${q.doctor.room_number}` : '—'}
                  </span>
                </div>

                {/* Counters Row */}
                <div className="mt-4 grid grid-cols-4 gap-2 rounded-xl bg-[#F5FAFB] p-3 text-center dark:bg-[#0B1728]/70 border border-[#DCE9EE]/70 dark:border-[#253F5B]/70">
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-[#64748B] dark:text-[#A5B4C7] truncate">
                      {t.waitingCount}
                    </div>
                    <div className="mt-1 text-lg font-black tabular-nums text-[#0284C7] dark:text-[#38BDF8]">
                      {q.waiting_count}
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-[#64748B] dark:text-[#A5B4C7] truncate">
                      {t.calledCount}
                    </div>
                    <div className="mt-1 text-lg font-black tabular-nums text-amber-600 dark:text-amber-400">
                      {q.called_count}
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-[#64748B] dark:text-[#A5B4C7] truncate">
                      {t.servingCount}
                    </div>
                    <div className="mt-1 text-lg font-black tabular-nums text-[#0D9488] dark:text-[#2DD4BF]">
                      {q.serving_count}
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-[#64748B] dark:text-[#A5B4C7] truncate">
                      {t.completedCount}
                    </div>
                    <div className="mt-1 text-lg font-black tabular-nums text-emerald-600 dark:text-emerald-400">
                      {q.completed_count ?? 0}
                    </div>
                  </div>
                </div>
              </div>

              <div className="mt-5 pt-4 border-t border-[#DCE9EE] dark:border-[#253F5B] flex items-center justify-between gap-3">
                <button
                  type="button"
                  onClick={() => {
                    setTargetQueue(q);
                    setIsPauseAction(!q.is_paused);
                  }}
                  className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-semibold transition-colors cursor-pointer ${
                    q.is_paused
                      ? 'border-emerald-200 bg-emerald-50/70 text-emerald-700 hover:bg-emerald-100 dark:border-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300'
                      : 'border-amber-200 bg-amber-50/70 text-amber-800 hover:bg-amber-100 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-300'
                  }`}
                >
                  {q.is_paused ? (
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

                <AppButton
                  variant="primary"
                  size="sm"
                  icon={<Users className="h-3.5 w-3.5" />}
                  onClick={() => navigate(`/reception/manage?queueId=${q.queue_id}`)}
                >
                  {t.manageQueue}
                </AppButton>
              </div>
            </div>
          ))}
        </div>
      )}

      <ConfirmModal
        isOpen={targetQueue !== null}
        title={
          isPauseAction ? t.pauseQueueConfirmTitle : t.resumeQueueConfirmTitle
        }
        message={
          isPauseAction
            ? `${targetQueue?.doctor.full_name}: ${t.pauseQueueConfirmMessage}`
            : `${targetQueue?.doctor.full_name}: ${t.resumeQueueConfirmMessage}`
        }
        confirmLabel={isPauseAction ? t.pauseQueue : t.resumeQueue}
        isDestructive={isPauseAction}
        isLoading={isProcessing}
        onConfirm={handleTogglePause}
        onCancel={() => setTargetQueue(null)}
      />
    </div>
  );
};
