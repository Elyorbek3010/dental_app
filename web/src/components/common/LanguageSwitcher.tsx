import React, { useEffect, useRef, useState } from 'react';
import { Check, Globe } from 'lucide-react';
import { useI18n } from '../../i18n/useI18n';
import type { Language } from '../../i18n/types';

const LANGUAGES: { code: Language; label: string }[] = [
  { code: 'uz', label: "O'zbek (UZ)" },
  { code: 'ru', label: 'Русский (RU)' },
  { code: 'en', label: 'English (EN)' },
];

export const LanguageSwitcher: React.FC = () => {
  const { language, setLanguage } = useI18n();
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isOpen) return;

    const handleOutsidePress = (event: MouseEvent | TouchEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleOutsidePress);
    document.addEventListener('touchstart', handleOutsidePress);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('mousedown', handleOutsidePress);
      document.removeEventListener('touchstart', handleOutsidePress);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [isOpen]);

  const handleSelect = (code: Language) => {
    setLanguage(code);
    setIsOpen(false);
  };

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        onClick={() => setIsOpen((prev) => !prev)}
        aria-haspopup="listbox"
        aria-expanded={isOpen}
        aria-label="Language"
        className="flex items-center gap-1.5 rounded-xl border border-[#DCE9EE] bg-white px-2.5 py-1.5 text-xs font-semibold text-[#14283F] shadow-2xs hover:bg-[#EDF6F8] dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:hover:bg-[#223C58] transition-colors cursor-pointer"
      >
        <Globe className="h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
        <span className="uppercase">{language}</span>
      </button>

      {isOpen && (
        <div
          role="listbox"
          aria-label="Language options"
          className="absolute right-0 mt-2 w-40 rounded-xl border border-[#DCE9EE] bg-white p-1.5 shadow-lg dark:border-[#253F5B] dark:bg-[#1A3047] z-50"
        >
          {LANGUAGES.map((item) => {
            const isActive = language === item.code;
            return (
              <button
                key={item.code}
                type="button"
                role="option"
                aria-selected={isActive}
                onClick={() => handleSelect(item.code)}
                className={`flex w-full items-center justify-between gap-2 px-3 py-2 rounded-lg text-xs transition-colors cursor-pointer ${
                  isActive
                    ? 'bg-[#DDF7F0] text-[#0F766E] font-bold dark:bg-[#12353D] dark:text-[#2DD4BF]'
                    : 'font-medium text-[#14283F] hover:bg-[#EDF6F8] dark:text-[#F1F5F9] dark:hover:bg-[#12243A]'
                }`}
              >
                <span>{item.label}</span>
                {isActive && <Check className="h-3.5 w-3.5 shrink-0" />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
