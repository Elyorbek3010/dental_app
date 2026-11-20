import React from 'react';

interface EmptyStateProps {
  title: string;
  description?: string;
  icon?: React.ReactNode;
  action?: React.ReactNode;
  compact?: boolean;
}

export const EmptyState: React.FC<EmptyStateProps> = ({
  title,
  description,
  icon,
  action,
  compact = false,
}) => {
  return (
    <div
      className={`rounded-2xl border border-dashed border-[#DCE9EE] bg-white/70 text-center dark:border-[#253F5B] dark:bg-[#12243A]/70 ${
        compact ? 'px-5 py-8' : 'px-6 py-12'
      }`}
    >
      <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
        {icon ?? (
          <svg
            viewBox="0 0 24 24"
            fill="none"
            className="h-6 w-6"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              d="M7.5 4.25C5.25 4.25 3.5 6.08 3.5 8.55c0 2.34.86 4.86 1.63 7.36.56 1.83 1.24 3.84 2.36 3.84.95 0 1.44-1.39 2.02-2.99.51-1.42 1.13-2.26 2.49-2.26s1.98.84 2.49 2.26c.58 1.6 1.07 2.99 2.02 2.99 1.12 0 1.8-2.01 2.36-3.84.77-2.5 1.63-5.02 1.63-7.36 0-2.47-1.75-4.3-4-4.3-1.47 0-2.54.73-3.51 1.38-.6.4-1.38.4-1.98 0C10.04 4.98 8.97 4.25 7.5 4.25Z"
              fill="currentColor"
              fillOpacity="0.9"
            />
          </svg>
        )}
      </div>
      <h3 className="text-sm sm:text-base font-bold text-[#14283F] dark:text-[#F1F5F9]">
        {title}
      </h3>
      {description && (
        <p className="mx-auto mt-1 max-w-md text-xs text-[#64748B] dark:text-[#A5B4C7]">
          {description}
        </p>
      )}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
};
