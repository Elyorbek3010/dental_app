import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Activity, BarChart3 } from 'lucide-react';
import { getAdminAnalyticsApi } from '../../api/admin';
import type { AdminAnalyticsOverview } from '../../types/admin';
import { useI18n } from '../../i18n/useI18n';
import { AlertBanner } from '../../components/common/AlertBanner';

export const AdminAnalyticsPage: React.FC = () => {
  const { t } = useI18n();

  const [analytics, setAnalytics] = useState<AdminAnalyticsOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const isMountedRef = useRef(true);
  const latestRequestIdRef = useRef(0);

  const fetchAnalytics = useCallback(
    async (isSilent = false) => {
      const requestId = ++latestRequestIdRef.current;
      if (!isSilent) {
        setIsLoading(true);
        setError(null);
      }
      try {
        const data = await getAdminAnalyticsApi();
        if (!isMountedRef.current || requestId !== latestRequestIdRef.current) return;
        setAnalytics(data);
        setError(null);
      } catch (err: unknown) {
        if (!isMountedRef.current || requestId !== latestRequestIdRef.current) return;
        if (!isSilent) {
          if (err instanceof Error) {
            setError(err.message);
          } else {
            setError(t.errorGeneric);
          }
        }
      } finally {
        if (isMountedRef.current && requestId === latestRequestIdRef.current && !isSilent) {
          setIsLoading(false);
        }
      }
    },
    [t.errorGeneric]
  );

  useEffect(() => {
    isMountedRef.current = true;
    const requestId = ++latestRequestIdRef.current;

    getAdminAnalyticsApi()
      .then((data) => {
        if (!isMountedRef.current || requestId !== latestRequestIdRef.current) return;
        setAnalytics(data);
        setError(null);
        setIsLoading(false);
      })
      .catch((err: unknown) => {
        if (!isMountedRef.current || requestId !== latestRequestIdRef.current) return;
        setError(err instanceof Error ? err.message : t.errorGeneric);
        setIsLoading(false);
      });

    const handleAdminRefresh = () => {
      fetchAnalytics(true);
    };

    window.addEventListener('admin:refresh', handleAdminRefresh);
    return () => {
      isMountedRef.current = false;
      window.removeEventListener('admin:refresh', handleAdminRefresh);
    };
  }, [fetchAnalytics, t.errorGeneric]);

  const totalTickets = analytics?.today_tickets_total || 0;
  const waitingPct = totalTickets > 0 ? Math.round(((analytics?.today_tickets_waiting || 0) / totalTickets) * 100) : 0;
  const calledPct = totalTickets > 0 ? Math.round(((analytics?.today_tickets_called || 0) / totalTickets) * 100) : 0;
  const servingPct = totalTickets > 0 ? Math.round(((analytics?.today_tickets_serving || 0) / totalTickets) * 100) : 0;
  const completedPct = totalTickets > 0 ? Math.round(((analytics?.today_tickets_completed || 0) / totalTickets) * 100) : 0;
  const otherPct = totalTickets > 0 ? 100 - (waitingPct + calledPct + servingPct + completedPct) : 0;

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100 flex items-center gap-2.5">
            <BarChart3 className="h-6 w-6 text-purple-600 dark:text-purple-400" />
            {t.adminAnalyticsTitle}
          </h2>
          <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
            {t.adminAnalyticsSubtitle}
          </p>
        </div>

        <button
          type="button"
          onClick={() => fetchAnalytics(false)}
          className="inline-flex items-center gap-2 rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-xs font-semibold text-zinc-700 shadow-2xs hover:bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-300 dark:hover:bg-zinc-800 transition-colors cursor-pointer"
        >
          <Activity className="h-3.5 w-3.5 text-purple-600 dark:text-purple-400" />
          {t.refresh}
        </button>
      </div>

      {error && <AlertBanner type="error" message={error} onClose={() => setError(null)} />}

      {isLoading ? (
        <div className="p-16 text-center text-xs text-zinc-500 dark:text-zinc-400">
          <div className="mx-auto h-8 w-8 animate-spin rounded-full border-2 border-purple-600 border-t-transparent mb-3" />
          {t.loading}
        </div>
      ) : !analytics ? (
        <div className="p-12 text-center text-xs text-zinc-500 dark:text-zinc-400">
          {t.noData}
        </div>
      ) : (
        <>
          {/* Visual Percentage Distribution Bar */}
          <div className="rounded-2xl border border-zinc-200 bg-white p-6 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
            <h3 className="text-sm font-bold text-zinc-900 dark:text-zinc-100 mb-2">
              {t.adminKpiTotalTickets}: {totalTickets}
            </h3>

            {/* Distribution Bar */}
            <div className="h-4 w-full rounded-full bg-zinc-100 dark:bg-zinc-800 flex overflow-hidden">
              {waitingPct > 0 && (
                <div
                  style={{ width: `${waitingPct}%` }}
                  className="bg-amber-400 dark:bg-amber-500 transition-all duration-500"
                  title={`${t.adminKpiWaiting}: ${analytics.today_tickets_waiting} (${waitingPct}%)`}
                />
              )}
              {calledPct > 0 && (
                <div
                  style={{ width: `${calledPct}%` }}
                  className="bg-blue-500 dark:bg-blue-600 transition-all duration-500"
                  title={`${t.adminKpiCalled}: ${analytics.today_tickets_called} (${calledPct}%)`}
                />
              )}
              {servingPct > 0 && (
                <div
                  style={{ width: `${servingPct}%` }}
                  className="bg-purple-500 dark:bg-purple-600 transition-all duration-500"
                  title={`${t.adminKpiServing}: ${analytics.today_tickets_serving} (${servingPct}%)`}
                />
              )}
              {completedPct > 0 && (
                <div
                  style={{ width: `${completedPct}%` }}
                  className="bg-emerald-500 dark:bg-emerald-600 transition-all duration-500"
                  title={`${t.adminKpiCompleted}: ${analytics.today_tickets_completed} (${completedPct}%)`}
                />
              )}
              {otherPct > 0 && (
                <div
                  style={{ width: `${otherPct}%` }}
                  className="bg-zinc-400 dark:bg-zinc-600 transition-all duration-500"
                  title={`${t.adminKpiSkipped}/${t.adminKpiCancelled}`}
                />
              )}
            </div>

            {/* Distribution Legend */}
            <div className="mt-4 flex flex-wrap items-center gap-4 text-xs font-medium">
              <div className="flex items-center gap-1.5">
                <span className="h-3 w-3 rounded-full bg-amber-400" />
                <span className="text-zinc-600 dark:text-zinc-300">
                  {t.adminKpiWaiting} ({analytics.today_tickets_waiting})
                </span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="h-3 w-3 rounded-full bg-blue-500" />
                <span className="text-zinc-600 dark:text-zinc-300">
                  {t.adminKpiCalled} ({analytics.today_tickets_called})
                </span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="h-3 w-3 rounded-full bg-purple-500" />
                <span className="text-zinc-600 dark:text-zinc-300">
                  {t.adminKpiServing} ({analytics.today_tickets_serving})
                </span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="h-3 w-3 rounded-full bg-emerald-500" />
                <span className="text-zinc-600 dark:text-zinc-300">
                  {t.adminKpiCompleted} ({analytics.today_tickets_completed})
                </span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="h-3 w-3 rounded-full bg-zinc-400" />
                <span className="text-zinc-600 dark:text-zinc-300">
                  {t.adminKpiSkipped}/{t.adminKpiCancelled} (
                  {analytics.today_tickets_skipped + analytics.today_tickets_cancelled})
                </span>
              </div>
            </div>
          </div>

          {/* Doctor Load Overview */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {analytics.doctors_today.map((doc) => (
              <div
                key={doc.doctor_id}
                className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900 flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <h4 className="text-sm font-bold text-zinc-900 dark:text-zinc-100">
                        {doc.doctor_name}
                      </h4>
                      <p className="text-xs text-zinc-500 dark:text-zinc-400">
                        {doc.specialization_name} • {doc.room_number ? `Xona ${doc.room_number}` : '—'}
                      </p>
                    </div>

                    {doc.has_queue_today ? (
                      <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-2xs font-semibold text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300">
                        {t.adminDoctorQueueStatusOpen}
                      </span>
                    ) : (
                      <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-2xs font-semibold text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400">
                        {t.adminDoctorQueueStatusClosed}
                      </span>
                    )}
                  </div>

                  <div className="mt-4 grid grid-cols-4 gap-2 text-center">
                    <div className="rounded-xl bg-zinc-50 p-2 dark:bg-zinc-800/60">
                      <span className="text-2xs text-zinc-400 uppercase font-semibold">
                        Jami
                      </span>
                      <p className="text-base font-bold text-zinc-900 dark:text-zinc-100">
                        {doc.total_tickets}
                      </p>
                    </div>

                    <div className="rounded-xl bg-amber-50/60 p-2 dark:bg-amber-950/20">
                      <span className="text-2xs text-amber-700 dark:text-amber-400 uppercase font-semibold">
                        Kutish
                      </span>
                      <p className="text-base font-bold text-amber-900 dark:text-amber-200">
                        {doc.waiting_tickets}
                      </p>
                    </div>

                    <div className="rounded-xl bg-purple-50/60 p-2 dark:bg-purple-950/20">
                      <span className="text-2xs text-purple-700 dark:text-purple-400 uppercase font-semibold">
                        Qabul
                      </span>
                      <p className="text-base font-bold text-purple-900 dark:text-purple-200">
                        {doc.serving_tickets}
                      </p>
                    </div>

                    <div className="rounded-xl bg-emerald-50/60 p-2 dark:bg-emerald-950/20">
                      <span className="text-2xs text-emerald-700 dark:text-emerald-400 uppercase font-semibold">
                        Yopilgan
                      </span>
                      <p className="text-base font-bold text-emerald-900 dark:text-emerald-200">
                        {doc.completed_tickets}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
};
