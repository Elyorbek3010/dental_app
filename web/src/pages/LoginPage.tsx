import React, { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Globe, Lock, Phone, Stethoscope } from 'lucide-react';
import { useAuth } from '../context/useAuth';
import { useI18n } from '../i18n/useI18n';
import type { Language } from '../i18n/types';
import { AlertBanner } from '../components/common/AlertBanner';

export const LoginPage: React.FC = () => {
  const { login, isAuthenticated, authError, clearAuthError } = useAuth();
  const { language, setLanguage, t } = useI18n();
  const navigate = useNavigate();

  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  if (isAuthenticated) {
    return <Navigate to="/reception" replace />;
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    clearAuthError();
    setErrorMessage(null);

    const trimmedPhone = phone.trim();
    if (!trimmedPhone || !password) {
      setErrorMessage(t.loginErrorInvalid);
      return;
    }

    setIsSubmitting(true);
    try {
      await login(trimmedPhone, password);
      navigate('/reception', { replace: true });
    } catch (err: unknown) {
      if (err instanceof Error) {
        if (err.message === 'PATIENT_DENIED') {
          setErrorMessage(t.loginErrorPatientDenied);
        } else if (err.message.includes('401') || err.message.toLowerCase().includes('credentials')) {
          setErrorMessage(t.loginErrorInvalid);
        } else if (err.message.includes('403') || err.message.toLowerCase().includes('inactive')) {
          setErrorMessage(t.loginErrorInactive);
        } else {
          setErrorMessage(err.message || t.loginErrorNetwork);
        }
      } else {
        setErrorMessage(t.loginErrorNetwork);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const languages: { code: Language; label: string }[] = [
    { code: 'uz', label: "O'zbekcha" },
    { code: 'ru', label: 'Русский' },
    { code: 'en', label: 'English' },
  ];

  const displayError =
    errorMessage ||
    (authError === 'PATIENT_DENIED'
      ? t.loginErrorPatientDenied
      : authError === 'SESSION_EXPIRED'
      ? t.sessionExpired
      : null);

  return (
    <div className="flex min-h-screen w-screen flex-col justify-center bg-zinc-50 px-4 py-12 sm:px-6 lg:px-8 dark:bg-zinc-950 font-sans">
      {/* Top Language Bar */}
      <div className="absolute top-6 right-6 flex items-center gap-2">
        <Globe className="h-4 w-4 text-zinc-400" />
        <div className="flex rounded-xl border border-zinc-200 bg-white p-1 shadow-2xs dark:border-zinc-800 dark:bg-zinc-900">
          {languages.map((l) => (
            <button
              key={l.code}
              type="button"
              onClick={() => setLanguage(l.code)}
              className={`rounded-lg px-2.5 py-1 text-xs font-semibold transition-colors ${
                language === l.code
                  ? 'bg-indigo-600 text-white shadow-2xs'
                  : 'text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-200'
              }`}
            >
              {l.label}
            </button>
          ))}
        </div>
      </div>

      <div className="sm:mx-auto sm:w-full sm:max-w-md">
        <div className="flex justify-center">
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-indigo-600 text-white shadow-lg shadow-indigo-500/25">
            <Stethoscope className="h-7 w-7" />
          </div>
        </div>
        <h2 className="mt-5 text-center text-2xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
          {t.loginTitle}
        </h2>
        <p className="mt-1 text-center text-xs text-zinc-500 dark:text-zinc-400">
          {t.loginSubtitle}
        </p>
      </div>

      <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div className="rounded-2xl border border-zinc-200 bg-white p-8 shadow-xl dark:border-zinc-800 dark:bg-zinc-900">
          {displayError && (
            <div className="mb-6">
              <AlertBanner
                type="error"
                message={displayError}
                onClose={() => {
                  setErrorMessage(null);
                  clearAuthError();
                }}
              />
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-5">
            <div>
              <label className="block text-xs font-semibold text-zinc-700 dark:text-zinc-300 uppercase tracking-wider">
                {t.phoneLabel}
              </label>
              <div className="relative mt-1.5">
                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 text-zinc-400">
                  <Phone className="h-4 w-4" />
                </div>
                <input
                  type="tel"
                  required
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder={t.phonePlaceholder}
                  disabled={isSubmitting}
                  className="block w-full rounded-xl border border-zinc-300 bg-white py-2.5 pr-3.5 pl-10 text-sm text-zinc-900 placeholder-zinc-400 shadow-2xs focus:border-indigo-500 focus:outline-hidden focus:ring-2 focus:ring-indigo-500/20 disabled:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100 dark:placeholder-zinc-500"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-zinc-700 dark:text-zinc-300 uppercase tracking-wider">
                {t.passwordLabel}
              </label>
              <div className="relative mt-1.5">
                <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 text-zinc-400">
                  <Lock className="h-4 w-4" />
                </div>
                <input
                  type="password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder={t.passwordPlaceholder}
                  disabled={isSubmitting}
                  className="block w-full rounded-xl border border-zinc-300 bg-white py-2.5 pr-3.5 pl-10 text-sm text-zinc-900 placeholder-zinc-400 shadow-2xs focus:border-indigo-500 focus:outline-hidden focus:ring-2 focus:ring-indigo-500/20 disabled:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100 dark:placeholder-zinc-500"
                />
              </div>
            </div>

            <button
              type="submit"
              disabled={isSubmitting || !phone || !password}
              className="mt-6 flex w-full items-center justify-center gap-2 rounded-xl bg-indigo-600 px-4 py-3 text-sm font-semibold text-white shadow-md shadow-indigo-500/20 hover:bg-indigo-700 focus:ring-2 focus:ring-indigo-500/20 disabled:opacity-50 transition-all cursor-pointer"
            >
              {isSubmitting && (
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
              )}
              {isSubmitting ? t.loggingIn : t.loginButton}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
};
