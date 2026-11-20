import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  Activity,
  Ban,
  CheckCircle2,
  ClipboardList,
  Clock,
  PhoneCall,
  Radio,
  SkipForward,
  UserCheck,
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

export const AdminAnalyticsPage: React.FC = () => {
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

  const totalTickets = analytics?.today_tickets_total || 0;
  const waitingCount = analytics?.today_tickets_waiting || 0;
  const calledCount = analytics?.today_tickets_called || 0;
  const servingCount = analytics?.today_tickets_serving || 0;
  const completedCount = analytics?.today_tickets_completed || 0;
  const skippedCount = analytics?.today_tickets_skipped || 0;
  const cancelledCount = analytics?.today_tickets_cancelled || 0;
  const todayQueuesCount = analytics?.today_opened_queues_count || 0;

  return (
    <div className="space-y-4 max-w-7xl mx-auto animate-dental-in">
      <PageHeader
        title={t.adminAnalyticsTitle}
        subtitle={t.adminAnalyticsSubtitle}
        icon={<ClipboardList className="h-5 w-5" />}
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
          {/* Primary Tinted Ticket Metrics */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3.5">
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
              value={waitingCount}
              helperText={formatShareText(
                waitingCount,
                totalTickets,
                t.adminShareSummaryTemplate,
                t.adminNoTicketsIssuedToday
              )}
              icon={<Clock className="h-5 w-5" />}
              tone="blue"
            />
            <StatCard
              variant="tinted"
              label={t.adminKpiCompleted}
              subLabel={t.todayShortLabel}
              value={completedCount}
              helperText={formatShareText(
                completedCount,
                totalTickets,
                t.adminShareSummaryTemplate,
                t.adminNoTicketsIssuedToday
              )}
              icon={<CheckCircle2 className="h-5 w-5" />}
              tone="emerald"
            />
            <StatCard
              variant="tinted"
              label={t.adminKpiSkipped}
              subLabel={t.todayShortLabel}
              value={skippedCount}
              helperText={formatShareText(
                skippedCount,
                totalTickets,
                t.adminShareSummaryTemplate,
                t.adminNoTicketsIssuedToday
              )}
              icon={<SkipForward className="h-5 w-5" />}
              tone="rose"
            />
          </div>

          {/* Secondary Live Status Strip */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard
              label={t.adminKpiCalled}
              value={calledCount}
              icon={<PhoneCall className="h-4 w-4" />}
              tone="amber"
            />
            <StatCard
              label={t.adminKpiServing}
              value={servingCount}
              icon={<UserCheck className="h-4 w-4" />}
              tone="teal"
            />
            <StatCard
              label={t.adminKpiCancelled}
              value={cancelledCount}
              icon={<Ban className="h-4 w-4" />}
              tone="neutral"
            />
            <StatCard
              label={t.adminKpiTodayQueues}
              value={todayQueuesCount}
              icon={<Radio className="h-4 w-4" />}
              tone="blue"
            />
          </div>

          {/* Today's Completion Progress */}
          <CompletionProgressCard
            totalTickets={totalTickets}
            completedTickets={completedCount}
            waitingTickets={waitingCount}
            calledTickets={calledCount}
            servingTickets={servingCount}
            skippedTickets={skippedCount}
            cancelledTickets={cancelledCount}
          />

          {/* Interactive Doctor Queue Cards / Table */}
          <DoctorQueuesSection doctors={analytics.doctors_today} defaultView="cards" />
        </>
      )}
    </div>
  );
};
