import React, { useMemo, useState } from 'react';
import { LayoutGrid, Search, Stethoscope, Table2, UserRound } from 'lucide-react';
import type { DoctorQueueSummary } from '../../types/admin';
import { useI18n } from '../../i18n/useI18n';
import { calcShareValue, formatPercent } from '../../utils/adminStats';
import { EmptyState } from '../common/EmptyState';

interface DoctorQueuesSectionProps {
  doctors: DoctorQueueSummary[];
  defaultView?: 'cards' | 'table';
}

type QueueStatusFilter = 'ALL' | 'OPEN' | 'CLOSED';
type ViewMode = 'cards' | 'table';

export const DoctorQueuesSection: React.FC<DoctorQueuesSectionProps> = ({
  doctors,
  defaultView = 'table',
}) => {
  const { t } = useI18n();
  const [statusFilter, setStatusFilter] = useState<QueueStatusFilter>('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [viewMode, setViewMode] = useState<ViewMode>(defaultView);

  const counts = useMemo(() => {
    const open = doctors.filter((d) => d.has_queue_today).length;
    return {
      all: doctors.length,
      open,
      closed: doctors.length - open,
    };
  }, [doctors]);

  const filteredDoctors = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return doctors.filter((doc) => {
      if (statusFilter === 'OPEN' && !doc.has_queue_today) return false;
      if (statusFilter === 'CLOSED' && doc.has_queue_today) return false;
      if (!q) return true;
      return (
        doc.doctor_name.toLowerCase().includes(q) ||
        doc.specialization_name.toLowerCase().includes(q) ||
        (doc.room_number || '').toLowerCase().includes(q)
      );
    });
  }, [doctors, searchQuery, statusFilter]);

  const filterOptions: { key: QueueStatusFilter; label: string; count: number }[] = [
    { key: 'ALL', label: t.adminFilterAll, count: counts.all },
    { key: 'OPEN', label: t.adminFilterOpen, count: counts.open },
    { key: 'CLOSED', label: t.adminFilterClosed, count: counts.closed },
  ];

  return (
    <section className="rounded-2xl border border-[#DCE9EE] bg-white shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A] overflow-hidden flex flex-col lg:flex-1 lg:min-h-0">
      {/* Header & Interactive Controls */}
      <div className="shrink-0 px-5 py-3 border-b border-[#DCE9EE] dark:border-[#253F5B] bg-[#F5FAFB]/70 dark:bg-[#0B1728]/40 flex flex-col xl:flex-row xl:items-center xl:justify-between gap-2.5">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
            <Stethoscope className="h-4.5 w-4.5" />
          </div>
          <div>
            <h3 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9]">
              {t.adminTodayDoctorQueues}
            </h3>
            <p className="text-xs text-[#64748B] dark:text-[#A5B4C7]">
              {t.doctorsOverviewSubtitle}
            </p>
          </div>
        </div>

        {doctors.length > 0 && (
          <div className="flex flex-wrap items-center gap-2.5">
            {/* Search Box */}
            <div className="relative flex-1 min-w-44 sm:w-52 sm:flex-initial">
              <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={t.adminSearchDoctorPlaceholder}
                aria-label={t.adminSearchDoctorPlaceholder}
                className="w-full rounded-xl border border-[#DCE9EE] bg-white pl-8.5 pr-3 py-1.5 text-xs text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF]"
              />
            </div>

            {/* Interactive Status Filter Pills */}
            <div
              role="group"
              aria-label={t.status}
              className="inline-flex items-center rounded-xl border border-[#DCE9EE] bg-white p-0.5 dark:border-[#253F5B] dark:bg-[#12243A]"
            >
              {filterOptions.map((opt) => {
                const active = statusFilter === opt.key;
                return (
                  <button
                    key={opt.key}
                    type="button"
                    onClick={() => setStatusFilter(opt.key)}
                    aria-pressed={active}
                    className={`inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs font-semibold transition-colors cursor-pointer ${
                      active
                        ? 'bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]'
                        : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                    }`}
                  >
                    <span>{opt.label}</span>
                    <span className="tabular-nums opacity-80">{opt.count}</span>
                  </button>
                );
              })}
            </div>

            {/* Cards / Table View Toggle */}
            <div
              role="group"
              aria-label={t.actions}
              className="inline-flex items-center rounded-xl border border-[#DCE9EE] bg-white p-0.5 dark:border-[#253F5B] dark:bg-[#12243A]"
            >
              <button
                type="button"
                onClick={() => setViewMode('table')}
                aria-pressed={viewMode === 'table'}
                className={`inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs font-semibold transition-colors cursor-pointer ${
                  viewMode === 'table'
                    ? 'bg-[#E0F2FE] text-[#0369A1] dark:bg-[#10324F] dark:text-[#38BDF8]'
                    : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                }`}
              >
                <Table2 className="h-3.5 w-3.5" />
                <span>{t.adminViewTable}</span>
              </button>
              <button
                type="button"
                onClick={() => setViewMode('cards')}
                aria-pressed={viewMode === 'cards'}
                className={`inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs font-semibold transition-colors cursor-pointer ${
                  viewMode === 'cards'
                    ? 'bg-[#E0F2FE] text-[#0369A1] dark:bg-[#10324F] dark:text-[#38BDF8]'
                    : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                }`}
              >
                <LayoutGrid className="h-3.5 w-3.5" />
                <span>{t.adminViewCards}</span>
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Content */}
      {doctors.length === 0 ? (
        <div className="p-6">
          <EmptyState title={t.adminNoQueuesToday} compact />
        </div>
      ) : filteredDoctors.length === 0 ? (
        <div className="p-6">
          <EmptyState title={t.adminNoDoctorsMatchFilter} compact />
        </div>
      ) : viewMode === 'cards' ? (
        <div className="p-4 sm:p-5 lg:flex-1 lg:min-h-0 lg:overflow-y-auto grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 content-start">
          {filteredDoctors.map((doc) => {
            const docCompletionPct = calcShareValue(doc.completed_tickets, doc.total_tickets);
            return (
              <div
                key={doc.doctor_id}
                className="rounded-2xl border border-[#DCE9EE] bg-[#F5FAFB]/45 p-4.5 shadow-2xs transition-all duration-150 hover:border-[#0D9488]/45 hover:bg-white hover:shadow-xs motion-reduce:transition-none dark:border-[#253F5B] dark:bg-[#0B1728]/45 dark:hover:border-[#2DD4BF]/45 dark:hover:bg-[#162B42]"
              >
                <div className="flex items-start justify-between gap-2.5">
                  <div className="flex items-center gap-2.5 min-w-0">
                    <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
                      <UserRound className="h-4 w-4" />
                    </div>
                    <div className="min-w-0">
                      <h4 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9] truncate">
                        {doc.doctor_name}
                      </h4>
                      <p className="text-xs text-[#64748B] dark:text-[#A5B4C7] truncate">
                        {doc.specialization_name} •{' '}
                        {doc.room_number ? `${t.room} ${doc.room_number}` : '—'}
                      </p>
                    </div>
                  </div>

                  {doc.has_queue_today ? (
                    <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300 shrink-0">
                      <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                      {t.adminDoctorQueueStatusOpen}
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1.5 rounded-full bg-[#EDF6F8] px-2.5 py-0.5 text-[11px] font-semibold text-[#64748B] dark:bg-[#1A3047] dark:text-[#A5B4C7] shrink-0">
                      <span className="h-1.5 w-1.5 rounded-full bg-slate-400" />
                      {t.adminDoctorQueueStatusClosed}
                    </span>
                  )}
                </div>

                <div className="mt-3.5 grid grid-cols-3 gap-2 text-center">
                  <div className="rounded-xl border border-[#0284C7]/15 bg-[#E0F2FE]/65 p-2 dark:border-[#38BDF8]/20 dark:bg-[#10324F]/65">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-[#0369A1] dark:text-[#38BDF8] block truncate">
                      {t.waitingCount}
                    </span>
                    <p className="mt-0.5 text-base font-bold tabular-nums text-[#0284C7] dark:text-[#38BDF8]">
                      {doc.waiting_tickets}
                    </p>
                  </div>

                  <div className="rounded-xl border border-[#0D9488]/20 bg-[#DDF7F0]/65 p-2 dark:border-[#2DD4BF]/20 dark:bg-[#12353D]/70">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-[#0F766E] dark:text-[#2DD4BF] block truncate">
                      {t.servingCount}
                    </span>
                    <p className="mt-0.5 text-base font-bold tabular-nums text-[#0D9488] dark:text-[#2DD4BF]">
                      {doc.serving_tickets}
                    </p>
                  </div>

                  <div className="rounded-xl border border-emerald-200/80 bg-emerald-50/75 p-2 dark:border-emerald-800/40 dark:bg-emerald-950/35">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-700 dark:text-emerald-300 block truncate">
                      {t.completedCount}
                    </span>
                    <p className="mt-0.5 text-base font-bold tabular-nums text-emerald-700 dark:text-emerald-300">
                      {doc.completed_tickets}
                    </p>
                  </div>
                </div>

                {/* Per-Doctor Progress Bar */}
                <div className="mt-3 pt-2.5 border-t border-[#DCE9EE]/80 dark:border-[#253F5B]/80">
                  <div className="flex items-center justify-between text-[11px] font-semibold text-[#64748B] dark:text-[#A5B4C7]">
                    <span>
                      {doc.completed_tickets} / {doc.total_tickets} {t.adminTicketsSuffix}
                    </span>
                    <span className="tabular-nums text-[#0F766E] dark:text-[#2DD4BF]">
                      {formatPercent(docCompletionPct)}
                    </span>
                  </div>
                  <div className="mt-1.5 h-1.5 w-full rounded-full bg-[#DCE9EE]/80 dark:bg-[#1A3047] overflow-hidden">
                    <div
                      style={{ width: `${docCompletionPct}%` }}
                      className="h-full rounded-full bg-[#0D9488] dark:bg-[#2DD4BF] transition-[width] duration-300 ease-out motion-reduce:transition-none"
                    />
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="overflow-x-auto lg:flex-1 lg:min-h-0 lg:overflow-y-auto">
          <table className="w-full text-left border-collapse text-xs">
            <thead className="sticky top-0 z-10">
              <tr className="border-b border-[#DCE9EE] bg-[#F5FAFB] dark:border-[#253F5B] dark:bg-[#0B1728] text-[#64748B] dark:text-[#A5B4C7] uppercase tracking-wider font-bold text-[11px]">
                <th className="px-4 py-3 text-center w-10">#</th>
                <th className="px-4 py-3">{t.doctor}</th>
                <th className="px-4 py-3">{t.specialization}</th>
                <th className="px-4 py-3">{t.room}</th>
                <th className="px-4 py-3">{t.status}</th>
                <th className="px-4 py-3 min-w-44">{t.queueProgressColumn}</th>
                <th className="px-4 py-3 text-center">{t.waitingCount}</th>
                <th className="px-4 py-3 text-center">{t.servingCount}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#DCE9EE] dark:divide-[#253F5B] font-medium">
              {filteredDoctors.map((item, idx) => {
                const docPct = calcShareValue(item.completed_tickets, item.total_tickets);
                return (
                  <tr
                    key={item.doctor_id}
                    className="hover:bg-[#F5FAFB] dark:hover:bg-[#1A3047]/60 transition-colors"
                  >
                    <td className="px-4 py-3 text-center tabular-nums text-[#64748B] dark:text-[#A5B4C7]">
                      {idx + 1}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2.5">
                        <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
                          <UserRound className="h-3.5 w-3.5" />
                        </span>
                        <span className="font-bold text-[#14283F] dark:text-[#F1F5F9]">
                          {item.doctor_name}
                        </span>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-[#64748B] dark:text-[#A5B4C7]">
                      {item.specialization_name}
                    </td>
                    <td className="px-4 py-3 text-[#64748B] dark:text-[#A5B4C7] whitespace-nowrap">
                      {item.room_number ? `${t.room} ${item.room_number}` : '—'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      {item.has_queue_today ? (
                        <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300">
                          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                          {t.adminDoctorQueueStatusOpen}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 rounded-full bg-[#EDF6F8] px-2.5 py-0.5 text-[11px] font-semibold text-[#64748B] dark:bg-[#1A3047] dark:text-[#A5B4C7]">
                          <span className="h-1.5 w-1.5 rounded-full bg-slate-400" />
                          {t.adminDoctorQueueStatusClosed}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2.5">
                        <span className="w-12 shrink-0 text-[11px] font-bold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                          {item.completed_tickets} / {item.total_tickets}
                        </span>
                        <div className="h-2 flex-1 min-w-20 rounded-full bg-[#EDF6F8] dark:bg-[#1A3047] overflow-hidden">
                          <div
                            style={{ width: `${docPct}%` }}
                            className="h-full rounded-full bg-[#0D9488] dark:bg-[#2DD4BF] transition-[width] duration-300 ease-out motion-reduce:transition-none"
                          />
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <span className="inline-flex min-w-7 items-center justify-center rounded-full bg-[#DDF7F0] px-2 py-0.5 text-xs font-bold tabular-nums text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
                        {item.waiting_tickets}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center font-semibold tabular-nums text-[#0284C7] dark:text-[#38BDF8]">
                      {item.serving_tickets}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
};
