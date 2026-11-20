import React from 'react';

interface LoadingSkeletonProps {
  rows?: number;
  cards?: number;
}

export const LoadingSkeleton: React.FC<LoadingSkeletonProps> = ({
  rows = 4,
  cards = 0,
}) => {
  return (
    <div className="space-y-4" aria-busy="true">
      {cards > 0 && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {Array.from({ length: cards }).map((_, idx) => (
            <div
              key={idx}
              className="h-28 rounded-2xl border border-[#DCE9EE] bg-white p-5 dark:border-[#253F5B] dark:bg-[#12243A]"
            >
              <div className="h-3 w-24 rounded-full bg-[#EDF6F8] dark:bg-[#1A3047] animate-pulse" />
              <div className="mt-5 h-7 w-16 rounded-lg bg-[#EDF6F8] dark:bg-[#1A3047] animate-pulse" />
            </div>
          ))}
        </div>
      )}
      {rows > 0 && (
        <div className="rounded-2xl border border-[#DCE9EE] bg-white p-5 space-y-3 dark:border-[#253F5B] dark:bg-[#12243A]">
          {Array.from({ length: rows }).map((_, idx) => (
            <div
              key={idx}
              className="h-10 w-full rounded-xl bg-[#EDF6F8] dark:bg-[#1A3047] animate-pulse"
            />
          ))}
        </div>
      )}
    </div>
  );
};
