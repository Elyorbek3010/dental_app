import React, { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Activity,
  AlertCircle,
  Clock,
  DoorClosed,
  PlayCircle,
  PlusCircle,
  UserCheck,
  Users,
} from 'lucide-react';
import { fetchDoctors, fetchReceptionTodayQueues, fetchSpecializations, openDoctorQueue } from '../api/reception';
import { useAuth } from '../context/useAuth';
import { useI18n } from '../i18n/useI18n';
import type { Doctor, ReceptionQueueOverview, Specialization } from '../types/reception';
import { StatusBadge } from '../components/common/StatusBadge';
import { AlertBanner } from '../components/common/AlertBanner';

export const DashboardOverviewPage: React.FC = () => {
  const { user } = useAuth();
  const { language, t } = useI18n();
  const navigate = useNavigate();

  const [doctors, setDoctors] = useState<Doctor[]>([]);
  const [specializations, setSpecializations] = useState<Record<number, string>>({});
  const [todayQueues, setTodayQueues] = useState<ReceptionQueueOverview[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [openingDoctorId, setOpeningDoctorId] = useState<number | null>(null);
  const [notice, setNotice] = useState<{ type: 'error' | 'success'; message: string } | null>(null);

  const clinicId = user?.clinic_id || 1;

  const loadData = useCallback(async (showLoading = false) => {
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
  }, [clinicId, t.errorGeneric]);

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
      // Refresh queues list to reflect newly active queue
      const updatedQueues = await fetchReceptionTodayQueues();
      setTodayQueues(updatedQueues);
    } catch (err: unknown) {
      if (err instanceof Error && err.message.includes('409')) {
        setNotice({ type: 'error', message: t.openQueueAlreadyExists });
        // Refresh anyway to sync
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

  // Build doctor queue map
  const doctorQueueMap = new Map<number, ReceptionQueueOverview>();
  todayQueues.forEach((q) => {
    doctorQueueMap.set(q.doctor.id, q);
  });

  // Calculate totals
  const totalWaiting = todayQueues.reduce((sum, q) => sum + q.waiting_count, 0);
  const totalCalled = todayQueues.reduce((sum, q) => sum + q.called_count, 0);
  const totalServing = todayQueues.reduce((sum, q) => sum + q.serving_count, 0);

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* Page Title */}
      <div>
        <h2 className="text-xl font-bold text-zinc-900 dark:text-zinc-100">
          {t.dashboard}
        </h2>
        <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
          {t.doctorsOverviewSubtitle}
        </p>
      </div>

      {notice && (
        <AlertBanner
          type={notice.type}
          message={notice.message}
          onClose={() => setNotice(null)}
        />
      )}

      {/* KPI Cards Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Total Active Queues */}
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
              {t.totalQueues}
            </span>
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-indigo-50 text-indigo-600 dark:bg-indigo-950/60 dark:text-indigo-400">
              <Activity className="h-5 w-5" />
            </div>
          </div>
          <div className="mt-3 flex items-baseline gap-2">
            <span className="text-2xl font-black text-zinc-900 dark:text-zinc-100">
              {todayQueues.length}
            </span>
            <span className="text-xs text-zinc-500">
              / {doctors.length} {t.doctor.toLowerCase()}
            </span>
          </div>
        </div>

        {/* Total Waiting */}
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
              {t.totalWaiting}
            </span>
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-blue-50 text-blue-600 dark:bg-blue-950/60 dark:text-blue-400">
              <Clock className="h-5 w-5" />
            </div>
          </div>
          <div className="mt-3">
            <span className="text-2xl font-black text-blue-600 dark:text-blue-400">
              {totalWaiting}
            </span>
          </div>
        </div>

        {/* Total Called */}
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
              {t.totalCalled}
            </span>
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-amber-50 text-amber-600 dark:bg-amber-950/60 dark:text-amber-400">
              <Users className="h-5 w-5" />
            </div>
          </div>
          <div className="mt-3">
            <span className="text-2xl font-black text-amber-600 dark:text-amber-400">
              {totalCalled}
            </span>
          </div>
        </div>

        {/* Total Serving */}
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold uppercase tracking-wider text-zinc-500 dark:text-zinc-400">
              {t.totalServing}
            </span>
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600 dark:bg-emerald-950/60 dark:text-emerald-400">
              <UserCheck className="h-5 w-5" />
            </div>
          </div>
          <div className="mt-3">
            <span className="text-2xl font-black text-emerald-600 dark:text-emerald-400">
              {totalServing}
            </span>
          </div>
        </div>
      </div>

      {/* Today's Doctors & Queues Table */}
      <div className="rounded-2xl border border-zinc-200 bg-white shadow-2xs overflow-hidden dark:border-zinc-800 dark:bg-zinc-900">
        <div className="border-b border-zinc-200 bg-zinc-50/50 px-6 py-4 dark:border-zinc-800 dark:bg-zinc-900/50 flex items-center justify-between">
          <div>
            <h3 className="text-sm font-bold text-zinc-900 dark:text-zinc-100">
              {t.doctorsOverviewTitle}
            </h3>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-0.5">
              {clinicId ? `${t.clinicLabel} #${clinicId}` : ''}
            </p>
          </div>
        </div>

        {isLoading ? (
          <div className="p-12 text-center">
            <div className="inline-block h-8 w-8 animate-spin rounded-full border-3 border-indigo-600 border-t-transparent" />
            <p className="mt-2 text-xs text-zinc-500 dark:text-zinc-400">{t.loading}</p>
          </div>
        ) : doctors.length === 0 ? (
          <div className="p-12 text-center text-zinc-500 dark:text-zinc-400">
            <AlertCircle className="mx-auto h-8 w-8 text-zinc-400 mb-2" />
            <p className="text-sm font-medium">{t.noDoctorsFound}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-zinc-200 bg-zinc-50 text-[11px] font-bold uppercase tracking-wider text-zinc-500 dark:border-zinc-800 dark:bg-zinc-800/40 dark:text-zinc-400">
                <tr>
                  <th scope="col" className="px-6 py-3.5">
                    {t.doctor}
                  </th>
                  <th scope="col" className="px-6 py-3.5">
                    {t.specialization}
                  </th>
                  <th scope="col" className="px-6 py-3.5">
                    {t.room}
                  </th>
                  <th scope="col" className="px-6 py-3.5">
                    {t.status}
                  </th>
                  <th scope="col" className="px-6 py-3.5 text-center">
                    {t.waitingCount}
                  </th>
                  <th scope="col" className="px-6 py-3.5 text-right">
                    {t.actions}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
                {doctors.map((doctor) => {
                  const queue = doctorQueueMap.get(doctor.id);
                  const isOpening = openingDoctorId === doctor.id;
                  const specializationName =
                    specializations[doctor.specialization_id] || t.noData;

                  return (
                    <tr
                      key={doctor.id}
                      className="hover:bg-zinc-50/80 dark:hover:bg-zinc-800/50 transition-colors"
                    >
                      {/* Doctor Name */}
                      <td className="px-6 py-4 font-semibold text-zinc-900 dark:text-zinc-100 whitespace-nowrap">
                        {doctor.full_name}
                      </td>

                      {/* Specialization */}
                      <td className="px-6 py-4 text-zinc-600 dark:text-zinc-400 whitespace-nowrap">
                        {specializationName}
                      </td>

                      {/* Room */}
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className="inline-flex items-center gap-1.5 rounded-lg bg-zinc-100 px-2 py-0.5 text-xs font-medium text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                          <DoorClosed className="h-3.5 w-3.5 text-zinc-400" />
                          {doctor.room_number ? `${t.room} ${doctor.room_number}` : '—'}
                        </span>
                      </td>

                      {/* Today's Queue Status */}
                      <td className="px-6 py-4 whitespace-nowrap">
                        {queue ? (
                          queue.is_paused ? (
                            <StatusBadge status="PAUSED" size="sm" />
                          ) : (
                            <StatusBadge status="ACTIVE" size="sm" />
                          )
                        ) : (
                          <StatusBadge status="NOT_OPEN" size="sm" />
                        )}
                      </td>

                      {/* Waiting Count */}
                      <td className="px-6 py-4 whitespace-nowrap text-center">
                        {queue ? (
                          <span className="inline-flex items-center justify-center rounded-full bg-blue-50 px-2.5 py-0.5 text-xs font-bold text-blue-700 dark:bg-blue-950/50 dark:text-blue-300">
                            {queue.waiting_count}
                          </span>
                        ) : (
                          <span className="text-xs text-zinc-400">—</span>
                        )}
                      </td>

                      {/* Actions */}
                      <td className="px-6 py-4 whitespace-nowrap text-right">
                        {queue ? (
                          <button
                            type="button"
                            onClick={() =>
                              navigate(`/reception/manage?queueId=${queue.queue_id}`)
                            }
                            className="inline-flex items-center gap-1.5 rounded-xl border border-indigo-200 bg-indigo-50/50 px-3.5 py-1.5 text-xs font-semibold text-indigo-700 hover:bg-indigo-100/70 dark:border-indigo-800 dark:bg-indigo-950/40 dark:text-indigo-300 transition-colors"
                          >
                            <PlayCircle className="h-4 w-4" />
                            {t.manageQueue}
                          </button>
                        ) : (
                          <button
                            type="button"
                            onClick={() => handleOpenQueue(doctor)}
                            disabled={isOpening}
                            className="inline-flex items-center gap-1.5 rounded-xl bg-indigo-600 px-3.5 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-indigo-700 disabled:opacity-50 transition-colors cursor-pointer"
                          >
                            {isOpening ? (
                              <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-white border-t-transparent" />
                            ) : (
                              <PlusCircle className="h-4 w-4" />
                            )}
                            {isOpening ? t.openingQueue : t.openQueue}
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};
