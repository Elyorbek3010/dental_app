import React, { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { UserPlus, X } from 'lucide-react';
import { useI18n } from '../../i18n/useI18n';

interface WalkInModalProps {
  isOpen: boolean;
  isLoading: boolean;
  error?: string | null;
  onClose: () => void;
  onSubmit: (patientName: string, patientPhone?: string) => Promise<void>;
}

const INPUT_CLASS =
  'mt-1.5 block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-sm text-[#14283F] placeholder-[#64748B]/80 shadow-2xs transition-colors focus:border-[#0D9488] focus:bg-white focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 disabled:cursor-not-allowed disabled:opacity-60 dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/75 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728] dark:focus:text-[#F1F5F9] dark:focus:ring-[#2DD4BF]/25';

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

  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !isLoading) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isLoading, isOpen, onClose]);

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

  return createPortal(
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="walkin-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[#0B1728]/65 backdrop-blur-xs"
    >
      <div className="relative w-full max-w-md max-h-[90vh] overflow-y-auto rounded-2xl border border-[#DCE9EE] bg-white p-6 shadow-2xl dark:border-[#253F5B] dark:bg-[#1A3047]">
        <button
          type="button"
          aria-label={t.cancel}
          onClick={onClose}
          disabled={isLoading}
          className="absolute top-4 right-4 rounded-lg p-1.5 text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] disabled:opacity-50 dark:text-[#A5B4C7] dark:hover:bg-[#12243A] dark:hover:text-[#F1F5F9] cursor-pointer"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="flex items-center gap-3 border-b border-[#DCE9EE] pb-4 pr-8 dark:border-[#253F5B]">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
            <UserPlus className="h-5 w-5" />
          </div>
          <div className="min-w-0">
            <h3
              id="walkin-modal-title"
              className="text-base font-bold text-[#14283F] dark:text-[#F1F5F9]"
            >
              {t.walkInModalTitle}
            </h3>
            <p className="text-xs text-[#64748B] dark:text-[#A5B4C7]">
              {t.walkInModalSubtitle}
            </p>
          </div>
        </div>

        {(error || validationError) && (
          <div className="mt-4 rounded-xl bg-rose-50 p-3 text-sm font-medium text-rose-700 ring-1 ring-rose-200 dark:bg-rose-950/50 dark:text-rose-200 dark:ring-rose-800/70">
            {validationError || error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          <div>
            <label
              htmlFor="walkin-patient-name"
              className="block text-xs font-semibold text-[#14283F] dark:text-[#F1F5F9] uppercase tracking-wider"
            >
              {t.fullNameLabel} <span className="text-rose-500">*</span>
            </label>
            <input
              id="walkin-patient-name"
              type="text"
              autoFocus
              value={patientName}
              onChange={(e) => {
                setPatientName(e.target.value);
                if (validationError) setValidationError(null);
              }}
              placeholder={t.fullNamePlaceholder}
              disabled={isLoading}
              className={INPUT_CLASS}
            />
          </div>

          <div>
            <label
              htmlFor="walkin-patient-phone"
              className="block text-xs font-semibold text-[#14283F] dark:text-[#F1F5F9] uppercase tracking-wider"
            >
              {t.phoneOptionalLabel}
            </label>
            <input
              id="walkin-patient-phone"
              type="tel"
              value={patientPhone}
              onChange={(e) => setPatientPhone(e.target.value)}
              placeholder="+998901234567"
              disabled={isLoading}
              className={INPUT_CLASS}
            />
          </div>

          <div className="mt-6 flex flex-wrap items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              disabled={isLoading}
              className="rounded-xl border border-[#DCE9EE] bg-white px-4 py-2.5 text-sm font-semibold text-[#14283F] hover:bg-[#EDF6F8] disabled:cursor-not-allowed disabled:opacity-50 dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:hover:bg-[#0B1728] cursor-pointer"
            >
              {t.cancel}
            </button>
            <button
              type="submit"
              disabled={isLoading || !patientName.trim()}
              className="rounded-xl bg-[#0D9488] px-5 py-2.5 text-sm font-semibold text-white shadow-xs hover:bg-[#0F766E] focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/30 disabled:cursor-not-allowed disabled:opacity-50 flex items-center gap-2 dark:bg-[#14B8A6] dark:text-[#07131D] dark:hover:bg-[#2DD4BF] dark:focus:ring-[#2DD4BF]/35 cursor-pointer"
            >
              {isLoading && (
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
              )}
              {isLoading ? t.addingWalkIn : t.addWalkInSubmit}
            </button>
          </div>
        </form>
      </div>
    </div>,
    document.body
  );
};
