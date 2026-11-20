import React from 'react';
import { Flag } from 'lucide-react';
import { useI18n } from '../../i18n/useI18n';
import {
  calcShareValue,
  formatCompletionProgressText,
  formatPercent,
} from '../../utils/adminStats';

interface CompletionProgressCardProps {
  totalTickets: number;
  completedTickets: number;
  waitingTickets: number;
  calledTickets: number;
  servingTickets: number;
  skippedTickets: number;
  cancelledTickets: number;
}

export const CompletionProgressCard: React.FC<CompletionProgressCardProps> = ({
  totalTickets,
  completedTickets,
  waitingTickets,
  calledTickets,
  servingTickets,
  skippedTickets,
  cancelledTickets,
}) => {
  const { t } = useI18n();

  const completionPercent = calcShareValue(completedTickets, totalTickets);
  const formattedPercent = formatPercent(completionPercent);
  const summaryText = formatCompletionProgressText(
    completedTickets,
    totalTickets,
    t.adminProgressSummaryTemplate
  );
  const activeInQueue = waitingTickets + calledTickets + servingTickets;
  const skippedOrCancelled = skippedTickets + cancelledTickets;

  return (
    <section className="shrink-0 rounded-2xl border border-[#DCE9EE] bg-white p-5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
            <Flag className="h-5 w-5" />
          </div>
          <div>
            <h3 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9]">
              {t.adminProgressTitle}
            </h3>
            <p className="mt-0.5 text-xs font-medium text-[#64748B] dark:text-[#A5B4C7]">
              {totalTickets > 0 ? t.adminAnalyticsSubtitle : t.adminNoTicketsIssuedToday}
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-3 md:gap-4">
          <span className="text-2xl sm:text-3xl font-black tracking-tight tabular-nums text-[#0F766E] dark:text-[#2DD4BF]">
            {formattedPercent}
          </span>
          <span className="hidden sm:inline-block h-6 w-px bg-[#DCE9EE] dark:bg-[#253F5B]" />
          <span className="text-xs sm:text-sm font-semibold text-[#14283F] dark:text-[#F1F5F9]">
            {summaryText}
          </span>
        </div>
      </div>

      {/* Clean Teal Progress Bar */}
      <div className="mt-4">
        <div
          role="progressbar"
          aria-label={t.adminProgressTitle}
          aria-valuenow={completionPercent}
          aria-valuemin={0}
          aria-valuemax={100}
          className="h-3.5 w-full rounded-full bg-[#EDF6F8] dark:bg-[#0B1728] overflow-hidden border border-[#DCE9EE]/70 dark:border-[#253F5B]/80"
        >
          <div
            style={{ width: `${completionPercent}%` }}
            className="h-full rounded-full bg-[#0D9488] dark:bg-[#2DD4BF] transition-[width] duration-500 ease-out motion-reduce:transition-none"
          />
        </div>
      </div>

      {/* Compact Breakdown Strip */}
      <div className="mt-3.5 flex flex-wrap items-center gap-3 text-xs">
        <span className="inline-flex items-center gap-1.5 rounded-lg bg-[#F5FAFB] px-2.5 py-1 font-medium text-[#64748B] dark:bg-[#0B1728]/60 dark:text-[#A5B4C7]">
          {t.adminKpiCompleted}:{' '}
          <strong className="tabular-nums text-emerald-700 dark:text-emerald-300">
            {completedTickets} / {totalTickets}
          </strong>
        </span>
        <span className="inline-flex items-center gap-1.5 rounded-lg bg-[#F5FAFB] px-2.5 py-1 font-medium text-[#64748B] dark:bg-[#0B1728]/60 dark:text-[#A5B4C7]">
          {t.adminActiveInQueueLabel}:{' '}
          <strong className="tabular-nums text-[#0284C7] dark:text-[#38BDF8]">
            {activeInQueue}
          </strong>
        </span>
        <span className="inline-flex items-center gap-1.5 rounded-lg bg-[#F5FAFB] px-2.5 py-1 font-medium text-[#64748B] dark:bg-[#0B1728]/60 dark:text-[#A5B4C7]">
          {t.adminSkippedCancelledLabel}:{' '}
          <strong className="tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
            {skippedOrCancelled}
          </strong>
        </span>
      </div>
    </section>
  );
};
