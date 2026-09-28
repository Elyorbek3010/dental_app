import { createContext } from 'react';
import type { Language, TranslationDictionary } from './types';

export interface I18nContextValue {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: TranslationDictionary;
}

export const I18nContext = createContext<I18nContextValue | null>(null);
