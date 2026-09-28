import React, { useState } from 'react';
import { UserPlus, X } from 'lucide-react';
import { useI18n } from '../../i18n/useI18n';

interface WalkInModalProps {
  isOpen: boolean;
  isLoading: boolean;
  error?: string | null;
  onClose: () => void;
  onSubmit: (patientName: string, patientPhone?: string) => Promise<void>;
}

export const WalkInModal: React.FC<WalkInModalProps> = ({
  isOpen,
  isLoading,
  error,
  onClose,
  onSubmit,
}) => {
  const { t } = useI18n();
  const [patientName, setPatientName] = useState('');
  const [patientPhone, setPatientPhone] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedName = patientName.trim();
    if (!trimmedName || trimmedName.length < 2) {
      setValidationError(t.fullNameRequired);
      return;
    }

    setValidationError(null);
    try {
      await onSubmit(trimmedName, patientPhone.trim() || undefined);
      setPatientName('');
      setPatientPhone('');
      onClose();
    } catch {
      // error is handled by caller and passed via error prop
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-zinc-900/60 backdrop-blur-xs animate-fadeIn">
      <div className="relative w-full max-w-md rounded-2xl bg-white p-6 shadow-2xl ring-1 ring-zinc-900/5 dark:bg-zinc-900 dark:ring-white/10">
        <button
          onClick={onClose}
          disabled={isLoading}
          className="absolute top-4 right-4 rounded-lg p-1 text-zinc-400 hover:bg-zinc-100 hover:text-zinc-600 dark:hover:bg-zinc-800 dark:hover:text-zinc-300"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="flex items-center gap-3 border-b border-zinc-100 pb-4 dark:border-zinc-800">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-indigo-50 text-indigo-600 dark:bg-indigo-950/50 dark:text-indigo-400">
            <UserPlus className="h-5 w-5" />
          </div>
          <div>
            <h3 className="text-base font-semibold text-zinc-900 dark:text-zinc-100">
              {t.walkInModalTitle}
            </h3>
            <p className="text-xs text-zinc-500 dark:text-zinc-400">
              {t.walkInModalSubtitle}
            </p>
          </div>
        </div>

        {(error || validationError) && (
          <div className="mt-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700 ring-1 ring-rose-200 dark:bg-rose-950/30 dark:text-rose-300 dark:ring-rose-800">
            {validationError || error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          <div>
            <label className="block text-xs font-semibold text-zinc-700 dark:text-zinc-300 uppercase tracking-wider">
              {t.fullNameLabel} <span className="text-rose-500">*</span>
            </label>
            <input
              type="text"
              autoFocus
              value={patientName}
              onChange={(e) => {
                setPatientName(e.target.value);
                if (validationError) setValidationError(null);
              }}
              placeholder={t.fullNamePlaceholder}
              disabled={isLoading}
              className="mt-1.5 block w-full rounded-xl border border-zinc-300 bg-white px-3.5 py-2.5 text-sm text-zinc-900 placeholder-zinc-400 shadow-xs focus:border-indigo-500 focus:outline-hidden focus:ring-2 focus:ring-indigo-500/20 disabled:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100 dark:placeholder-zinc-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-zinc-700 dark:text-zinc-300 uppercase tracking-wider">
              {t.phoneOptionalLabel}
            </label>
            <input
              type="tel"
              value={patientPhone}
              onChange={(e) => setPatientPhone(e.target.value)}
              placeholder="+998901234567"
              disabled={isLoading}
              className="mt-1.5 block w-full rounded-xl border border-zinc-300 bg-white px-3.5 py-2.5 text-sm text-zinc-900 placeholder-zinc-400 shadow-xs focus:border-indigo-500 focus:outline-hidden focus:ring-2 focus:ring-indigo-500/20 disabled:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100 dark:placeholder-zinc-500"
            />
          </div>

          <div className="mt-6 flex items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              disabled={isLoading}
              className="rounded-xl border border-zinc-300 px-4 py-2.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50 disabled:opacity-50 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
            >
              {t.cancel}
            </button>
            <button
              type="submit"
              disabled={isLoading || !patientName.trim()}
              className="rounded-xl bg-indigo-600 px-5 py-2.5 text-sm font-medium text-white shadow-xs hover:bg-indigo-700 focus:ring-2 focus:ring-indigo-500/20 disabled:opacity-50 flex items-center gap-2"
            >
              {isLoading && (
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
              )}
              {isLoading ? t.addingWalkIn : t.addWalkInSubmit}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
