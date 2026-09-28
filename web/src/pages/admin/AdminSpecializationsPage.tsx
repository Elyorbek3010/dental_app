import React, { useCallback, useEffect, useState } from 'react';
import { CheckCircle2, Edit2, Plus, Power, Search, Stethoscope, XCircle } from 'lucide-react';
import {
  createAdminSpecializationApi,
  listAdminSpecializationsApi,
  updateAdminSpecializationApi,
} from '../../api/admin';
import type { AdminSpecialization } from '../../types/admin';
import { useI18n } from '../../i18n/useI18n';
import { ConfirmModal } from '../../components/common/ConfirmModal';
import { AlertBanner } from '../../components/common/AlertBanner';

export const AdminSpecializationsPage: React.FC = () => {
  const { t } = useI18n();

  const [specializations, setSpecializations] = useState<AdminSpecialization[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState<'ALL' | 'ACTIVE' | 'INACTIVE'>('ALL');
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  // Modal states
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingSpec, setEditingSpec] = useState<AdminSpecialization | null>(null);
  const [nameUz, setNameUz] = useState('');
  const [nameRu, setNameRu] = useState('');
  const [nameEn, setNameEn] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  // Status toggle confirmation
  const [toggleTarget, setToggleTarget] = useState<AdminSpecialization | null>(null);
  const [isToggling, setIsToggling] = useState(false);

  const fetchSpecializations = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const data = await listAdminSpecializationsApi();
      setSpecializations(data);
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
    listAdminSpecializationsApi()
      .then((data) => {
        if (!isCancelled) {
          setSpecializations(data);
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

  const handleOpenCreateModal = () => {
    setEditingSpec(null);
    setNameUz('');
    setNameRu('');
    setNameEn('');
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleOpenEditModal = (spec: AdminSpecialization) => {
    setEditingSpec(spec);
    setNameUz(spec.name_uz || '');
    setNameRu(spec.name_ru || '');
    setNameEn(spec.name_en || '');
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedUz = nameUz.trim();
    if (!trimmedUz) {
      setFormError(t.adminSpecNameUzReq);
      return;
    }

    setIsSaving(true);
    setFormError(null);
    try {
      if (editingSpec) {
        await updateAdminSpecializationApi(editingSpec.id, {
          name_uz: trimmedUz,
          name_ru: nameRu.trim() || null,
          name_en: nameEn.trim() || null,
        });
      } else {
        await createAdminSpecializationApi({
          name_uz: trimmedUz,
          name_ru: nameRu.trim() || null,
          name_en: nameEn.trim() || null,
        });
      }

      setIsModalOpen(false);
      setSuccessMessage(t.adminSpecSaveSuccess);
      await fetchSpecializations();
    } catch (err: unknown) {
      if (err instanceof Error) {
        setFormError(err.message);
      } else {
        setFormError(t.errorGeneric);
      }
    } finally {
      setIsSaving(false);
    }
  };

  const handleConfirmToggle = async () => {
    if (!toggleTarget) return;
    setIsToggling(true);
    try {
      await updateAdminSpecializationApi(toggleTarget.id, {
        is_active: !toggleTarget.is_active,
      });
      setToggleTarget(null);
      await fetchSpecializations();
    } catch (err: unknown) {
      if (err instanceof Error) {
        setError(err.message);
      } else {
        setError(t.errorGeneric);
      }
    } finally {
      setIsToggling(false);
    }
  };

  const filteredSpecs = specializations.filter((spec) => {
    const matchesSearch =
      spec.name_uz.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (spec.name_ru && spec.name_ru.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (spec.name_en && spec.name_en.toLowerCase().includes(searchQuery.toLowerCase()));

    const matchesStatus =
      filterStatus === 'ALL' ||
      (filterStatus === 'ACTIVE' && spec.is_active) ||
      (filterStatus === 'INACTIVE' && !spec.is_active);

    return matchesSearch && matchesStatus;
  });

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100 flex items-center gap-2.5">
            <Stethoscope className="h-6 w-6 text-purple-600 dark:text-purple-400" />
            {t.adminSpecializationsTitle}
          </h2>
          <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
            {t.adminSpecializationsSubtitle}
          </p>
        </div>

        <button
          type="button"
          onClick={handleOpenCreateModal}
          className="inline-flex items-center gap-2 rounded-xl bg-purple-600 px-4 py-2.5 text-xs font-semibold text-white shadow-xs hover:bg-purple-700 transition-colors cursor-pointer shrink-0"
        >
          <Plus className="h-4 w-4" />
          {t.adminAddSpecialization}
        </button>
      </div>

      {error && (
        <AlertBanner type="error" message={error} onClose={() => setError(null)} />
      )}
      {successMessage && (
        <AlertBanner
          type="success"
          message={successMessage}
          onClose={() => setSuccessMessage(null)}
        />
      )}

      {/* Filter and Search Bar */}
      <div className="flex flex-col sm:flex-row gap-3">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={t.adminSearch}
            className="w-full rounded-xl border border-zinc-200 bg-white pl-10 pr-4 py-2 text-xs text-zinc-900 placeholder-zinc-400 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-100"
          />
        </div>

        <div className="flex rounded-xl border border-zinc-200 bg-white p-1 dark:border-zinc-800 dark:bg-zinc-900">
          {(['ALL', 'ACTIVE', 'INACTIVE'] as const).map((status) => (
            <button
              key={status}
              type="button"
              onClick={() => setFilterStatus(status)}
              className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition-colors cursor-pointer ${
                filterStatus === status
                  ? 'bg-purple-600 text-white shadow-2xs'
                  : 'text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100'
              }`}
            >
              {status === 'ALL'
                ? t.adminFilterAll
                : status === 'ACTIVE'
                ? t.adminSpecActive
                : t.adminSpecInactive}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="rounded-2xl border border-zinc-200 bg-white shadow-2xs dark:border-zinc-800 dark:bg-zinc-900 overflow-hidden">
        {isLoading ? (
          <div className="p-12 text-center text-xs text-zinc-500 dark:text-zinc-400">
            <div className="mx-auto h-7 w-7 animate-spin rounded-full border-2 border-purple-600 border-t-transparent mb-3" />
            {t.loading}
          </div>
        ) : filteredSpecs.length === 0 ? (
          <div className="p-12 text-center text-xs text-zinc-500 dark:text-zinc-400">
            {t.adminSpecEmpty}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="border-b border-zinc-200 bg-zinc-50/75 dark:border-zinc-800 dark:bg-zinc-800/40 text-zinc-500 dark:text-zinc-400 uppercase tracking-wider font-semibold">
                  <th className="px-5 py-3.5">{t.adminSpecNameUz}</th>
                  <th className="px-5 py-3.5">{t.adminSpecNameRu}</th>
                  <th className="px-5 py-3.5">{t.adminSpecNameEn}</th>
                  <th className="px-5 py-3.5">{t.adminSpecStatus}</th>
                  <th className="px-5 py-3.5 text-right">{t.actions}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800/60 font-medium">
                {filteredSpecs.map((spec) => (
                  <tr
                    key={spec.id}
                    className="hover:bg-zinc-50/60 dark:hover:bg-zinc-800/30 transition-colors"
                  >
                    <td className="px-5 py-3.5 text-zinc-900 dark:text-zinc-100 font-semibold">
                      {spec.name_uz}
                    </td>
                    <td className="px-5 py-3.5 text-zinc-600 dark:text-zinc-300">
                      {spec.name_ru || '—'}
                    </td>
                    <td className="px-5 py-3.5 text-zinc-600 dark:text-zinc-300">
                      {spec.name_en || '—'}
                    </td>
                    <td className="px-5 py-3.5">
                      {spec.is_active ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-2xs font-semibold text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300">
                          <CheckCircle2 className="h-3 w-3" />
                          {t.adminSpecActive}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-zinc-100 px-2 py-0.5 text-2xs font-semibold text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400">
                          <XCircle className="h-3 w-3" />
                          {t.adminSpecInactive}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-3.5 text-right space-x-2">
                      <button
                        type="button"
                        onClick={() => handleOpenEditModal(spec)}
                        className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-2xs font-semibold text-purple-700 hover:bg-purple-50 dark:text-purple-400 dark:hover:bg-purple-950/40 transition-colors cursor-pointer"
                        title={t.adminEditSpecialization}
                      >
                        <Edit2 className="h-3.5 w-3.5" />
                        {t.adminEditSpecialization}
                      </button>

                      <button
                        type="button"
                        onClick={() => setToggleTarget(spec)}
                        className={`inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-2xs font-semibold transition-colors cursor-pointer ${
                          spec.is_active
                            ? 'text-amber-700 hover:bg-amber-50 dark:text-amber-400 dark:hover:bg-amber-950/40'
                            : 'text-emerald-700 hover:bg-emerald-50 dark:text-emerald-400 dark:hover:bg-emerald-950/40'
                        }`}
                        title={
                          spec.is_active ? t.adminSpecDeactivate : t.adminSpecActivate
                        }
                      >
                        <Power className="h-3.5 w-3.5" />
                        {spec.is_active ? t.adminSpecDeactivate : t.adminSpecActivate}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Create / Edit Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs">
          <div className="w-full max-w-lg rounded-2xl border border-zinc-200 bg-white p-6 shadow-xl dark:border-zinc-800 dark:bg-zinc-900">
            <h3 className="text-base font-bold text-zinc-900 dark:text-zinc-100">
              {editingSpec ? t.adminEditSpecialization : t.adminAddSpecialization}
            </h3>
            <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
              {t.adminSpecializationsSubtitle}
            </p>

            {formError && (
              <div className="mt-4 rounded-xl bg-red-50 p-2.5 text-xs text-red-600 dark:bg-red-950/40 dark:text-red-400">
                {formError}
              </div>
            )}

            <form onSubmit={handleSave} className="mt-4 space-y-4 text-xs">
              <div>
                <label className="block font-semibold text-zinc-700 dark:text-zinc-300">
                  {t.adminSpecNameUz} <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  required
                  value={nameUz}
                  onChange={(e) => setNameUz(e.target.value)}
                  placeholder="Masalan: Terapiya"
                  className="mt-1 block w-full rounded-xl border border-zinc-300 bg-white px-3 py-2 text-zinc-900 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                />
              </div>

              <div>
                <label className="block font-semibold text-zinc-700 dark:text-zinc-300">
                  {t.adminSpecNameRu}
                </label>
                <input
                  type="text"
                  value={nameRu}
                  onChange={(e) => setNameRu(e.target.value)}
                  placeholder="Например: Терапия"
                  className="mt-1 block w-full rounded-xl border border-zinc-300 bg-white px-3 py-2 text-zinc-900 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                />
              </div>

              <div>
                <label className="block font-semibold text-zinc-700 dark:text-zinc-300">
                  {t.adminSpecNameEn}
                </label>
                <input
                  type="text"
                  value={nameEn}
                  onChange={(e) => setNameEn(e.target.value)}
                  placeholder="e.g. Therapy / General Dentistry"
                  className="mt-1 block w-full rounded-xl border border-zinc-300 bg-white px-3 py-2 text-zinc-900 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                />
              </div>

              <div className="flex justify-end gap-3 pt-3">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  disabled={isSaving}
                  className="rounded-xl px-4 py-2 font-semibold text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800"
                >
                  {t.cancel}
                </button>
                <button
                  type="submit"
                  disabled={isSaving || !nameUz.trim()}
                  className="rounded-xl bg-purple-600 px-4 py-2 font-semibold text-white shadow-xs hover:bg-purple-700 disabled:opacity-50"
                >
                  {isSaving ? t.adminSaving : t.adminSave}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Toggle Confirm Modal */}
      <ConfirmModal
        isOpen={!!toggleTarget}
        title={
          toggleTarget?.is_active
            ? t.adminSpecDeactivateConfirmTitle
            : t.adminSpecActivateConfirmTitle
        }
        message={
          toggleTarget?.is_active
            ? t.adminSpecDeactivateConfirmMsg
            : t.adminSpecActivateConfirmMsg
        }
        confirmLabel={
          toggleTarget?.is_active ? t.adminSpecDeactivate : t.adminSpecActivate
        }
        cancelLabel={t.cancel}
        isDestructive={toggleTarget?.is_active}
        isLoading={isToggling}
        onConfirm={handleConfirmToggle}
        onCancel={() => setToggleTarget(null)}
      />
    </div>
  );
};
