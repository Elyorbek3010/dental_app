import React from 'react';
import { useI18n } from '../../i18n/useI18n';
import type { TicketStatus } from '../../types/reception';

interface StatusBadgeProps {
  status: TicketStatus | 'ACTIVE' | 'PAUSED' | 'NOT_OPEN';
  size?: 'sm' | 'md' | 'lg';
}

export const StatusBadge: React.FC<StatusBadgeProps> = ({ status, size = 'md' }) => {
  const { t } = useI18n();

  const sizeClasses = {
    sm: 'px-2 py-0.5 text-xs font-medium',
    md: 'px-2.5 py-1 text-xs font-semibold tracking-wide',
    lg: 'px-3 py-1.5 text-sm font-semibold tracking-wide',
  }[size];

  switch (status) {
    case 'WAITING':
      return (
        <span className={`inline-flex items-center rounded-full bg-blue-50 text-blue-700 ring-1 ring-blue-700/10 dark:bg-blue-900/30 dark:text-blue-300 dark:ring-blue-400/20 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-blue-600 dark:bg-blue-400" />
          {t.statusWaiting}
        </span>
      );
    case 'CALLED':
      return (
        <span className={`inline-flex items-center rounded-full bg-amber-50 text-amber-800 ring-1 ring-amber-600/20 dark:bg-amber-900/30 dark:text-amber-300 dark:ring-amber-400/30 ${sizeClasses} animate-pulse`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-amber-600 dark:bg-amber-400" />
          {t.statusCalled}
        </span>
      );
    case 'SERVING':
      return (
        <span className={`inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-emerald-600/20 dark:bg-emerald-900/30 dark:text-emerald-300 dark:ring-emerald-400/30 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-emerald-600 dark:bg-emerald-400 animate-ping" />
          {t.statusServing}
        </span>
      );
    case 'COMPLETED':
      return (
        <span className={`inline-flex items-center rounded-full bg-zinc-100 text-zinc-700 ring-1 ring-zinc-600/10 dark:bg-zinc-800 dark:text-zinc-300 dark:ring-zinc-700 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-zinc-400" />
          {t.statusCompleted}
        </span>
      );
    case 'SKIPPED':
      return (
        <span className={`inline-flex items-center rounded-full bg-purple-50 text-purple-700 ring-1 ring-purple-700/10 dark:bg-purple-900/30 dark:text-purple-300 dark:ring-purple-400/20 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-purple-500" />
          {t.statusSkipped}
        </span>
      );
    case 'CANCELLED':
      return (
        <span className={`inline-flex items-center rounded-full bg-rose-50 text-rose-700 ring-1 ring-rose-600/10 dark:bg-rose-900/30 dark:text-rose-300 dark:ring-rose-400/20 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-rose-500" />
          {t.statusCancelled}
        </span>
      );
    case 'ACTIVE':
      return (
        <span className={`inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 ring-1 ring-emerald-600/20 dark:bg-emerald-900/30 dark:text-emerald-300 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-emerald-500" />
          {t.queueStateActive}
        </span>
      );
    case 'PAUSED':
      return (
        <span className={`inline-flex items-center rounded-full bg-amber-50 text-amber-700 ring-1 ring-amber-600/20 dark:bg-amber-900/30 dark:text-amber-300 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-amber-500" />
          {t.queueStatePaused}
        </span>
      );
    case 'NOT_OPEN':
      return (
        <span className={`inline-flex items-center rounded-full bg-zinc-100 text-zinc-600 ring-1 ring-zinc-500/10 dark:bg-zinc-800 dark:text-zinc-400 ${sizeClasses}`}>
          <span className="mr-1.5 h-1.5 w-1.5 rounded-full bg-zinc-400" />
          {t.queueStateNotOpen}
        </span>
      );
    default:
      return null;
  }
};
