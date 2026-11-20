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
import { PageHeader } from '../../components/common/PageHeader';
import { AppButton } from '../../components/common/AppButton';
import { EmptyState } from '../../components/common/EmptyState';
import { LoadingSkeleton } from '../../components/common/LoadingSkeleton';

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
    <div className="space-y-6 max-w-7xl mx-auto animate-dental-in">
      <PageHeader
        title={t.adminSpecializationsTitle}
        subtitle={t.adminSpecializationsSubtitle}
        icon={<Stethoscope className="h-5 w-5" />}
        actions={
          <AppButton
            variant="primary"
            size="md"
            icon={<Plus className="h-4 w-4" />}
            onClick={handleOpenCreateModal}
          >
            {t.adminAddSpecialization}
          </AppButton>
        }
      />

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
          <Search className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-[#64748B] dark:text-[#A5B4C7]" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={t.adminSearch}
            className="w-full rounded-xl border border-[#DCE9EE] bg-white pl-10 pr-4 py-2 text-xs text-[#14283F] placeholder-[#64748B]/70 shadow-2xs focus:border-[#0D9488] focus:ring-2 focus:ring-[#0D9488]/15 focus:outline-hidden dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/60"
          />
        </div>

        <div className="inline-flex rounded-xl border border-[#DCE9EE] bg-white p-1 dark:border-[#253F5B] dark:bg-[#12243A]">
          {(['ALL', 'ACTIVE', 'INACTIVE'] as const).map((status) => (
            <button
              key={status}
              type="button"
              onClick={() => setFilterStatus(status)}
              className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition-colors cursor-pointer ${
                filterStatus === status
                  ? 'bg-[#0D9488] text-white shadow-2xs'
                  : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
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
      <div className="rounded-2xl border border-[#DCE9EE] bg-white shadow-xs dark:border-[#253F5B] dark:bg-[#12243A] overflow-hidden">
        {isLoading ? (
          <div className="p-6">
            <LoadingSkeleton rows={5} cards={0} />
          </div>
        ) : filteredSpecs.length === 0 ? (
          <EmptyState
            compact
            title={t.adminSpecEmpty}
            icon={<Stethoscope className="h-6 w-6" />}
          />
        ) : (
          <div className="overflow-x-auto lg:max-h-[calc(100vh-15.5rem)] lg:overflow-y-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead className="sticky top-0 z-10">
                <tr className="border-b border-[#DCE9EE] bg-[#F5FAFB] dark:border-[#253F5B] dark:bg-[#1A3047] text-[#64748B] dark:text-[#A5B4C7] uppercase tracking-wider font-semibold">
                  <th className="px-5 py-3.5">{t.adminSpecNameUz}</th>
                  <th className="px-5 py-3.5">{t.adminSpecNameRu}</th>
                  <th className="px-5 py-3.5">{t.adminSpecNameEn}</th>
                  <th className="px-5 py-3.5">{t.adminSpecStatus}</th>
                  <th className="px-5 py-3.5 text-right">{t.actions}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#DCE9EE]/70 dark:divide-[#253F5B]/70 font-medium">
                {filteredSpecs.map((spec) => (
                  <tr
                    key={spec.id}
                    className="hover:bg-[#F5FAFB]/80 dark:hover:bg-[#1A3047]/45 transition-colors"
                  >
                    <td className="px-5 py-3.5 text-[#14283F] dark:text-[#F1F5F9] font-semibold">
                      {spec.name_uz}
                    </td>
                    <td className="px-5 py-3.5 text-[#64748B] dark:text-[#A5B4C7]">
                      {spec.name_ru || '—'}
                    </td>
                    <td className="px-5 py-3.5 text-[#64748B] dark:text-[#A5B4C7]">
                      {spec.name_en || '—'}
                    </td>
                    <td className="px-5 py-3.5">
                      {spec.is_active ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 border border-emerald-200/80 px-2.5 py-0.5 text-2xs font-semibold text-emerald-700 dark:bg-emerald-950/50 dark:border-emerald-800/60 dark:text-emerald-300">
                          <CheckCircle2 className="h-3 w-3" />
                          {t.adminSpecActive}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-slate-100 border border-slate-200 px-2.5 py-0.5 text-2xs font-semibold text-slate-600 dark:bg-slate-800/60 dark:border-slate-700 dark:text-slate-300">
                          <XCircle className="h-3 w-3" />
                          {t.adminSpecInactive}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-3.5 text-right space-x-1.5">
                      <button
                        type="button"
                        onClick={() => handleOpenEditModal(spec)}
                        className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-2xs font-semibold text-[#0F766E] hover:bg-[#DDF7F0]/70 dark:text-[#2DD4BF] dark:hover:bg-[#0D9488]/15 transition-colors cursor-pointer"
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
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/55 backdrop-blur-xs">
          <div className="w-full max-w-lg rounded-2xl border border-[#DCE9EE] bg-white p-6 shadow-2xl dark:border-[#253F5B] dark:bg-[#12243A] animate-dental-in">
            <h3 className="text-base font-bold text-[#14283F] dark:text-[#F1F5F9]">
              {editingSpec ? t.adminEditSpecialization : t.adminAddSpecialization}
            </h3>
            <p className="mt-1 text-xs text-[#64748B] dark:text-[#A5B4C7]">
              {t.adminSpecializationsSubtitle}
            </p>

            {formError && (
              <div className="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-2.5 text-xs text-rose-700 dark:border-rose-900/60 dark:bg-rose-950/40 dark:text-rose-300">
                {formError}
              </div>
            )}

            <form onSubmit={handleSave} className="mt-4 space-y-4 text-xs">
              <div>
                <label className="block font-semibold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.adminSpecNameUz} <span className="text-rose-500">*</span>
                </label>
                <input
                  type="text"
                  required
                  value={nameUz}
                  onChange={(e) => setNameUz(e.target.value)}
                  placeholder="Masalan: Terapiya"
                  className="mt-1.5 block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:ring-2 focus:ring-[#0D9488]/15 focus:outline-hidden dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                />
              </div>

              <div>
                <label className="block font-semibold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.adminSpecNameRu}
                </label>
                <input
                  type="text"
                  value={nameRu}
                  onChange={(e) => setNameRu(e.target.value)}
                  placeholder="Например: Терапия"
                  className="mt-1.5 block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:ring-2 focus:ring-[#0D9488]/15 focus:outline-hidden dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                />
              </div>

              <div>
                <label className="block font-semibold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.adminSpecNameEn}
                </label>
                <input
                  type="text"
                  value={nameEn}
                  onChange={(e) => setNameEn(e.target.value)}
                  placeholder="e.g. Therapy / General Dentistry"
                  className="mt-1.5 block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:ring-2 focus:ring-[#0D9488]/15 focus:outline-hidden dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                />
              </div>

              <div className="flex justify-end gap-2.5 pt-3 border-t border-[#DCE9EE] dark:border-[#253F5B]">
                <AppButton
                  type="button"
                  variant="ghost"
                  onClick={() => setIsModalOpen(false)}
                  disabled={isSaving}
                >
                  {t.cancel}
                </AppButton>
                <AppButton
                  type="submit"
                  variant="primary"
                  loading={isSaving}
                  disabled={isSaving || !nameUz.trim()}
                >
                  {isSaving ? t.adminSaving : t.adminSave}
                </AppButton>
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
