import React from 'react';

type StatTone = 'teal' | 'blue' | 'amber' | 'emerald' | 'rose' | 'neutral';

interface StatCardProps {
  label: string;
  value: string | number;
  subValue?: string;
  subLabel?: string;
  helperText?: string;
  icon: React.ReactNode;
  tone?: StatTone;
  variant?: 'default' | 'tinted';
}

export const StatCard: React.FC<StatCardProps> = ({
  label,
  value,
  subValue,
  subLabel,
  helperText,
  icon,
  tone = 'teal',
  variant = 'default',
}) => {
  const iconToneClasses: Record<StatTone, string> = {
    teal: 'bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]',
    blue: 'bg-[#E0F2FE] text-[#0369A1] dark:bg-[#10324F] dark:text-[#38BDF8]',
    amber: 'bg-amber-100/80 text-amber-700 dark:bg-amber-950/60 dark:text-amber-300',
    emerald: 'bg-emerald-100/80 text-emerald-700 dark:bg-emerald-950/60 dark:text-emerald-300',
    rose: 'bg-rose-100/80 text-rose-700 dark:bg-rose-950/60 dark:text-rose-300',
    neutral: 'bg-[#EDF6F8] text-[#64748B] dark:bg-[#1A3047] dark:text-[#A5B4C7]',
  };

  const cardSurfaceClass: string =
    variant === 'tinted'
      ? {
          teal: 'border-[#0D9488]/15 bg-[#EEF9F7] dark:border-[#2DD4BF]/20 dark:bg-[#102E35]',
          blue: 'border-[#0284C7]/15 bg-[#EEF7FC] dark:border-[#38BDF8]/20 dark:bg-[#112A42]',
          amber: 'border-amber-200/70 bg-[#FDF8EE] dark:border-amber-700/30 dark:bg-[#2B2418]',
          emerald: 'border-emerald-200/70 bg-[#EFFAF3] dark:border-emerald-700/30 dark:bg-[#112E26]',
          rose: 'border-rose-200/70 bg-[#FDF2F2] dark:border-rose-700/30 dark:bg-[#2E1A22]',
          neutral: 'border-[#DCE9EE] bg-[#F5FAFB] dark:border-[#253F5B] dark:bg-[#162B42]',
        }[tone]
      : 'border-[#DCE9EE] bg-white dark:border-[#253F5B] dark:bg-[#12243A]';

  if (variant === 'tinted') {
    return (
      <div
        className={`rounded-2xl border p-4.5 shadow-2xs transition-all duration-150 hover:-translate-y-0.5 hover:shadow-xs motion-reduce:transition-none motion-reduce:hover:translate-y-0 ${cardSurfaceClass}`}
      >
        <div className="flex items-center gap-3">
          <div
            className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl ${iconToneClasses[tone]}`}
          >
            {icon}
          </div>
          <div className="min-w-0">
            <p className="text-xs font-bold text-[#14283F] dark:text-[#F1F5F9] truncate">
              {label}
            </p>
            {subLabel && (
              <p className="text-[11px] font-medium text-[#64748B] dark:text-[#A5B4C7] truncate">
                {subLabel}
              </p>
            )}
          </div>
        </div>
        <div className="mt-3 flex items-baseline gap-2">
          <span className="text-2xl sm:text-3xl font-black tracking-tight tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
            {value}
          </span>
          {subValue && (
            <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7]">
              {subValue}
            </span>
          )}
        </div>
        {helperText && (
          <p className="mt-1.5 text-[11px] font-medium text-[#64748B] dark:text-[#A5B4C7] leading-snug">
            {helperText}
          </p>
        )}
      </div>
    );
  }

  return (
    <div
      className={`rounded-2xl border p-4.5 shadow-2xs transition-all duration-150 hover:-translate-y-0.5 hover:border-[#0D9488]/40 hover:shadow-xs motion-reduce:transition-none motion-reduce:hover:translate-y-0 dark:hover:border-[#2DD4BF]/40 ${cardSurfaceClass}`}
    >
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-wide text-[#64748B] dark:text-[#A5B4C7]">
          {label}
        </p>
        <div
          className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${iconToneClasses[tone]}`}
        >
          {icon}
        </div>
      </div>
      <div className="mt-2.5 flex items-baseline gap-2">
        <span className="text-2xl font-bold tracking-tight tabular-nums text-[#14283F] dark:text-[#F1F5F9]">
          {value}
        </span>
        {subValue && (
          <span className="text-xs font-medium text-[#64748B] dark:text-[#A5B4C7]">
            {subValue}
          </span>
        )}
      </div>
      {helperText && (
        <p className="mt-1.5 text-xs font-medium text-[#64748B] dark:text-[#A5B4C7] leading-snug">
          {helperText}
        </p>
      )}
    </div>
  );
};
