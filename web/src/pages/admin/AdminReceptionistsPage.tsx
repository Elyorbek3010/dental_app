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
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100 flex items-center gap-2.5">
            <UserCog className="h-6 w-6 text-purple-600 dark:text-purple-400" />
            {t.adminReceptionistsTitle}
          </h2>
          <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
            {t.adminReceptionistsSubtitle}
          </p>
        </div>

        <button
          type="button"
          onClick={handleOpenCreateModal}
          className="inline-flex items-center gap-2 rounded-xl bg-purple-600 px-4 py-2.5 text-xs font-semibold text-white shadow-xs hover:bg-purple-700 transition-colors cursor-pointer shrink-0"
        >
          <Plus className="h-4 w-4" />
          {t.adminAddReceptionist}
        </button>
      </div>

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
          <Search className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={t.adminSearch}
            className="w-full rounded-xl border border-zinc-200 bg-white pl-10 pr-4 py-2 text-xs text-zinc-900 placeholder-zinc-400 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-100"
          />
        </div>

        {/* Active/Inactive Status Toggle */}
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
                ? t.adminReceptionistActive
                : t.adminReceptionistInactive}
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
        ) : filteredRecs.length === 0 ? (
          <div className="p-12 text-center text-xs text-zinc-500 dark:text-zinc-400">
            {t.adminReceptionistEmpty}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="border-b border-zinc-200 bg-zinc-50/75 dark:border-zinc-800 dark:bg-zinc-800/40 text-zinc-500 dark:text-zinc-400 uppercase tracking-wider font-semibold">
                  <th className="px-5 py-3.5">{t.adminReceptionistName}</th>
                  <th className="px-5 py-3.5">{t.adminReceptionistPhone}</th>
                  <th className="px-5 py-3.5">{t.adminReceptionistStatus}</th>
                  <th className="px-5 py-3.5 text-right">{t.actions}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800/60 font-medium">
                {filteredRecs.map((rec) => (
                  <tr
                    key={rec.id}
                    className="hover:bg-zinc-50/60 dark:hover:bg-zinc-800/30 transition-colors"
                  >
                    <td className="px-5 py-3.5 text-zinc-900 dark:text-zinc-100 font-semibold">
                      {rec.full_name}
                    </td>
                    <td className="px-5 py-3.5 text-zinc-600 dark:text-zinc-300 font-mono">
                      {rec.phone}
                    </td>
                    <td className="px-5 py-3.5">
                      {rec.is_active ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-2xs font-semibold text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300">
                          <CheckCircle2 className="h-3 w-3" />
                          {t.adminReceptionistActive}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-red-50 px-2 py-0.5 text-2xs font-semibold text-red-700 dark:bg-red-950/60 dark:text-red-300">
                          <XCircle className="h-3 w-3" />
                          {t.adminReceptionistInactive}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-3.5 text-right space-x-2">
                      <button
                        type="button"
                        onClick={() => handleOpenEditModal(rec)}
                        className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-2xs font-semibold text-purple-700 hover:bg-purple-50 dark:text-purple-400 dark:hover:bg-purple-950/40 transition-colors cursor-pointer"
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
                            ? 'text-red-700 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950/40'
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
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs">
          <div className="w-full max-w-lg rounded-2xl border border-zinc-200 bg-white p-6 shadow-xl dark:border-zinc-800 dark:bg-zinc-900">
            <h3 className="text-base font-bold text-zinc-900 dark:text-zinc-100">
              {editingRec ? t.adminEditReceptionist : t.adminAddReceptionist}
            </h3>
            <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
              {t.adminReceptionistsSubtitle}
            </p>

            {formError && (
              <div className="mt-4 rounded-xl bg-red-50 p-2.5 text-xs text-red-600 dark:bg-red-950/40 dark:text-red-400">
                {formError}
              </div>
            )}

            <form onSubmit={handleSave} className="mt-4 space-y-4 text-xs">
              <div>
                <label className="block font-semibold text-zinc-700 dark:text-zinc-300">
                  {t.adminReceptionistName} <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  required
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder="Masalan: Dilnoza Karimova"
                  className="mt-1 block w-full rounded-xl border border-zinc-300 bg-white px-3 py-2 text-zinc-900 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                />
              </div>

              <div>
                <label className="block font-semibold text-zinc-700 dark:text-zinc-300">
                  {t.adminReceptionistPhone} <span className="text-red-500">*</span>
                </label>
                <input
                  type="tel"
                  required
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+998901234567"
                  className="mt-1 block w-full rounded-xl border border-zinc-300 bg-white px-3 py-2 text-zinc-900 font-mono shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                />
              </div>

              <div>
                <label className="block font-semibold text-zinc-700 dark:text-zinc-300 flex items-center justify-between">
                  <span>
                    {editingRec ? t.adminReceptionistResetPassword : t.adminReceptionistPassword}{' '}
                    {!editingRec && <span className="text-red-500">*</span>}
                  </span>
                  {editingRec && (
                    <span className="text-2xs font-normal text-zinc-400">
                      {t.adminReceptionistPasswordHint}
                    </span>
                  )}
                </label>
                <div className="relative mt-1">
                  <KeyRound className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-zinc-400" />
                  <input
                    type="password"
                    required={!editingRec}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder={editingRec ? '••••••••' : '•••••••• (kamida 6 belgi)'}
                    className="block w-full rounded-xl border border-zinc-300 bg-white pl-9 pr-3 py-2 text-zinc-900 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                  />
                </div>
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
                  disabled={isSaving || !fullName.trim() || !phone.trim()}
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
