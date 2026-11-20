import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Calendar,
  CalendarClock,
  CheckCircle2,
  Clock,
  Download,
  History,
  Info,
  Layers,
  Stethoscope,
  TrendingUp,
} from 'lucide-react';
import {
  exportAdminDoctorPerformanceCsvApi,
  getAdminDoctorPerformanceApi,
} from '../../api/admin';
import { useI18n } from '../../i18n/useI18n';
import type { AdminDoctorPerformanceResponse, ReportingPeriod } from '../../types/admin';
import { AlertBanner } from '../../components/common/AlertBanner';
import { AppButton } from '../../components/common/AppButton';
import { EmptyState } from '../../components/common/EmptyState';
import { LoadingSkeleton } from '../../components/common/LoadingSkeleton';
import { PageHeader } from '../../components/common/PageHeader';
import { StatCard } from '../../components/common/StatCard';
import { StatusBadge } from '../../components/common/StatusBadge';

function formatTimestampInTz(iso: string | null, timeZone: string): string {
  if (!iso) return '—';
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return '—';
  try {
    return new Intl.DateTimeFormat(undefined, {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).format(parsed);
  } catch {
    return parsed.toISOString().slice(0, 16).replace('T', ' ');
  }
}

function formatDurationSeconds(seconds: number | null, legacyLabel: string): string {
  if (seconds === null || seconds === undefined) return legacyLabel;
  const totalMins = Math.round(seconds / 60);
  const h = Math.floor(totalMins / 60);
  const m = totalMins % 60;
  if (h <= 0) return `${m}m`;
  return `${h}h ${m}m`;
}

export const AdminDoctorHistoryPage: React.FC = () => {
  const { t, language } = useI18n();

  const [report, setReport] = useState<AdminDoctorPerformanceResponse | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isExporting, setIsExporting] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const [period, setPeriod] = useState<ReportingPeriod>('today');
  const [selectedDoctorId, setSelectedDoctorId] = useState<number | undefined>(undefined);
  const [selectedSpecId, setSelectedSpecId] = useState<number | undefined>(undefined);
  const [dateFrom, setDateFrom] = useState<string>(() => new Date().toISOString().slice(0, 10));
  const [dateTo, setDateTo] = useState<string>(() => new Date().toISOString().slice(0, 10));

  const fetchReport = useCallback(
    async (silent = false) => {
      if (!silent) setIsLoading(true);
      setError(null);
      try {
        const data = await getAdminDoctorPerformanceApi({
          doctor_id: selectedDoctorId,
          specialization_id: selectedSpecId,
          period,
          date_from: period === 'custom' ? dateFrom : undefined,
          date_to: period === 'custom' ? dateTo : undefined,
        });
        setReport(data);
      } catch (err: unknown) {
        setError(err instanceof Error ? err.message : t.errorGeneric);
      } finally {
        setIsLoading(false);
      }
    },
    [selectedDoctorId, selectedSpecId, period, dateFrom, dateTo, t.errorGeneric]
  );

  useEffect(() => {
    let isCancelled = false;

    getAdminDoctorPerformanceApi({
      doctor_id: selectedDoctorId,
      specialization_id: selectedSpecId,
      period,
      date_from: period === 'custom' ? dateFrom : undefined,
      date_to: period === 'custom' ? dateTo : undefined,
    })
      .then((data) => {
        if (!isCancelled) {
          setReport(data);
          setError(null);
        }
      })
      .catch((err: unknown) => {
        if (!isCancelled) {
          setError(err instanceof Error ? err.message : t.errorGeneric);
        }
      })
      .finally(() => {
        if (!isCancelled) {
          setIsLoading(false);
        }
      });

    return () => {
      isCancelled = true;
    };
  }, [selectedDoctorId, selectedSpecId, period, dateFrom, dateTo, language, t.errorGeneric]);

  useEffect(() => {
    const handleRefresh = () => {
      fetchReport(true);
    };
    window.addEventListener('admin:refresh', handleRefresh);
    return () => window.removeEventListener('admin:refresh', handleRefresh);
  }, [fetchReport]);

  const handleExportCsv = async () => {
    if (isExporting) return;
    setIsExporting(true);
    setError(null);
    try {
      await exportAdminDoctorPerformanceCsvApi({
        doctor_id: selectedDoctorId,
        specialization_id: selectedSpecId,
        period,
        date_from: period === 'custom' ? dateFrom : undefined,
        date_to: period === 'custom' ? dateTo : undefined,
      });
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t.errorGeneric);
    } finally {
      setIsExporting(false);
    }
  };

  const specializations = useMemo(() => {
    if (!report) return [];
    const seen = new Map<number, string>();
    report.doctors.forEach((d) => {
      if (d.specialization_id != null && !seen.has(d.specialization_id)) {
        seen.set(d.specialization_id, d.specialization_name);
      }
    });
    return Array.from(seen.entries()).map(([id, name]) => ({ id, name }));
  }, [report]);

  const maxDoctorAllTime = useMemo(() => {
    if (!report || report.doctors.length === 0) return 1;
    return Math.max(1, ...report.doctors.map((d) => d.completed_all_time));
  }, [report]);

  const periodOptions: { key: ReportingPeriod; label: string }[] = [
    { key: 'today', label: t.periodToday },
    { key: 'week', label: t.periodWeek },
    { key: 'month', label: t.periodMonth },
    { key: 'year', label: t.periodYear },
    { key: 'custom', label: t.periodCustom },
    { key: 'all', label: t.periodAllTime },
  ];

  const renderShiftStatusBadge = (statusStr: string, isPaused = false) => {
    if (isPaused || statusStr === 'PAUSED') {
      return <StatusBadge status="PAUSED" size="sm" />;
    }
    if (statusStr === 'OPEN' || statusStr === 'ACTIVE') {
      return <StatusBadge status="OPEN" size="sm" />;
    }
    if (statusStr === 'CLOSING') {
      return <StatusBadge status="CLOSING" size="sm" />;
    }
    if (statusStr === 'FINISHED') {
      return <StatusBadge status="FINISHED" size="sm" />;
    }
    return <StatusBadge status="NOT_OPEN" size="sm" />;
  };

  return (
    <div className="space-y-4 max-w-7xl mx-auto animate-dental-in">
      <PageHeader
        title={t.adminDoctorHistoryTitle}
        subtitle={
          report
            ? `${t.adminDoctorHistorySubtitle} • ${report.clinic_timezone}`
            : t.adminDoctorHistorySubtitle
        }
        icon={<History className="h-5 w-5" />}
        actions={
          <AppButton
            variant="secondary"
            size="sm"
            loading={isExporting}
            disabled={isLoading || !report}
            onClick={handleExportCsv}
            icon={<Download className="h-4 w-4 text-[#0D9488] dark:text-[#2DD4BF]" />}
          >
            {isExporting ? t.exportingCsv : t.exportCsv}
          </AppButton>
        }
      />

      {error && <AlertBanner type="error" message={error} onClose={() => setError(null)} />}

      {/* Filter Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-[#DCE9EE] bg-white p-3.5 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
        <div
          role="group"
          aria-label={t.periodCustom}
          className="inline-flex flex-wrap items-center gap-1 rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] p-1 dark:border-[#253F5B] dark:bg-[#0B1728]/70"
        >
          {periodOptions.map((opt) => {
            const active = period === opt.key;
            return (
              <button
                key={opt.key}
                type="button"
                aria-pressed={active}
                onClick={() => setPeriod(opt.key)}
                className={`rounded-lg px-2.5 py-1 text-xs font-semibold transition-colors cursor-pointer ${
                  active
                    ? 'bg-[#0D9488] text-white shadow-2xs dark:bg-[#14B8A6] dark:text-[#07131D]'
                    : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                }`}
              >
                {opt.label}
              </button>
            );
          })}
        </div>

        <div className="flex flex-wrap items-center gap-2.5">
          <select
            aria-label={t.doctor}
            value={selectedDoctorId ?? ''}
            onChange={(e) =>
              setSelectedDoctorId(e.target.value ? Number(e.target.value) : undefined)
            }
            className="rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3 py-1.5 text-xs font-semibold text-[#14283F] focus:border-[#0D9488] focus:outline-hidden dark:border-[#253F5B] dark:bg-[#0B1728] dark:text-[#F1F5F9]"
          >
            <option value="">{t.allDoctors}</option>
            {(report?.doctors ?? []).map((d) => (
              <option key={d.doctor_id} value={d.doctor_id}>
                {d.doctor_name}
              </option>
            ))}
          </select>

          {specializations.length > 1 && (
            <select
              aria-label={t.filterBySpecialization}
              value={selectedSpecId ?? ''}
              onChange={(e) =>
                setSelectedSpecId(e.target.value ? Number(e.target.value) : undefined)
              }
              className="rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3 py-1.5 text-xs font-semibold text-[#14283F] focus:border-[#0D9488] focus:outline-hidden dark:border-[#253F5B] dark:bg-[#0B1728] dark:text-[#F1F5F9]"
            >
              <option value="">{t.allSpecializations}</option>
              {specializations.map((sp) => (
                <option key={sp.id} value={sp.id}>
                  {sp.name}
                </option>
              ))}
            </select>
          )}

          {period === 'custom' && (
            <div className="flex items-center gap-2">
              <label className="flex items-center gap-1 text-xs font-medium text-[#64748B] dark:text-[#A5B4C7]">
                <span>{t.dateFromLabel}</span>
                <input
                  type="date"
                  value={dateFrom}
                  onChange={(e) => setDateFrom(e.target.value)}
                  className="rounded-lg border border-[#DCE9EE] bg-[#F5FAFB] px-2 py-1 text-xs text-[#14283F] dark:border-[#253F5B] dark:bg-[#0B1728] dark:text-[#F1F5F9]"
                />
              </label>
              <label className="flex items-center gap-1 text-xs font-medium text-[#64748B] dark:text-[#A5B4C7]">
                <span>{t.dateToLabel}</span>
                <input
                  type="date"
                  value={dateTo}
                  onChange={(e) => setDateTo(e.target.value)}
                  className="rounded-lg border border-[#DCE9EE] bg-[#F5FAFB] px-2 py-1 text-xs text-[#14283F] dark:border-[#253F5B] dark:bg-[#0B1728] dark:text-[#F1F5F9]"
                />
              </label>
            </div>
          )}
        </div>
      </div>

      {isLoading ? (
        <LoadingSkeleton cards={5} rows={4} />
      ) : report ? (
        <>
          {/* 5 KPI Summary Cards */}
          <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-5 gap-3">
            <StatCard
              label={t.completedTodayLabel}
              value={report.summary.completed_today}
              tone="teal"
              icon={<CheckCircle2 className="h-4.5 w-4.5" />}
            />
            <StatCard
              label={t.completedWeekLabel}
              value={report.summary.completed_this_week}
              tone="blue"
              icon={<Calendar className="h-4.5 w-4.5" />}
            />
            <StatCard
              label={t.completedMonthLabel}
              value={report.summary.completed_this_month}
              tone="blue"
              icon={<TrendingUp className="h-4.5 w-4.5" />}
            />
            <StatCard
              label={t.completedYearLabel}
              value={report.summary.completed_this_year}
              tone="emerald"
              icon={<Layers className="h-4.5 w-4.5" />}
            />
            <StatCard
              label={t.completedAllTimeLabel}
              value={report.summary.completed_all_time}
              tone="neutral"
              icon={<CalendarClock className="h-4.5 w-4.5" />}
              subValue={`${t.completedSelectedRangeLabel}: ${report.summary.completed_in_selected_range}`}
            />
          </div>

          {report.summary.legacy_unattributed_completed_count > 0 && (
            <div className="flex items-start gap-2.5 rounded-xl border border-amber-200 bg-amber-50/75 px-3.5 py-2.5 text-xs text-amber-900 dark:border-amber-800/60 dark:bg-amber-950/35 dark:text-amber-200">
              <Info className="h-4 w-4 shrink-0 mt-0.5 text-amber-600 dark:text-amber-400" />
              <span>
                {t.legacyNoTimestampNote.replace(
                  '{count}',
                  String(report.summary.legacy_unattributed_completed_count)
                )}
              </span>
            </div>
          )}

          {/* Doctor Performance Summary Table */}
          <div className="rounded-2xl border border-[#DCE9EE] bg-white shadow-2xs overflow-hidden dark:border-[#253F5B] dark:bg-[#12243A]">
            <div className="flex items-center justify-between px-4 py-3 border-b border-[#DCE9EE] dark:border-[#253F5B]">
              <div className="flex items-center gap-2">
                <Stethoscope className="h-4 w-4 text-[#0D9488] dark:text-[#2DD4BF]" />
                <h2 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.doctorPerformanceSummaryTitle}
                </h2>
              </div>
              <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7]">
                {report.doctors.length} {t.adminNavDoctors.toLowerCase()}
              </span>
            </div>

            {report.doctors.length === 0 ? (
              <div className="p-6">
                <EmptyState title={t.noDoctorsFound} description={t.adminNoDoctorsMatchFilter} />
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead>
                    <tr className="border-b border-[#DCE9EE] bg-[#F5FAFB] text-[11px] font-bold uppercase tracking-wider text-[#64748B] dark:border-[#253F5B] dark:bg-[#0B1728]/60 dark:text-[#A5B4C7]">
                      <th className="px-4 py-2.5">{t.doctor}</th>
                      <th className="px-3 py-2.5">{t.specialization}</th>
                      <th className="px-3 py-2.5">{t.currentShiftLabel}</th>
                      <th className="px-3 py-2.5 text-right">{t.periodToday}</th>
                      <th className="px-3 py-2.5 text-right">{t.periodWeek}</th>
                      <th className="px-3 py-2.5 text-right">{t.periodMonth}</th>
                      <th className="px-3 py-2.5 text-right">{t.periodYear}</th>
                      <th className="px-3 py-2.5 text-right">{t.completedAllTimeLabel}</th>
                      <th className="px-3 py-2.5 text-right">{t.avgShiftDurationLabel}</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#DCE9EE]/70 dark:divide-[#253F5B]/70">
                    {report.doctors.map((doc) => {
                      const pct = Math.round((doc.completed_all_time / maxDoctorAllTime) * 100);
                      const isSelected = selectedDoctorId === doc.doctor_id;
                      return (
                        <tr
                          key={doc.doctor_id}
                          onClick={() =>
                            setSelectedDoctorId((prev) =>
                              prev === doc.doctor_id ? undefined : doc.doctor_id
                            )
                          }
                          className={`transition-colors cursor-pointer ${
                            isSelected
                              ? 'bg-[#DDF7F0]/55 dark:bg-[#12353D]/60'
                              : 'hover:bg-[#F5FAFB] dark:hover:bg-[#0B1728]/45'
                          }`}
                        >
                          <td className="px-4 py-2.5 font-semibold text-[#14283F] dark:text-[#F1F5F9] whitespace-nowrap">
                            <div>{doc.doctor_name}</div>
                            {doc.room_number && (
                              <span className="text-[11px] font-normal text-[#64748B] dark:text-[#A5B4C7]">
                                {t.room} {doc.room_number}
                              </span>
                            )}
                          </td>
                          <td className="px-3 py-2.5 text-[#0F766E] dark:text-[#2DD4BF] whitespace-nowrap">
                            {doc.specialization_name}
                          </td>
                          <td className="px-3 py-2.5 whitespace-nowrap">
                            {renderShiftStatusBadge(doc.current_shift_status)}
                          </td>
                          <td className="px-3 py-2.5 text-right font-bold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                            {doc.completed_today}
                          </td>
                          <td className="px-3 py-2.5 text-right font-semibold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                            {doc.completed_this_week}
                          </td>
                          <td className="px-3 py-2.5 text-right font-semibold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                            {doc.completed_this_month}
                          </td>
                          <td className="px-3 py-2.5 text-right font-semibold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                            {doc.completed_this_year}
                          </td>
                          <td className="px-3 py-2.5 text-right">
                            <div className="flex items-center justify-end gap-2">
                              <div className="hidden sm:block w-16 h-1.5 rounded-full bg-[#EDF6F8] dark:bg-[#1A3047] overflow-hidden">
                                <div
                                  className="h-full rounded-full bg-[#0D9488] dark:bg-[#2DD4BF]"
                                  style={{ width: `${pct}%` }}
                                />
                              </div>
                              <span className="font-black tabular-nums text-[#0F766E] dark:text-[#2DD4BF]">
                                {doc.completed_all_time}
                              </span>
                            </div>
                          </td>
                          <td className="px-3 py-2.5 text-right tabular-nums text-[#64748B] dark:text-[#A5B4C7] whitespace-nowrap">
                            {doc.avg_shift_duration_minutes !== null
                              ? `${doc.avg_shift_duration_minutes}m`
                              : '—'}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Shift Session History Table */}
          <div className="rounded-2xl border border-[#DCE9EE] bg-white shadow-2xs overflow-hidden dark:border-[#253F5B] dark:bg-[#12243A]">
            <div className="flex items-center justify-between px-4 py-3 border-b border-[#DCE9EE] dark:border-[#253F5B]">
              <div className="flex items-center gap-2">
                <Clock className="h-4 w-4 text-[#0284C7] dark:text-[#38BDF8]" />
                <h2 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.shiftHistoryTitle}
                </h2>
              </div>
              <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7]">
                {report.shifts.length} {t.shiftHistoryTitle.toLowerCase()}
              </span>
            </div>

            {report.shifts.length === 0 ? (
              <div className="p-6">
                <EmptyState
                  title={t.noShiftHistoryFound}
                  description={t.adminDoctorHistorySubtitle}
                />
              </div>
            ) : (
              <div className="max-h-96 overflow-auto">
                <table className="w-full text-left border-collapse text-xs">
                  <thead className="sticky top-0 z-10 bg-[#F5FAFB] dark:bg-[#0B1728]">
                    <tr className="border-b border-[#DCE9EE] text-[11px] font-bold uppercase tracking-wider text-[#64748B] dark:border-[#253F5B] dark:text-[#A5B4C7]">
                      <th className="px-4 py-2.5">{t.doctor}</th>
                      <th className="px-3 py-2.5">{t.specialization}</th>
                      <th className="px-3 py-2.5">{t.status}</th>
                      <th className="px-3 py-2.5">{t.shiftStartTimeCol}</th>
                      <th className="px-3 py-2.5">{t.shiftEndTimeCol}</th>
                      <th className="px-3 py-2.5 text-right">{t.shiftDurationLabel}</th>
                      <th className="px-3 py-2.5 text-right">{t.totalIssuedLabel}</th>
                      <th className="px-3 py-2.5 text-right">{t.completedCount}</th>
                      <th className="px-3 py-2.5 text-right">{t.skippedCount}</th>
                      <th className="px-3 py-2.5 text-right">{t.adminKpiCancelled}</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#DCE9EE]/70 dark:divide-[#253F5B]/70">
                    {report.shifts.map((s) => (
                      <tr
                        key={s.queue_id}
                        className="hover:bg-[#F5FAFB] dark:hover:bg-[#0B1728]/45 transition-colors"
                      >
                        <td className="px-4 py-2.5 font-semibold text-[#14283F] dark:text-[#F1F5F9] whitespace-nowrap">
                          <div>{s.doctor_name}</div>
                          <span className="text-[11px] font-mono font-normal text-[#64748B] dark:text-[#A5B4C7]">
                            #{s.queue_id} • {s.queue_date}
                          </span>
                        </td>
                        <td className="px-3 py-2.5 text-[#0F766E] dark:text-[#2DD4BF] whitespace-nowrap">
                          {s.specialization_name}
                        </td>
                        <td className="px-3 py-2.5 whitespace-nowrap">
                          <div className="flex items-center gap-1.5">
                            {renderShiftStatusBadge(s.shift_status, s.is_paused)}
                            {s.is_paused && s.shift_status === 'CLOSING' && (
                              <StatusBadge status="CLOSING" size="sm" />
                            )}
                          </div>
                        </td>
                        <td className="px-3 py-2.5 whitespace-nowrap font-mono text-[11px] text-[#14283F] dark:text-[#F1F5F9]">
                          {s.started_at
                            ? formatTimestampInTz(s.started_at, report.clinic_timezone)
                            : `${s.queue_date} (${t.legacyDurationLabel})`}
                        </td>
                        <td className="px-3 py-2.5 whitespace-nowrap font-mono text-[11px] text-[#64748B] dark:text-[#A5B4C7]">
                          {formatTimestampInTz(s.ended_at, report.clinic_timezone)}
                        </td>
                        <td className="px-3 py-2.5 text-right tabular-nums text-[#64748B] dark:text-[#A5B4C7] whitespace-nowrap">
                          {formatDurationSeconds(s.duration_seconds, t.legacyDurationLabel)}
                        </td>
                        <td className="px-3 py-2.5 text-right font-semibold tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
                          {s.total_tickets}
                        </td>
                        <td className="px-3 py-2.5 text-right font-bold tabular-nums text-emerald-700 dark:text-emerald-300">
                          {s.completed_count}
                        </td>
                        <td className="px-3 py-2.5 text-right tabular-nums text-rose-700 dark:text-rose-300">
                          {s.skipped_count}
                        </td>
                        <td className="px-3 py-2.5 text-right tabular-nums text-[#64748B] dark:text-[#A5B4C7]">
                          {s.cancelled_count}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      ) : null}
    </div>
  );
};
