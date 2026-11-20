import React from 'react';
import { AlertCircle, CheckCircle, Info, X } from 'lucide-react';

interface AlertBannerProps {
  type: 'error' | 'success' | 'info';
  message: string;
  onClose?: () => void;
}

export const AlertBanner: React.FC<AlertBannerProps> = ({ type, message, onClose }) => {
  if (!message) return null;

  const styles = {
    error: {
      bg: 'bg-rose-50 dark:bg-rose-950/40',
      border: 'border-rose-200 dark:border-rose-900',
      text: 'text-rose-800 dark:text-rose-200',
      icon: <AlertCircle className="h-5 w-5 text-rose-500 shrink-0 mt-0.5" />,
    },
    success: {
      bg: 'bg-emerald-50 dark:bg-emerald-950/40',
      border: 'border-emerald-200 dark:border-emerald-900',
      text: 'text-emerald-800 dark:text-emerald-200',
      icon: <CheckCircle className="h-5 w-5 text-emerald-500 shrink-0 mt-0.5" />,
    },
    info: {
      bg: 'bg-[#E0F2FE] dark:bg-[#10324F]/60',
      border: 'border-[#0284C7]/25 dark:border-[#38BDF8]/30',
      text: 'text-[#0369A1] dark:text-[#BAE6FD]',
      icon: <Info className="h-5 w-5 text-[#0284C7] dark:text-[#38BDF8] shrink-0 mt-0.5" />,
    },
  }[type];

  return (
    <div
      className={`flex items-start justify-between gap-3 rounded-xl border p-4 text-sm ${styles.bg} ${styles.border} ${styles.text} shadow-2xs animate-dental-in`}
    >
      <div className="flex items-start gap-3">
        {styles.icon}
        <span className="font-medium leading-relaxed">{message}</span>
      </div>
      {onClose && (
        <button
          onClick={onClose}
          className="rounded-md p-1 hover:bg-black/5 dark:hover:bg-white/5 opacity-70 hover:opacity-100 transition-opacity"
        >
          <X className="h-4 w-4" />
        </button>
      )}
    </div>
  );
};
