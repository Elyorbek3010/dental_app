import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  Activity,
  CheckCircle2,
  ClipboardList,
  Clock,
  Radio,
  SkipForward,
  Stethoscope,
  TrendingUp,
  UserCog,
  Users,
} from 'lucide-react';
import { getAdminAnalyticsApi } from '../../api/admin';
import type { AdminAnalyticsOverview } from '../../types/admin';
import { useI18n } from '../../i18n/useI18n';
import { formatShareText } from '../../utils/adminStats';
import { CompletionProgressCard } from '../../components/admin/CompletionProgressCard';
import { DoctorQueuesSection } from '../../components/admin/DoctorQueuesSection';
import { AlertBanner } from '../../components/common/AlertBanner';
import { AppButton } from '../../components/common/AppButton';
import { EmptyState } from '../../components/common/EmptyState';
import { LoadingSkeleton } from '../../components/common/LoadingSkeleton';
import { PageHeader } from '../../components/common/PageHeader';
import { StatCard } from '../../components/common/StatCard';

export const AdminOverviewPage: React.FC = () => {
  const { t } = useI18n();

  const [analytics, setAnalytics] = useState<AdminAnalyticsOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const isMountedRef = useRef(true);
  const latestRequestIdRef = useRef(0);
  const errorGenericRef = useRef(t.errorGeneric);

  useEffect(() => {
    errorGenericRef.current = t.errorGeneric;
  }, [t.errorGeneric]);

  const fetchAnalytics = useCallback(async (isSilent = false) => {
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
        setError(err instanceof Error ? err.message : errorGenericRef.current);
      }
    } finally {
      if (isMountedRef.current && requestId === latestRequestIdRef.current && !isSilent) {
        setIsLoading(false);
      }
    }
  }, []);

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
        setError(err instanceof Error ? err.message : errorGenericRef.current);
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
  }, [fetchAnalytics]);

  const totalTickets = analytics?.today_tickets_total ?? 0;
  const skippedAndCancelled =
    (analytics?.today_tickets_skipped ?? 0) + (analytics?.today_tickets_cancelled ?? 0);

  return (
    <div className="space-y-3.5 lg:space-y-0 lg:h-[calc(100vh-6.5rem)] lg:flex lg:flex-col lg:gap-3.5 max-w-7xl mx-auto animate-dental-in">
      <PageHeader
        title={t.adminOverviewTitle}
        subtitle={t.adminOverviewSubtitle}
        icon={<TrendingUp className="h-5 w-5" />}
        actions={
          <AppButton
            variant="secondary"
            size="sm"
            onClick={() => fetchAnalytics(false)}
            icon={<Activity className="h-3.5 w-3.5 text-[#0D9488] dark:text-[#2DD4BF]" />}
          >
            {t.refresh}
          </AppButton>
        }
      />

      {error && <AlertBanner type="error" message={error} onClose={() => setError(null)} />}

      {isLoading ? (
        <LoadingSkeleton cards={4} rows={5} />
      ) : !analytics ? (
        <EmptyState title={t.noData} />
      ) : (
        <>
          {/* Primary Tinted KPI Summary Cards */}
          <div className="shrink-0 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard
              variant="tinted"
              label={t.adminKpiTotalTickets}
              subLabel={t.todayShortLabel}
              value={totalTickets}
              icon={<ClipboardList className="h-5 w-5" />}
              tone="teal"
            />
            <StatCard
              variant="tinted"
              label={t.adminKpiWaiting}
              subLabel={t.adminActiveInQueueLabel}
              value={analytics.today_tickets_waiting}
              helperText={formatShareText(
                analytics.today_tickets_waiting,
                totalTickets,
                t.adminShareSummaryTemplate,
                t.adminNoTicketsIssuedToday
              )}
              icon={<Clock className="h-5 w-5" />}
              tone="amber"
            />
            <StatCard
              variant="tinted"
              label={t.adminKpiCompleted}
              subLabel={t.todayShortLabel}
              value={analytics.today_tickets_completed}
              helperText={formatShareText(
                analytics.today_tickets_completed,
                totalTickets,
                t.adminShareSummaryTemplate,
                t.adminNoTicketsIssuedToday
              )}
              icon={<CheckCircle2 className="h-5 w-5" />}
              tone="emerald"
            />
            <StatCard
              variant="tinted"
              label={t.adminSkippedCancelledLabel}
              subLabel={t.todayShortLabel}
              value={skippedAndCancelled}
              helperText={formatShareText(
                skippedAndCancelled,
                totalTickets,
                t.adminShareSummaryTemplate,
                t.adminNoTicketsIssuedToday
              )}
              icon={<SkipForward className="h-5 w-5" />}
              tone="rose"
            />
          </div>

          {/* Today's Completion Progress */}
          <CompletionProgressCard
            totalTickets={analytics.today_tickets_total}
            completedTickets={analytics.today_tickets_completed}
            waitingTickets={analytics.today_tickets_waiting}
            calledTickets={analytics.today_tickets_called}
            servingTickets={analytics.today_tickets_serving}
            skippedTickets={analytics.today_tickets_skipped}
            cancelledTickets={analytics.today_tickets_cancelled}
          />

          {/* Compact Clinic Staffing & Open Queues Strip */}
          <div className="shrink-0 grid grid-cols-2 lg:grid-cols-4 gap-2.5">
            <div className="flex items-center gap-3 rounded-xl border border-[#DCE9EE] bg-white px-4 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
              <Users className="h-4 w-4 text-[#0D9488] dark:text-[#2DD4BF] shrink-0" />
              <div className="min-w-0 flex-1 flex items-baseline justify-between gap-2">
                <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7] truncate">
                  {t.adminKpiActiveDoctors}
                </span>
                <span className="text-sm font-bold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                  {analytics.active_doctors_count}/{analytics.total_doctors_count}
                </span>
              </div>
            </div>

            <div className="flex items-center gap-3 rounded-xl border border-[#DCE9EE] bg-white px-4 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
              <Stethoscope className="h-4 w-4 text-[#0284C7] dark:text-[#38BDF8] shrink-0" />
              <div className="min-w-0 flex-1 flex items-baseline justify-between gap-2">
                <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7] truncate">
                  {t.adminKpiActiveSpecializations}
                </span>
                <span className="text-sm font-bold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                  {analytics.active_specializations_count}
                </span>
              </div>
            </div>

            <div className="flex items-center gap-3 rounded-xl border border-[#DCE9EE] bg-white px-4 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
              <UserCog className="h-4 w-4 text-[#0D9488] dark:text-[#2DD4BF] shrink-0" />
              <div className="min-w-0 flex-1 flex items-baseline justify-between gap-2">
                <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7] truncate">
                  {t.adminKpiActiveReceptionists}
                </span>
                <span className="text-sm font-bold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                  {analytics.active_receptionists_count}
                </span>
              </div>
            </div>

            <div className="flex items-center gap-3 rounded-xl border border-[#DCE9EE] bg-white px-4 py-2.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
              <Radio className="h-4 w-4 text-emerald-600 dark:text-emerald-400 shrink-0" />
              <div className="min-w-0 flex-1 flex items-baseline justify-between gap-2">
                <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7] truncate">
                  {t.adminKpiTodayQueues}
                </span>
                <span className="text-sm font-bold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                  {analytics.today_opened_queues_count}
                </span>
              </div>
            </div>
          </div>

          {/* Interactive Today's Doctor Queue Statuses */}
          <DoctorQueuesSection doctors={analytics.doctors_today} defaultView="table" />
        </>
      )}
    </div>
  );
};
