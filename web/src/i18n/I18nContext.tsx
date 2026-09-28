import React, { useEffect, useState } from 'react';
import type { Language } from './types';
import { translations } from './translations';
import { I18nContext, type I18nContextValue } from './I18nContextDefinition';

const STORAGE_KEY = 'dental_reception_lang';

export const I18nProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [language, setLanguageState] = useState<Language>(() => {
    const saved = localStorage.getItem(STORAGE_KEY) as Language | null;
    if (saved && (saved === 'uz' || saved === 'ru' || saved === 'en')) {
      return saved;
    }
    return 'uz';
  });

  const setLanguage = (lang: Language) => {
    setLanguageState(lang);
    localStorage.setItem(STORAGE_KEY, lang);
  };

  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);

  const value: I18nContextValue = {
    language,
    setLanguage,
    t: translations[language],
  };

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
};
