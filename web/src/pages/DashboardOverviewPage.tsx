import React, { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Activity,
  CheckCircle2,
  Clock,
  DoorClosed,
  LayoutDashboard,
  PhoneCall,
  PlayCircle,
  PlusCircle,
  Search,
  UserCheck,
} from 'lucide-react';
import {
  fetchDoctors,
  fetchReceptionTodayQueues,
  fetchSpecializations,
  openDoctorQueue,
} from '../api/reception';
import { useAuth } from '../context/useAuth';
import { useI18n } from '../i18n/useI18n';
import type { Doctor, ReceptionQueueOverview, Specialization } from '../types/reception';
import { AlertBanner } from '../components/common/AlertBanner';
import { AppButton } from '../components/common/AppButton';
import { EmptyState } from '../components/common/EmptyState';
import { LoadingSkeleton } from '../components/common/LoadingSkeleton';
import { PageHeader } from '../components/common/PageHeader';
import { StatCard } from '../components/common/StatCard';
import { StatusBadge } from '../components/common/StatusBadge';

export const DashboardOverviewPage: React.FC = () => {
  const { user } = useAuth();
  const { language, t } = useI18n();
  const navigate = useNavigate();

  const [doctors, setDoctors] = useState<Doctor[]>([]);
  const [specializations, setSpecializations] = useState<Record<number, string>>({});
  const [todayQueues, setTodayQueues] = useState<ReceptionQueueOverview[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [openingDoctorId, setOpeningDoctorId] = useState<number | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'ALL' | 'ACTIVE' | 'PAUSED' | 'NOT_OPEN'>('ALL');
  const [notice, setNotice] = useState<{ type: 'error' | 'success'; message: string } | null>(null);

  const clinicId = user?.clinic_id || 1;

  const loadData = useCallback(
    async (showLoading = false) => {
      if (showLoading) setIsLoading(true);
      try {
        const [doctorsData, specsData, queuesData] = await Promise.all([
          fetchDoctors(clinicId),
          fetchSpecializations(clinicId),
          fetchReceptionTodayQueues(),
        ]);

        const specMap: Record<number, string> = {};
        specsData.forEach((s: Specialization) => {
          specMap[s.id] = s.name;
        });

        setDoctors(doctorsData);
        setSpecializations(specMap);
        setTodayQueues(queuesData);
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : t.errorGeneric;
        setNotice({ type: 'error', message: msg });
      } finally {
        setIsLoading(false);
      }
    },
    [clinicId, t.errorGeneric]
  );

  useEffect(() => {
    let isCancelled = false;

    Promise.all([
      fetchDoctors(clinicId),
      fetchSpecializations(clinicId),
      fetchReceptionTodayQueues(),
    ])
      .then(([doctorsData, specsData, queuesData]) => {
        if (isCancelled) return;
        const specMap: Record<number, string> = {};
        specsData.forEach((s: Specialization) => {
          specMap[s.id] = s.name;
        });
        setDoctors(doctorsData);
        setSpecializations(specMap);
        setTodayQueues(queuesData);
      })
      .catch((err: unknown) => {
        if (isCancelled) return;
        const msg = err instanceof Error ? err.message : t.errorGeneric;
        setNotice({ type: 'error', message: msg });
      })
      .finally(() => {
        if (!isCancelled) {
          setIsLoading(false);
        }
      });

    const handleRefresh = () => {
      loadData(false);
    };

    window.addEventListener('reception:refresh', handleRefresh);
    return () => {
      isCancelled = true;
      window.removeEventListener('reception:refresh', handleRefresh);
    };
  }, [clinicId, language, loadData, t.errorGeneric]);

  const handleOpenQueue = async (doctor: Doctor) => {
    if (openingDoctorId !== null) return;
    setOpeningDoctorId(doctor.id);
    setNotice(null);

    try {
      await openDoctorQueue(doctor.id);
      setNotice({ type: 'success', message: `${doctor.full_name}: ${t.openQueueSuccess}` });
      const updatedQueues = await fetchReceptionTodayQueues();
      setTodayQueues(updatedQueues);
    } catch (err: unknown) {
      if (err instanceof Error && err.message.includes('409')) {
        setNotice({ type: 'error', message: t.openQueueAlreadyExists });
        const updatedQueues = await fetchReceptionTodayQueues();
        setTodayQueues(updatedQueues);
      } else {
        const msg = err instanceof Error ? err.message : t.errorGeneric;
        setNotice({ type: 'error', message: msg });
      }
    } finally {
      setOpeningDoctorId(null);
    }
  };

  const doctorQueueMap = new Map<number, ReceptionQueueOverview>();
  todayQueues.forEach((q) => {
    doctorQueueMap.set(q.doctor.id, q);
  });

  const totalWaiting = todayQueues.reduce((sum, q) => sum + q.waiting_count, 0);
  const totalCalled = todayQueues.reduce((sum, q) => sum + q.called_count, 0);
  const totalServing = todayQueues.reduce((sum, q) => sum + q.serving_count, 0);
  const totalCompleted = todayQueues.reduce((sum, q) => sum + (q.completed_count ?? 0), 0);

  const filteredDoctors = doctors.filter((doctor) => {
    const queue = doctorQueueMap.get(doctor.id);
    const docStatus = queue ? (queue.is_paused ? 'PAUSED' : 'ACTIVE') : 'NOT_OPEN';
    if (statusFilter !== 'ALL' && docStatus !== statusFilter) return false;
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    const specName = (specializations[doctor.specialization_id] || '').toLowerCase();
    return (
      doctor.full_name.toLowerCase().includes(q) ||
      specName.includes(q) ||
      (doctor.room_number || '').toLowerCase().includes(q)
    );
  });

  return (
    <div className="space-y-4 lg:space-y-0 lg:h-[calc(100vh-6rem)] lg:flex lg:flex-col lg:gap-4 max-w-7xl mx-auto animate-dental-in">
      <PageHeader
        title={t.dashboard}
        subtitle={t.doctorsOverviewSubtitle}
        icon={<LayoutDashboard className="h-5 w-5" />}
      />

      {notice && (
        <AlertBanner
          type={notice.type}
          message={notice.message}
          onClose={() => setNotice(null)}
        />
      )}

      {/* KPI Cards */}
      <div className="shrink-0 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3.5">
        <StatCard
          variant="tinted"
          label={t.totalQueues}
          value={todayQueues.length}
          subValue={`/ ${doctors.length}`}
          icon={<Activity className="h-4.5 w-4.5" />}
          tone="teal"
        />
        <StatCard
          variant="tinted"
          label={t.totalWaiting}
          value={totalWaiting}
          icon={<Clock className="h-4.5 w-4.5" />}
          tone="blue"
        />
        <StatCard
          variant="tinted"
          label={t.totalCalled}
          value={totalCalled}
          icon={<PhoneCall className="h-4.5 w-4.5" />}
          tone="amber"
        />
        <StatCard
          variant="tinted"
          label={t.totalServing}
          value={totalServing}
          icon={<UserCheck className="h-4.5 w-4.5" />}
          tone="teal"
        />
        <StatCard
          variant="tinted"
          label={t.totalCompleted}
          value={totalCompleted}
          icon={<CheckCircle2 className="h-4.5 w-4.5" />}
          tone="emerald"
        />
      </div>

      {/* Doctors & Today's Queues Bento Station Grid */}
      <div className="lg:flex-1 lg:min-h-0 flex flex-col rounded-3xl border border-[#DCE9EE] bg-white shadow-2xs overflow-hidden dark:border-[#253F5B] dark:bg-[#12243A]">
        <div className="shrink-0 border-b border-[#DCE9EE] bg-[#F5FAFB]/70 px-6 py-4 dark:border-[#253F5B] dark:bg-[#0B1728]/40 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3.5">
          <div>
            <h3 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9]">
              {t.doctorsOverviewTitle}
            </h3>
            <p className="text-xs text-[#64748B] dark:text-[#A5B4C7] mt-0.5">
              {clinicId ? `${t.clinicLabel} #${clinicId}` : ''} • {filteredDoctors.length}
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-2.5">
            <div className="relative flex-1 sm:w-56">
              <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={t.adminSearch}
                className="w-full rounded-xl border border-[#DCE9EE] bg-white py-1.5 pl-8 pr-3 text-xs text-[#14283F] placeholder-[#64748B]/70 focus:border-[#0D9488] focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/60"
              />
            </div>

            <div className="inline-flex rounded-xl border border-[#DCE9EE] bg-white p-1 dark:border-[#253F5B] dark:bg-[#1A3047]">
              {(
                [
                  { id: 'ALL', label: t.allStatuses },
                  { id: 'ACTIVE', label: t.queueStateActive },
                  { id: 'PAUSED', label: t.queueStatePaused },
                  { id: 'NOT_OPEN', label: t.queueStateNotOpen },
                ] as const
              ).map((tab) => (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => setStatusFilter(tab.id)}
                  className={`rounded-lg px-2.5 py-1 text-[11px] font-semibold transition-colors cursor-pointer ${
                    statusFilter === tab.id
                      ? 'bg-[#0D9488] text-white dark:bg-[#14B8A6] dark:text-[#07131D]'
                      : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        {isLoading ? (
          <div className="p-6">
            <LoadingSkeleton rows={4} />
          </div>
        ) : filteredDoctors.length === 0 ? (
          <div className="p-6">
            <EmptyState title={t.noDoctorsFound} compact />
          </div>
        ) : (
          <div className="p-4 sm:p-5 lg:flex-1 lg:min-h-0 lg:overflow-y-auto grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 content-start">
            {filteredDoctors.map((doctor) => {
              const queue = doctorQueueMap.get(doctor.id);
              const isOpening = openingDoctorId === doctor.id;
              const specializationName =
                specializations[doctor.specialization_id] || t.noData;
              const accentClass = !queue
                ? 'border-l-slate-300 dark:border-l-slate-600'
                : queue.is_paused
                  ? 'border-l-amber-500'
                  : 'border-l-[#0D9488] dark:border-l-[#2DD4BF]';

              return (
                <div
                  key={doctor.id}
                  className={`flex flex-col justify-between rounded-2xl border border-[#DCE9EE] border-l-4 ${accentClass} bg-[#F5FAFB]/55 p-4.5 shadow-2xs transition-all hover:bg-white dark:border-[#253F5B] dark:bg-[#0B1728]/55 dark:hover:bg-[#1A3047]/65`}
                >
                  <div>
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <h4
                          className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9] truncate"
                          title={doctor.full_name}
                        >
                          {doctor.full_name}
                        </h4>
                        <p className="text-xs font-medium text-[#0F766E] dark:text-[#2DD4BF] mt-0.5 truncate">
                          {specializationName}
                        </p>
                      </div>
                      {queue ? (
                        <div className="flex flex-wrap items-center justify-end gap-1">
                          <StatusBadge
                            status={queue.shift_status === 'CLOSING' ? 'CLOSING' : 'OPEN'}
                            size="sm"
                          />
                          {queue.is_paused && <StatusBadge status="PAUSED" size="sm" />}
                        </div>
                      ) : (
                        <StatusBadge status="NOT_OPEN" size="sm" />
                      )}
                    </div>

                    <div className="mt-3.5 flex flex-wrap items-center gap-2 text-xs">
                      <span className="inline-flex items-center gap-1 rounded-lg bg-white border border-[#DCE9EE] px-2.5 py-1 font-semibold text-[#14283F] dark:bg-[#12243A] dark:border-[#253F5B] dark:text-[#F1F5F9]">
                        <DoorClosed className="h-3.5 w-3.5 text-[#0284C7] dark:text-[#38BDF8]" />
                        {doctor.room_number ? `${t.room} ${doctor.room_number}` : '—'}
                      </span>

                      {queue && (
                        <>
                          <span className="inline-flex items-center gap-1 rounded-lg bg-[#E0F2FE] px-2.5 py-1 font-bold tabular-nums text-[#0369A1] dark:bg-[#10324F] dark:text-[#38BDF8]">
                            {t.waitingCount}: {queue.waiting_count}
                          </span>
                          <span className="inline-flex items-center gap-1 rounded-lg bg-emerald-50 px-2.5 py-1 font-bold tabular-nums text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300">
                            {t.completedCount}: {queue.completed_count ?? 0}
                          </span>
                        </>
                      )}
                    </div>
                  </div>

                  <div className="mt-4 pt-3 border-t border-[#DCE9EE] dark:border-[#253F5B]">
                    {queue ? (
                      <AppButton
                        variant="secondary"
                        size="sm"
                        className="w-full"
                        icon={<PlayCircle className="h-3.5 w-3.5 text-[#0D9488] dark:text-[#2DD4BF]" />}
                        onClick={() =>
                          navigate(`/reception/manage?queueId=${queue.queue_id}`)
                        }
                      >
                        {t.manageQueue}
                      </AppButton>
                    ) : (
                      <AppButton
                        variant="primary"
                        size="sm"
                        className="w-full"
                        loading={isOpening}
                        icon={<PlusCircle className="h-3.5 w-3.5" />}
                        onClick={() => handleOpenQueue(doctor)}
                      >
                        {isOpening ? t.openingQueue : t.startShift}
                      </AppButton>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
