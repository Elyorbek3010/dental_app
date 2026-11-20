import React from 'react';
import {
  CheckCircle2,
  Clock,
  PauseCircle,
  PhoneCall,
  PlayCircle,
  SkipForward,
  XCircle,
} from 'lucide-react';
import { useI18n } from '../../i18n/useI18n';
import type { TicketStatus } from '../../types/reception';

interface StatusBadgeProps {
  status: TicketStatus | 'ACTIVE' | 'PAUSED' | 'NOT_OPEN';
  size?: 'sm' | 'md' | 'lg';
}

export const StatusBadge: React.FC<StatusBadgeProps> = ({ status, size = 'md' }) => {
  const { t } = useI18n();

  const sizeClasses = {
    sm: 'px-2.5 py-0.5 text-[11px] font-semibold gap-1',
    md: 'px-2.5 py-1 text-xs font-semibold gap-1.5',
    lg: 'px-3 py-1.5 text-sm font-semibold gap-1.5',
  }[size];

  switch (status) {
    case 'WAITING':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-[#E0F2FE] text-[#0369A1] ring-1 ring-[#0284C7]/20 dark:bg-[#10324F] dark:text-[#38BDF8] dark:ring-[#38BDF8]/30 ${sizeClasses}`}
        >
          <Clock className="h-3 w-3 shrink-0" />
          {t.statusWaiting}
        </span>
      );
    case 'CALLED':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-amber-50 text-amber-800 ring-1 ring-amber-600/25 dark:bg-amber-950/60 dark:text-amber-300 dark:ring-amber-400/35 ${sizeClasses}`}
        >
          <PhoneCall className="h-3 w-3 shrink-0" />
          {t.statusCalled}
        </span>
      );
    case 'SERVING':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-[#DDF7F0] text-[#0F766E] ring-1 ring-[#0D9488]/25 dark:bg-[#12353D] dark:text-[#2DD4BF] dark:ring-[#2DD4BF]/35 ${sizeClasses}`}
        >
          <span className="h-2 w-2 rounded-full bg-[#0D9488] dark:bg-[#2DD4BF] animate-pulse shrink-0" />
          {t.statusServing}
        </span>
      );
    case 'COMPLETED':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-emerald-600/20 dark:bg-emerald-950/50 dark:text-emerald-300 dark:ring-emerald-400/25 ${sizeClasses}`}
        >
          <CheckCircle2 className="h-3 w-3 shrink-0" />
          {t.statusCompleted}
        </span>
      );
    case 'SKIPPED':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-rose-50 text-rose-700 ring-1 ring-rose-600/20 dark:bg-rose-950/50 dark:text-rose-300 dark:ring-rose-400/30 ${sizeClasses}`}
        >
          <SkipForward className="h-3 w-3 shrink-0" />
          {t.statusSkipped}
        </span>
      );
    case 'CANCELLED':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-slate-100 text-slate-600 ring-1 ring-slate-500/15 dark:bg-slate-800/80 dark:text-slate-300 dark:ring-slate-600/40 ${sizeClasses}`}
        >
          <XCircle className="h-3 w-3 shrink-0" />
          {t.statusCancelled}
        </span>
      );
    case 'ACTIVE':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-emerald-600/20 dark:bg-emerald-950/50 dark:text-emerald-300 dark:ring-emerald-400/30 ${sizeClasses}`}
        >
          <PlayCircle className="h-3 w-3 shrink-0" />
          {t.queueStateActive}
        </span>
      );
    case 'PAUSED':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-amber-50 text-amber-800 ring-1 ring-amber-600/25 dark:bg-amber-950/50 dark:text-amber-300 dark:ring-amber-400/30 ${sizeClasses}`}
        >
          <PauseCircle className="h-3 w-3 shrink-0" />
          {t.queueStatePaused}
        </span>
      );
    case 'NOT_OPEN':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-[#EDF6F8] text-[#64748B] ring-1 ring-[#DCE9EE] dark:bg-[#1A3047] dark:text-[#A5B4C7] dark:ring-[#253F5B] ${sizeClasses}`}
        >
          <span className="h-1.5 w-1.5 rounded-full bg-[#94A3B8]" />
          {t.queueStateNotOpen}
        </span>
      );
    default:
      return null;
  }
};
