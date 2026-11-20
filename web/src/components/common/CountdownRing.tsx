import React from 'react';
import { Clock, PauseCircle } from 'lucide-react';
import { formatCountdownMmSs } from '../../hooks/useSmartCallCountdown';

interface CountdownRingProps {
  remainingSeconds: number;
  totalSeconds?: number;
  isPaused?: boolean;
  label?: string;
  pausedLabel?: string;
  size?: 'md' | 'lg';
  forceDark?: boolean;
}

export const CountdownRing: React.FC<CountdownRingProps> = ({
  remainingSeconds,
  totalSeconds = 120,
  isPaused = false,
  label,
  pausedLabel,
  size = 'md',
  forceDark = false,
}) => {
  const safeMax = Math.max(1, totalSeconds, remainingSeconds);
  const ratio = Math.max(0, Math.min(1, remainingSeconds / safeMax));
  const isWarning = !isPaused && remainingSeconds <= 15;

  const px = size === 'lg' ? 88 : 68;
  const strokeWidth = size === 'lg' ? 6 : 5;
  const radius = (px - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference * (1 - ratio);

  const ringStrokeClass = isPaused
    ? forceDark
      ? 'stroke-amber-400'
      : 'stroke-amber-500 dark:stroke-amber-400'
    : isWarning
      ? forceDark
        ? 'stroke-rose-400'
        : 'stroke-rose-600 dark:stroke-rose-400'
      : forceDark
        ? 'stroke-[#2DD4BF]'
        : 'stroke-[#0D9488] dark:stroke-[#2DD4BF]';

  const textClass = isPaused
    ? forceDark
      ? 'text-amber-300'
      : 'text-amber-700 dark:text-amber-300'
    : isWarning
      ? forceDark
        ? 'text-rose-300'
        : 'text-rose-700 dark:text-rose-300'
      : forceDark
        ? 'text-[#F1F5F9]'
        : 'text-[#14283F] dark:text-[#F1F5F9]';

  const containerClass = forceDark
    ? 'border-[#253F5B] bg-[#12243A]'
    : 'border-[#DCE9EE] bg-white/95 dark:border-[#253F5B] dark:bg-[#1A3047]';

  const trackStrokeClass = forceDark ? 'stroke-[#253F5B]' : 'stroke-[#DCE9EE] dark:stroke-[#253F5B]';
  const labelTextClass = forceDark ? 'text-[#A5B4C7]' : 'text-[#64748B] dark:text-[#A5B4C7]';

  return (
    <div className={`inline-flex items-center gap-3.5 rounded-2xl border px-3.5 py-2.5 shadow-2xs ${containerClass}`}>
      <div className="relative flex items-center justify-center shrink-0" style={{ width: px, height: px }}>
        <svg width={px} height={px} className="-rotate-90">
          <circle
            cx={px / 2}
            cy={px / 2}
            r={radius}
            fill="none"
            strokeWidth={strokeWidth}
            className={trackStrokeClass}
          />
          <circle
            cx={px / 2}
            cy={px / 2}
            r={radius}
            fill="none"
            strokeWidth={strokeWidth}
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={dashOffset}
            className={`${ringStrokeClass} transition-all duration-300`}
          />
        </svg>
        <span
          className={`absolute font-mono font-extrabold tabular-nums ${
            size === 'lg' ? 'text-lg' : 'text-sm'
          } ${textClass}`}
        >
          {formatCountdownMmSs(remainingSeconds)}
        </span>
      </div>

      <div className="text-left min-w-0">
        {label && (
          <div className={`flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider ${labelTextClass}`}>
            {isPaused ? (
              <PauseCircle className="h-3.5 w-3.5 text-amber-500 shrink-0" />
            ) : (
              <Clock
                className={`h-3.5 w-3.5 shrink-0 ${
                  isWarning
                    ? 'text-rose-500'
                    : forceDark
                      ? 'text-[#2DD4BF]'
                      : 'text-[#0D9488] dark:text-[#2DD4BF]'
                }`}
              />
            )}
            <span>{label}</span>
          </div>
        )}
        <div className={`mt-0.5 font-mono font-black tabular-nums ${size === 'lg' ? 'text-xl' : 'text-base'} ${textClass}`}>
          {formatCountdownMmSs(remainingSeconds)}
        </div>
        {isPaused && pausedLabel && (
          <span className="mt-1 inline-flex items-center rounded-md bg-amber-50 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-amber-700 dark:bg-amber-950/60 dark:text-amber-300">
            {pausedLabel}
          </span>
        )}
      </div>
    </div>
  );
};
