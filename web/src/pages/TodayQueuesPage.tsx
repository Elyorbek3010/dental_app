import React, { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Activity,
  DoorClosed,
  PauseCircle,
  PlayCircle,
  Users,
} from 'lucide-react';
import { fetchReceptionTodayQueues, pauseQueue, resumeQueue } from '../api/reception';
import { useI18n } from '../i18n/useI18n';
import type { ReceptionQueueOverview } from '../types/reception';
import { StatusBadge } from '../components/common/StatusBadge';
import { ConfirmModal } from '../components/common/ConfirmModal';
import { AlertBanner } from '../components/common/AlertBanner';

export const TodayQueuesPage: React.FC = () => {
  const { t, language } = useI18n();
  const navigate = useNavigate();

  const [queues, setQueues] = useState<ReceptionQueueOverview[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [notice, setNotice] = useState<{ type: 'error' | 'success'; message: string } | null>(null);

  // Pause / Resume modal state
  const [targetQueue, setTargetQueue] = useState<ReceptionQueueOverview | null>(null);
  const [isPauseAction, setIsPauseAction] = useState<boolean>(false);
  const [isProcessing, setIsProcessing] = useState<boolean>(false);

  const loadQueues = useCallback(async (showLoading = false) => {
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
  }, [t.errorGeneric]);

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

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-zinc-900 dark:text-zinc-100">
            {t.todayQueues}
          </h2>
          <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
            {t.doctorsOverviewSubtitle}
          </p>
        </div>
      </div>

      {notice && (
        <AlertBanner
          type={notice.type}
          message={notice.message}
          onClose={() => setNotice(null)}
        />
      )}

      {isLoading ? (
        <div className="p-16 text-center">
          <div className="inline-block h-8 w-8 animate-spin rounded-full border-3 border-indigo-600 border-t-transparent" />
          <p className="mt-2 text-xs text-zinc-500 dark:text-zinc-400">{t.loading}</p>
        </div>
      ) : queues.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-zinc-300 p-12 text-center dark:border-zinc-800 bg-white/50 dark:bg-zinc-900/50">
          <Activity className="mx-auto h-12 w-12 text-zinc-400 mb-3" />
          <h3 className="text-base font-bold text-zinc-800 dark:text-zinc-200">
            {t.noQueuesToday}
          </h3>
          <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400 max-w-md mx-auto">
            {t.noQueuesHint}
          </p>
          <button
            type="button"
            onClick={() => navigate('/reception')}
            className="mt-5 inline-flex items-center gap-2 rounded-xl bg-indigo-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-indigo-700"
          >
            {t.dashboard}
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {queues.map((q) => (
            <div
              key={q.queue_id}
              className={`flex flex-col justify-between rounded-2xl border bg-white p-5 shadow-2xs transition-all dark:bg-zinc-900 ${
                q.is_paused
                  ? 'border-amber-200 dark:border-amber-900/50'
                  : 'border-zinc-200 hover:border-indigo-300 dark:border-zinc-800 dark:hover:border-indigo-800'
              }`}
            >
              {/* Card Top */}
              <div>
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h3 className="text-base font-bold text-zinc-900 dark:text-zinc-100">
                      {q.doctor.full_name}
                    </h3>
                    <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
                      {q.specialization.name}
                    </p>
                  </div>
                  <StatusBadge status={q.is_paused ? 'PAUSED' : 'ACTIVE'} size="sm" />
                </div>

                <div className="mt-3 flex items-center gap-2">
                  <span className="inline-flex items-center gap-1.5 rounded-lg bg-zinc-100 px-2 py-0.5 text-xs font-medium text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                    <DoorClosed className="h-3.5 w-3.5 text-zinc-400" />
                    {q.doctor.room_number ? `${t.room} ${q.doctor.room_number}` : '—'}
                  </span>
                  <span className="text-xs text-zinc-400">
                    Queue #{q.queue_id}
                  </span>
                </div>

                {/* Counters Row */}
                <div className="mt-5 grid grid-cols-3 gap-2 rounded-xl bg-zinc-50 p-3 text-center dark:bg-zinc-800/50">
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-zinc-400">
                      {t.waitingCount}
                    </div>
                    <div className="mt-1 text-lg font-black text-blue-600 dark:text-blue-400">
                      {q.waiting_count}
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-zinc-400">
                      {t.calledCount}
                    </div>
                    <div className="mt-1 text-lg font-black text-amber-600 dark:text-amber-400">
                      {q.called_count}
                    </div>
                  </div>
                  <div>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-zinc-400">
                      {t.servingCount}
                    </div>
                    <div className="mt-1 text-lg font-black text-emerald-600 dark:text-emerald-400">
                      {q.serving_count}
                    </div>
                  </div>
                </div>
              </div>

              {/* Card Footer Actions */}
              <div className="mt-5 pt-4 border-t border-zinc-100 dark:border-zinc-800/80 flex items-center justify-between gap-3">
                <button
                  type="button"
                  onClick={() => {
                    setTargetQueue(q);
                    setIsPauseAction(!q.is_paused);
                  }}
                  className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-semibold transition-colors ${
                    q.is_paused
                      ? 'border-emerald-200 text-emerald-700 hover:bg-emerald-50 dark:border-emerald-800 dark:text-emerald-400 dark:hover:bg-emerald-950/40'
                      : 'border-amber-200 text-amber-700 hover:bg-amber-50 dark:border-amber-800 dark:text-amber-400 dark:hover:bg-amber-950/40'
                  }`}
                >
                  {q.is_paused ? (
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

                <button
                  type="button"
                  onClick={() => navigate(`/reception/manage?queueId=${q.queue_id}`)}
                  className="inline-flex items-center gap-1.5 rounded-xl bg-indigo-600 px-4 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-indigo-700 transition-colors"
                >
                  <Users className="h-4 w-4" />
                  {t.manageQueue}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Pause / Resume Confirmation Modal */}
      <ConfirmModal
        isOpen={targetQueue !== null}
        title={
          isPauseAction
            ? t.pauseQueueConfirmTitle
            : t.resumeQueueConfirmTitle
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
