import React from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'blue' | 'amber' | 'danger' | 'ghost';
type ButtonSize = 'xs' | 'sm' | 'md' | 'lg';

interface AppButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
  icon?: React.ReactNode;
}

export const AppButton: React.FC<AppButtonProps> = ({
  variant = 'primary',
  size = 'md',
  loading = false,
  icon,
  children,
  className = '',
  disabled,
  type = 'button',
  ...props
}) => {
  const variantClasses: Record<ButtonVariant, string> = {
    primary:
      'bg-[#0D9488] text-white hover:bg-[#0F766E] focus-visible:ring-[#0D9488] dark:bg-[#14B8A6] dark:text-[#07131D] dark:hover:bg-[#2DD4BF] shadow-xs',
    secondary:
      'border border-[#DCE9EE] bg-white text-[#14283F] hover:bg-[#EDF6F8] focus-visible:ring-[#0D9488] dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:hover:bg-[#223C58]',
    blue:
      'bg-[#0284C7] text-white hover:bg-[#0369A1] focus-visible:ring-[#0284C7] dark:bg-[#38BDF8] dark:text-[#07131D] dark:hover:bg-[#7DD3FC] shadow-xs',
    amber:
      'bg-amber-600 text-white hover:bg-amber-700 focus-visible:ring-amber-500 dark:bg-amber-500 dark:text-slate-950 dark:hover:bg-amber-400 shadow-xs',
    danger:
      'bg-rose-600 text-white hover:bg-rose-700 focus-visible:ring-rose-500 dark:bg-rose-500 dark:text-white dark:hover:bg-rose-400 shadow-xs',
    ghost:
      'text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] focus-visible:ring-[#0D9488] dark:text-[#A5B4C7] dark:hover:bg-[#1A3047] dark:hover:text-[#F1F5F9]',
  };

  const sizeClasses: Record<ButtonSize, string> = {
    xs: 'px-2.5 py-1.5 text-xs rounded-lg gap-1.5',
    sm: 'px-3 py-1.5 text-xs rounded-xl gap-1.5',
    md: 'px-4 py-2.5 text-xs sm:text-sm rounded-xl gap-2',
    lg: 'px-5 py-3 text-sm rounded-xl gap-2',
  };

  return (
    <button
      type={type}
      disabled={disabled || loading}
      className={`inline-flex items-center justify-center font-semibold transition-all duration-150 focus:outline-hidden focus-visible:ring-2 focus-visible:ring-offset-1 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer ${variantClasses[variant]} ${sizeClasses[size]} ${className}`}
      {...props}
    >
      {loading ? (
        <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />
      ) : (
        icon
      )}
      {children}
    </button>
  );
};
