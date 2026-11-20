import React from 'react';
import { Monitor, Moon, Sun } from 'lucide-react';
import { useTheme } from '../../context/useTheme';
import { useI18n } from '../../i18n/useI18n';
import type { ThemePreference } from '../../context/ThemeContextDefinition';

interface ThemeToggleProps {
  compact?: boolean;
}

export const ThemeToggle: React.FC<ThemeToggleProps> = ({ compact = false }) => {
  const { preference, setPreference } = useTheme();
  const { t } = useI18n();

  const options: {
    value: ThemePreference;
    label: string;
    icon: React.ReactNode;
  }[] = [
    {
      value: 'light',
      label: t.themeLight,
      icon: <Sun className="h-3.5 w-3.5" />,
    },
    {
      value: 'dark',
      label: t.themeDark,
      icon: <Moon className="h-3.5 w-3.5" />,
    },
    {
      value: 'system',
      label: t.themeSystem,
      icon: <Monitor className="h-3.5 w-3.5" />,
    },
  ];

  return (
    <div
      role="group"
      aria-label={t.themeLabel}
      className="inline-flex items-center rounded-xl border border-[#DCE9EE] bg-[#EDF6F8] p-0.5 dark:border-[#253F5B] dark:bg-[#0B1728]"
    >
      {options.map((opt) => {
        const isActive = preference === opt.value;
        return (
          <button
            key={opt.value}
            type="button"
            onClick={() => setPreference(opt.value)}
            title={opt.label}
            aria-label={opt.label}
            aria-pressed={isActive}
            className={`inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs font-semibold transition-all cursor-pointer ${
              isActive
                ? 'bg-white text-[#0F766E] shadow-xs dark:bg-[#1A3047] dark:text-[#2DD4BF]'
                : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
            }`}
          >
            {opt.icon}
            {!compact && <span className="hidden xl:inline">{opt.label}</span>}
          </button>
        );
      })}
    </div>
  );
};
