import React from 'react';

interface DentalLogoProps {
  className?: string;
  size?: 'sm' | 'md' | 'lg';
}

export const DentalLogo: React.FC<DentalLogoProps> = ({
  className = '',
  size = 'md',
}) => {
  const dimensions = {
    sm: 'h-8 w-8 rounded-lg',
    md: 'h-10 w-10 rounded-xl',
    lg: 'h-14 w-14 rounded-2xl',
  }[size];

  const iconSize = {
    sm: 'h-4 w-4',
    md: 'h-5 w-5',
    lg: 'h-8 w-8',
  }[size];

  return (
    <div
      className={`inline-flex items-center justify-center bg-gradient-to-br from-[#0D9488] to-[#0284C7] text-white shadow-sm shadow-teal-600/20 shrink-0 ${dimensions} ${className}`}
      aria-hidden="true"
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        className={iconSize}
        xmlns="http://www.w3.org/2000/svg"
      >
        <path
          d="M7.5 4.25C5.25 4.25 3.5 6.08 3.5 8.55c0 2.34.86 4.86 1.63 7.36.56 1.83 1.24 3.84 2.36 3.84.95 0 1.44-1.39 2.02-2.99.51-1.42 1.13-2.26 2.49-2.26s1.98.84 2.49 2.26c.58 1.6 1.07 2.99 2.02 2.99 1.12 0 1.8-2.01 2.36-3.84.77-2.5 1.63-5.02 1.63-7.36 0-2.47-1.75-4.3-4-4.3-1.47 0-2.54.73-3.51 1.38-.6.4-1.38.4-1.98 0C10.04 4.98 8.97 4.25 7.5 4.25Z"
          fill="currentColor"
          fillOpacity="0.95"
        />
        <path
          d="M8.75 8.5c.85-.45 1.95-.45 2.8 0"
          stroke="#0D9488"
          strokeWidth="1.4"
          strokeLinecap="round"
        />
      </svg>
    </div>
  );
};
