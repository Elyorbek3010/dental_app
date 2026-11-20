import React, { useCallback, useEffect, useState } from 'react';
import {
  CheckCircle2,
  Edit2,
  KeyRound,
  Plus,
  Power,
  Search,
  UserCog,
  XCircle,
} from 'lucide-react';
import {
  createAdminReceptionistApi,
  listAdminReceptionistsApi,
  updateAdminReceptionistApi,
} from '../../api/admin';
import type { AdminReceptionist } from '../../types/admin';
import { useI18n } from '../../i18n/useI18n';
import { ConfirmModal } from '../../components/common/ConfirmModal';
import { AlertBanner } from '../../components/common/AlertBanner';
import { PageHeader } from '../../components/common/PageHeader';
import { AppButton } from '../../components/common/AppButton';
import { EmptyState } from '../../components/common/EmptyState';
import { LoadingSkeleton } from '../../components/common/LoadingSkeleton';

export const AdminReceptionistsPage: React.FC = () => {
  const { t } = useI18n();

  const [receptionists, setReceptionists] = useState<AdminReceptionist[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState<'ALL' | 'ACTIVE' | 'INACTIVE'>('ALL');
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  // Modal states
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingRec, setEditingRec] = useState<AdminReceptionist | null>(null);
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  // Toggle confirmation
  const [toggleTarget, setToggleTarget] = useState<AdminReceptionist | null>(null);
  const [isToggling, setIsToggling] = useState(false);

  const fetchReceptionists = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const data = await listAdminReceptionistsApi();
      setReceptionists(data);
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
    listAdminReceptionistsApi()
      .then((data) => {
        if (!isCancelled) {
          setReceptionists(data);
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
    setEditingRec(null);
    setFullName('');
    setPhone('+998');
    setPassword('');
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleOpenEditModal = (rec: AdminReceptionist) => {
    setEditingRec(rec);
    setFullName(rec.full_name);
    setPhone(rec.phone);
    setPassword('');
    setFormError(null);
    setIsModalOpen(true);
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedName = fullName.trim();
    const trimmedPhone = phone.trim();

    if (!trimmedName) {
      setFormError(t.adminReceptionistNameReq);
      return;
    }
    if (!trimmedPhone) {
      setFormError(t.adminReceptionistPhoneReq);
      return;
    }

    if (!editingRec && (!password || password.length < 6)) {
      setFormError(t.adminReceptionistPasswordReq);
      return;
    }

    if (editingRec && password && password.length < 6) {
      setFormError(t.adminReceptionistPasswordReq);
      return;
    }

    setIsSaving(true);
    setFormError(null);
    try {
      if (editingRec) {
        await updateAdminReceptionistApi(editingRec.id, {
          full_name: trimmedName,
          phone: trimmedPhone,
          password: password ? password.trim() : undefined,
        });
      } else {
        await createAdminReceptionistApi({
          full_name: trimmedName,
          phone: trimmedPhone,
          password: password.trim(),
        });
      }

      setIsModalOpen(false);
      setSuccessMessage(t.adminReceptionistSaveSuccess);
      await fetchReceptionists();
    } catch (err: unknown) {
      if (err instanceof Error) {
        if (err.message.includes('409') || err.message.toLowerCase().includes('already registered')) {
          setFormError(t.adminReceptionistPhoneExists);
        } else {
          setFormError(err.message);
        }
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
      await updateAdminReceptionistApi(toggleTarget.id, {
        is_active: !toggleTarget.is_active,
      });
      setToggleTarget(null);
      await fetchReceptionists();
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

  const filteredRecs = receptionists.filter((rec) => {
    const matchesSearch =
      rec.full_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      rec.phone.includes(searchQuery);

    const matchesStatus =
      filterStatus === 'ALL' ||
      (filterStatus === 'ACTIVE' && rec.is_active) ||
      (filterStatus === 'INACTIVE' && !rec.is_active);

    return matchesSearch && matchesStatus;
  });

  return (
    <div className="space-y-6 max-w-7xl mx-auto animate-dental-in">
      <PageHeader
        title={t.adminReceptionistsTitle}
        subtitle={t.adminReceptionistsSubtitle}
        icon={<UserCog className="h-5 w-5" />}
        actions={
          <AppButton
            variant="primary"
            size="md"
            icon={<Plus className="h-4 w-4" />}
            onClick={handleOpenCreateModal}
          >
            {t.adminAddReceptionist}
          </AppButton>
        }
      />

      {error && <AlertBanner type="error" message={error} onClose={() => setError(null)} />}
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

        {/* Active/Inactive Status Toggle */}
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
                ? t.adminReceptionistActive
                : t.adminReceptionistInactive}
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
        ) : filteredRecs.length === 0 ? (
          <EmptyState
            compact
            title={t.adminReceptionistEmpty}
            icon={<UserCog className="h-6 w-6" />}
          />
        ) : (
          <div className="overflow-x-auto lg:max-h-[calc(100vh-15.5rem)] lg:overflow-y-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead className="sticky top-0 z-10">
                <tr className="border-b border-[#DCE9EE] bg-[#F5FAFB] dark:border-[#253F5B] dark:bg-[#1A3047] text-[#64748B] dark:text-[#A5B4C7] uppercase tracking-wider font-semibold">
                  <th className="px-5 py-3.5">{t.adminReceptionistName}</th>
                  <th className="px-5 py-3.5">{t.adminReceptionistPhone}</th>
                  <th className="px-5 py-3.5">{t.adminReceptionistStatus}</th>
                  <th className="px-5 py-3.5 text-right">{t.actions}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#DCE9EE]/70 dark:divide-[#253F5B]/70 font-medium">
                {filteredRecs.map((rec) => (
                  <tr
                    key={rec.id}
                    className="hover:bg-[#F5FAFB]/80 dark:hover:bg-[#1A3047]/45 transition-colors"
                  >
                    <td className="px-5 py-3.5 text-[#14283F] dark:text-[#F1F5F9] font-semibold">
                      {rec.full_name}
                    </td>
                    <td className="px-5 py-3.5 text-[#64748B] dark:text-[#A5B4C7] font-mono tabular-nums">
                      {rec.phone}
                    </td>
                    <td className="px-5 py-3.5">
                      {rec.is_active ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 border border-emerald-200/80 px-2.5 py-0.5 text-2xs font-semibold text-emerald-700 dark:bg-emerald-950/50 dark:border-emerald-800/60 dark:text-emerald-300">
                          <CheckCircle2 className="h-3 w-3" />
                          {t.adminReceptionistActive}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-rose-50 border border-rose-200/80 px-2.5 py-0.5 text-2xs font-semibold text-rose-700 dark:bg-rose-950/50 dark:border-rose-800/60 dark:text-rose-300">
                          <XCircle className="h-3 w-3" />
                          {t.adminReceptionistInactive}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-3.5 text-right space-x-1.5">
                      <button
                        type="button"
                        onClick={() => handleOpenEditModal(rec)}
                        className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-2xs font-semibold text-[#0F766E] hover:bg-[#DDF7F0]/70 dark:text-[#2DD4BF] dark:hover:bg-[#0D9488]/15 transition-colors cursor-pointer"
                        title={t.adminEditReceptionist}
                      >
                        <Edit2 className="h-3.5 w-3.5" />
                        {t.adminEditReceptionist}
                      </button>

                      <button
                        type="button"
                        onClick={() => setToggleTarget(rec)}
                        className={`inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-2xs font-semibold transition-colors cursor-pointer ${
                          rec.is_active
                            ? 'text-rose-700 hover:bg-rose-50 dark:text-rose-400 dark:hover:bg-rose-950/40'
                            : 'text-emerald-700 hover:bg-emerald-50 dark:text-emerald-400 dark:hover:bg-emerald-950/40'
                        }`}
                        title={
                          rec.is_active
                            ? t.adminReceptionistDeactivate
                            : t.adminReceptionistActivate
                        }
                      >
                        <Power className="h-3.5 w-3.5" />
                        {rec.is_active
                          ? t.adminReceptionistDeactivate
                          : t.adminReceptionistActivate}
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
              {editingRec ? t.adminEditReceptionist : t.adminAddReceptionist}
            </h3>
            <p className="mt-1 text-xs text-[#64748B] dark:text-[#A5B4C7]">
              {t.adminReceptionistsSubtitle}
            </p>

            {formError && (
              <div className="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-2.5 text-xs text-rose-700 dark:border-rose-900/60 dark:bg-rose-950/40 dark:text-rose-300">
                {formError}
              </div>
            )}

            <form onSubmit={handleSave} className="mt-4 space-y-4 text-xs">
              <div>
                <label className="block font-semibold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.adminReceptionistName} <span className="text-rose-500">*</span>
                </label>
                <input
                  type="text"
                  required
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder="Masalan: Dilnoza Karimova"
                  className="mt-1.5 block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:ring-2 focus:ring-[#0D9488]/15 focus:outline-hidden dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                />
              </div>

              <div>
                <label className="block font-semibold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.adminReceptionistPhone} <span className="text-rose-500">*</span>
                </label>
                <input
                  type="tel"
                  required
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+998901234567"
                  className="mt-1.5 block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-[#14283F] font-mono tabular-nums placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:ring-2 focus:ring-[#0D9488]/15 focus:outline-hidden dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                />
              </div>

              <div>
                <label className="flex font-semibold text-[#14283F] dark:text-[#F1F5F9] items-center justify-between">
                  <span>
                    {editingRec ? t.adminReceptionistResetPassword : t.adminReceptionistPassword}{' '}
                    {!editingRec && <span className="text-rose-500">*</span>}
                  </span>
                  {editingRec && (
                    <span className="text-2xs font-normal text-[#64748B] dark:text-[#A5B4C7]">
                      {t.adminReceptionistPasswordHint}
                    </span>
                  )}
                </label>
                <div className="relative mt-1.5">
                  <KeyRound className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
                  <input
                    type="password"
                    required={!editingRec}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    className="block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] pl-9 pr-3.5 py-2.5 text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:ring-2 focus:ring-[#0D9488]/15 focus:outline-hidden dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                  />
                </div>
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
                  disabled={isSaving || !fullName.trim() || !phone.trim()}
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
            ? t.adminReceptionistDeactivateConfirmTitle
            : t.adminReceptionistActivateConfirmTitle
        }
        message={
          toggleTarget?.is_active
            ? t.adminReceptionistDeactivateConfirmMsg
            : t.adminReceptionistActivateConfirmMsg
        }
        confirmLabel={
          toggleTarget?.is_active
            ? t.adminReceptionistDeactivate
            : t.adminReceptionistActivate
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
