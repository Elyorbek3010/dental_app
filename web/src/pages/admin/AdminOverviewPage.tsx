import React, { useCallback, useEffect, useState } from 'react';
import {
  Activity,
  ArrowRight,
  CheckCircle2,
  Clock,
  Radio,
  Stethoscope,
  TrendingUp,
  UserCheck,
  UserCog,
  Users,
} from 'lucide-react';
import { Link } from 'react-router-dom';
import { getAdminAnalyticsApi } from '../../api/admin';
import type { AdminAnalyticsOverview } from '../../types/admin';
import { useI18n } from '../../i18n/useI18n';
import { AlertBanner } from '../../components/common/AlertBanner';

export const AdminOverviewPage: React.FC = () => {
  const { t } = useI18n();

  const [analytics, setAnalytics] = useState<AdminAnalyticsOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAnalytics = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const data = await getAdminAnalyticsApi();
      setAnalytics(data);
    } catch (err: unknown) {
      if (err instanceof Error) {
        setError(err.message);
      } else {
        setError(t.errorGeneric);
      }
    } finally {
      setIsLoading(false);
    }
  }, [t.errorGeneric]);

  useEffect(() => {
    let isCancelled = false;
    getAdminAnalyticsApi()
      .then((data) => {
        if (!isCancelled) {
          setAnalytics(data);
          setIsLoading(false);
        }
      })
      .catch((err: unknown) => {
        if (!isCancelled) {
          setError(err instanceof Error ? err.message : t.errorGeneric);
          setIsLoading(false);
        }
      });
    return () => {
      isCancelled = true;
    };
  }, [t.errorGeneric]);

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100 flex items-center gap-2.5">
            <TrendingUp className="h-6 w-6 text-purple-600 dark:text-purple-400" />
            {t.adminOverviewTitle}
          </h2>
          <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
            {t.adminOverviewSubtitle}
          </p>
        </div>

        <button
          type="button"
          onClick={fetchAnalytics}
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
          {/* Top Operational Metrics */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            {/* Active Doctors */}
            <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold text-zinc-500 dark:text-zinc-400">
                  {t.adminKpiActiveDoctors}
                </p>
                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-purple-50 text-purple-600 dark:bg-purple-950/60 dark:text-purple-300">
                  <Users className="h-5 w-5" />
                </div>
              </div>
              <div className="mt-3 flex items-baseline gap-2">
                <span className="text-2xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
                  {analytics.active_doctors_count}
                </span>
                <span className="text-xs font-medium text-zinc-400">
                  / {analytics.total_doctors_count}
                </span>
              </div>
            </div>

            {/* Active Specializations */}
            <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold text-zinc-500 dark:text-zinc-400">
                  {t.adminKpiActiveSpecializations}
                </p>
                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-indigo-50 text-indigo-600 dark:bg-indigo-950/60 dark:text-indigo-300">
                  <Stethoscope className="h-5 w-5" />
                </div>
              </div>
              <div className="mt-3">
                <span className="text-2xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
                  {analytics.active_specializations_count}
                </span>
              </div>
            </div>

            {/* Active Receptionists */}
            <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold text-zinc-500 dark:text-zinc-400">
                  {t.adminKpiActiveReceptionists}
                </p>
                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-sky-50 text-sky-600 dark:bg-sky-950/60 dark:text-sky-300">
                  <UserCog className="h-5 w-5" />
                </div>
              </div>
              <div className="mt-3">
                <span className="text-2xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
                  {analytics.active_receptionists_count}
                </span>
              </div>
            </div>

            {/* Today Opened Queues */}
            <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold text-zinc-500 dark:text-zinc-400">
                  {t.adminKpiTodayQueues}
                </p>
                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600 dark:bg-emerald-950/60 dark:text-emerald-300">
                  <Radio className="h-5 w-5" />
                </div>
              </div>
              <div className="mt-3">
                <span className="text-2xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
                  {analytics.today_opened_queues_count}
                </span>
              </div>
            </div>
          </div>

          {/* Today's Live Ticket Throughput Breakdown */}
          <div className="rounded-2xl border border-zinc-200 bg-white p-6 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-sm font-bold text-zinc-900 dark:text-zinc-100">
                  {t.adminKpiTotalTickets}: {analytics.today_tickets_total}
                </h3>
                <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
                  {t.adminAnalyticsSubtitle}
                </p>
              </div>

              <Link
                to="/admin/analytics"
                className="inline-flex items-center gap-1.5 text-xs font-semibold text-purple-600 hover:text-purple-700 dark:text-purple-400"
              >
                {t.adminNavAnalytics}
                <ArrowRight className="h-3.5 w-3.5" />
              </Link>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
              {/* Waiting */}
              <div className="rounded-xl border border-amber-200 bg-amber-50/50 p-3.5 dark:border-amber-900/40 dark:bg-amber-950/20">
                <div className="flex items-center gap-1.5 text-amber-700 dark:text-amber-400">
                  <Clock className="h-4 w-4" />
                  <span className="text-2xs font-bold uppercase tracking-wider">
                    {t.adminKpiWaiting}
                  </span>
                </div>
                <p className="mt-2 text-xl font-bold text-amber-900 dark:text-amber-200">
                  {analytics.today_tickets_waiting}
                </p>
              </div>

              {/* Called */}
              <div className="rounded-xl border border-blue-200 bg-blue-50/50 p-3.5 dark:border-blue-900/40 dark:bg-blue-950/20">
                <div className="flex items-center gap-1.5 text-blue-700 dark:text-blue-400">
                  <Radio className="h-4 w-4" />
                  <span className="text-2xs font-bold uppercase tracking-wider">
                    {t.adminKpiCalled}
                  </span>
                </div>
                <p className="mt-2 text-xl font-bold text-blue-900 dark:text-blue-200">
                  {analytics.today_tickets_called}
                </p>
              </div>

              {/* Serving */}
              <div className="rounded-xl border border-indigo-200 bg-indigo-50/50 p-3.5 dark:border-indigo-900/40 dark:bg-indigo-950/20">
                <div className="flex items-center gap-1.5 text-indigo-700 dark:text-indigo-400">
                  <UserCheck className="h-4 w-4" />
                  <span className="text-2xs font-bold uppercase tracking-wider">
                    {t.adminKpiServing}
                  </span>
                </div>
                <p className="mt-2 text-xl font-bold text-indigo-900 dark:text-indigo-200">
                  {analytics.today_tickets_serving}
                </p>
              </div>

              {/* Completed */}
              <div className="rounded-xl border border-emerald-200 bg-emerald-50/50 p-3.5 dark:border-emerald-900/40 dark:bg-emerald-950/20">
                <div className="flex items-center gap-1.5 text-emerald-700 dark:text-emerald-400">
                  <CheckCircle2 className="h-4 w-4" />
                  <span className="text-2xs font-bold uppercase tracking-wider">
                    {t.adminKpiCompleted}
                  </span>
                </div>
                <p className="mt-2 text-xl font-bold text-emerald-900 dark:text-emerald-200">
                  {analytics.today_tickets_completed}
                </p>
              </div>

              {/* Skipped */}
              <div className="rounded-xl border border-zinc-200 bg-zinc-50 p-3.5 dark:border-zinc-800 dark:bg-zinc-800/40">
                <span className="text-2xs font-bold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
                  {t.adminKpiSkipped}
                </span>
                <p className="mt-2 text-xl font-bold text-zinc-700 dark:text-zinc-300">
                  {analytics.today_tickets_skipped}
                </p>
              </div>

              {/* Cancelled */}
              <div className="rounded-xl border border-zinc-200 bg-zinc-50 p-3.5 dark:border-zinc-800 dark:bg-zinc-800/40">
                <span className="text-2xs font-bold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
                  {t.adminKpiCancelled}
                </span>
                <p className="mt-2 text-xl font-bold text-zinc-700 dark:text-zinc-300">
                  {analytics.today_tickets_cancelled}
                </p>
              </div>
            </div>
          </div>

          {/* Today's Doctor Queue Statuses Table */}
          <div className="rounded-2xl border border-zinc-200 bg-white shadow-2xs dark:border-zinc-800 dark:bg-zinc-900 overflow-hidden">
            <div className="px-6 py-4 border-b border-zinc-200 dark:border-zinc-800 flex items-center justify-between">
              <div>
                <h3 className="text-sm font-bold text-zinc-900 dark:text-zinc-100">
                  {t.adminTodayDoctorQueues}
                </h3>
                <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
                  {t.doctorsOverviewSubtitle}
                </p>
              </div>
            </div>

            {analytics.doctors_today.length === 0 ? (
              <div className="p-8 text-center text-xs text-zinc-500 dark:text-zinc-400">
                {t.adminNoQueuesToday}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr className="border-b border-zinc-200 bg-zinc-50/75 dark:border-zinc-800 dark:bg-zinc-800/40 text-zinc-500 dark:text-zinc-400 uppercase tracking-wider font-semibold">
                      <th className="px-5 py-3.5">{t.doctor}</th>
                      <th className="px-5 py-3.5">{t.specialization}</th>
                      <th className="px-5 py-3.5">{t.room}</th>
                      <th className="px-5 py-3.5">{t.status}</th>
                      <th className="px-5 py-3.5 text-center">{t.totalQueues}</th>
                      <th className="px-5 py-3.5 text-center">{t.waitingCount}</th>
                      <th className="px-5 py-3.5 text-center">{t.servingCount}</th>
                      <th className="px-5 py-3.5 text-center">{t.completedCount}</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800/60 font-medium">
                    {analytics.doctors_today.map((item) => (
                      <tr
                        key={item.doctor_id}
                        className="hover:bg-zinc-50/60 dark:hover:bg-zinc-800/30 transition-colors"
                      >
                        <td className="px-5 py-3.5 text-zinc-900 dark:text-zinc-100 font-semibold">
                          {item.doctor_name}
                        </td>
                        <td className="px-5 py-3.5 text-zinc-600 dark:text-zinc-300">
                          {item.specialization_name}
                        </td>
                        <td className="px-5 py-3.5 text-zinc-600 dark:text-zinc-300">
                          {item.room_number || '—'}
                        </td>
                        <td className="px-5 py-3.5">
                          {item.has_queue_today ? (
                            <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-0.5 text-2xs font-semibold text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300">
                              <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                              {t.adminDoctorQueueStatusOpen}
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 rounded-full bg-zinc-100 px-2.5 py-0.5 text-2xs font-semibold text-zinc-500 dark:bg-zinc-800 dark:text-zinc-400">
                              {t.adminDoctorQueueStatusClosed}
                            </span>
                          )}
                        </td>
                        <td className="px-5 py-3.5 text-center font-bold text-zinc-900 dark:text-zinc-100">
                          {item.total_tickets}
                        </td>
                        <td className="px-5 py-3.5 text-center font-semibold text-amber-600 dark:text-amber-400">
                          {item.waiting_tickets}
                        </td>
                        <td className="px-5 py-3.5 text-center font-semibold text-indigo-600 dark:text-indigo-400">
                          {item.serving_tickets}
                        </td>
                        <td className="px-5 py-3.5 text-center font-semibold text-emerald-600 dark:text-emerald-400">
                          {item.completed_tickets}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
};
