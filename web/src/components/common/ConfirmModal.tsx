import React from 'react';
import { createPortal } from 'react-dom';
import { AlertTriangle, X } from 'lucide-react';
import { useI18n } from '../../i18n/useI18n';

interface ConfirmModalProps {
  isOpen: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  isDestructive?: boolean;
  isLoading?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export const ConfirmModal: React.FC<ConfirmModalProps> = ({
  isOpen,
  title,
  message,
  confirmLabel,
  cancelLabel,
  isDestructive = false,
  isLoading = false,
  onConfirm,
  onCancel,
}) => {
  const { t } = useI18n();

  if (!isOpen) return null;

  return createPortal(
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[#0B1728]/65 backdrop-blur-xs">
      <div className="relative w-full max-w-md max-h-[90vh] overflow-y-auto rounded-2xl border border-[#DCE9EE] bg-white p-6 shadow-2xl dark:border-[#253F5B] dark:bg-[#1A3047]">
        <button
          type="button"
          onClick={onCancel}
          disabled={isLoading}
          className="absolute top-4 right-4 rounded-lg p-1 text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:bg-[#12243A] dark:hover:text-[#F1F5F9] cursor-pointer"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="flex items-start gap-4">
          <div
            className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${
              isDestructive
                ? 'bg-rose-100 text-rose-600 dark:bg-rose-950/50 dark:text-rose-400'
                : 'bg-amber-100 text-amber-600 dark:bg-amber-950/50 dark:text-amber-400'
            }`}
          >
            <AlertTriangle className="h-6 w-6" />
          </div>

          <div className="flex-1">
            <h3 className="text-base font-bold text-[#14283F] dark:text-[#F1F5F9]">
              {title}
            </h3>
            <p className="mt-2 text-sm text-[#64748B] dark:text-[#A5B4C7] leading-relaxed">
              {message}
            </p>
          </div>
        </div>

        <div className="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={onCancel}
            disabled={isLoading}
            className="rounded-xl border border-[#DCE9EE] bg-white px-4 py-2.5 text-sm font-semibold text-[#14283F] hover:bg-[#EDF6F8] disabled:opacity-50 dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:hover:bg-[#0B1728] cursor-pointer"
          >
            {cancelLabel || t.cancel}
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={isLoading}
            className={`rounded-xl px-4 py-2.5 text-sm font-semibold text-white shadow-sm disabled:opacity-50 flex items-center gap-2 cursor-pointer ${
              isDestructive
                ? 'bg-rose-600 hover:bg-rose-700'
                : 'bg-[#0D9488] hover:bg-[#0F766E] dark:bg-[#14B8A6] dark:text-[#07131D] dark:hover:bg-[#2DD4BF]'
            }`}
          >
            {isLoading && (
              <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
            )}
            {confirmLabel || t.confirm}
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
};
