import React, { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Eye, EyeOff, Globe, Lock, Phone, ShieldCheck } from 'lucide-react';
import { useAuth } from '../context/useAuth';
import { useI18n } from '../i18n/useI18n';
import type { Language } from '../i18n/types';
import { AlertBanner } from '../components/common/AlertBanner';
import { AppButton } from '../components/common/AppButton';
import { DentalLogo } from '../components/common/DentalLogo';
import { ThemeToggle } from '../components/common/ThemeToggle';

export const LoginPage: React.FC = () => {
  const { user, login, isAuthenticated, authError, clearAuthError } = useAuth();
  const { language, setLanguage, t } = useI18n();
  const navigate = useNavigate();

  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  if (isAuthenticated && user) {
    if (user.role === 'ADMIN') {
      return <Navigate to="/admin" replace />;
    }
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
      const loggedInUser = await login(trimmedPhone, password);
      if (loggedInUser.role === 'ADMIN') {
        navigate('/admin', { replace: true });
      } else {
        navigate('/reception', { replace: true });
      }
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
    <div className="min-h-screen w-screen bg-[#F5FAFB] dark:bg-[#0B1728] lg:grid lg:grid-cols-12">
      {/* Left Editorial Clinical Showcase Panel (Desktop) */}
      <aside className="hidden lg:flex lg:col-span-5 relative overflow-hidden bg-gradient-to-br from-[#0F766E] via-[#0D9488] to-[#0284C7] p-12 text-white flex-col justify-between">
        <div
          className="pointer-events-none absolute -right-24 -top-24 h-80 w-80 rounded-full bg-white/10 blur-2xl"
          aria-hidden="true"
        />
        <div
          className="pointer-events-none absolute -left-16 bottom-12 h-64 w-64 rounded-full bg-[#38BDF8]/20 blur-2xl"
          aria-hidden="true"
        />

        <div className="relative z-10 flex items-center gap-3.5">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/15 border border-white/25 backdrop-blur-xs">
            <DentalLogo size="md" />
          </div>
          <div>
            <span className="text-lg font-extrabold tracking-tight block">{t.appTitle}</span>
            <span className="text-xs font-medium text-teal-100/90 uppercase tracking-widest">
              {t.clinicLabel}
            </span>
          </div>
        </div>

        <div className="relative z-10 space-y-6 max-w-md">
          <h2 className="text-3xl font-extrabold tracking-tight leading-tight">
            {t.loginTitle}
          </h2>
          <p className="text-sm text-teal-50/90 leading-relaxed">
            {t.loginSubtitle}
          </p>

          <div className="space-y-3 pt-2">
            <div className="flex items-center gap-3 rounded-2xl bg-white/10 border border-white/15 px-4 py-3 backdrop-blur-xs">
              <ShieldCheck className="h-5 w-5 text-[#DDF7F0] shrink-0" />
              <span className="text-xs font-semibold">{t.smartCall} &amp; {t.clinicQrTitle}</span>
            </div>
          </div>
        </div>

        <p className="relative z-10 text-xs text-teal-100/75">
          Clean Premium Dental
        </p>
      </aside>

      {/* Right Sign-In Form Workspace */}
      <main className="lg:col-span-7 relative flex min-h-screen flex-col justify-center px-4 py-12 sm:px-8 lg:px-14">
        {/* Top Controls: Theme + Language */}
        <div className="absolute top-4 right-4 sm:top-6 sm:right-6 z-10 flex flex-wrap items-center justify-end gap-2.5">
          <ThemeToggle compact />
          <div className="inline-flex items-center gap-1.5 rounded-xl border border-[#DCE9EE] bg-white p-1 shadow-2xs dark:border-[#253F5B] dark:bg-[#12243A]">
            <Globe className="ml-1.5 h-3.5 w-3.5 text-[#64748B] dark:text-[#A5B4C7]" />
            {languages.map((l) => (
              <button
                key={l.code}
                type="button"
                onClick={() => setLanguage(l.code)}
                className={`rounded-lg px-2.5 py-1 text-xs font-semibold transition-colors cursor-pointer ${
                  language === l.code
                    ? 'bg-[#0D9488] text-white dark:bg-[#14B8A6] dark:text-[#07131D]'
                    : 'text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9]'
                }`}
              >
                {l.label}
              </button>
            ))}
          </div>
        </div>

        <div className="mx-auto w-full max-w-md animate-dental-in">
          <div className="flex flex-col items-start text-left lg:hidden mb-6">
            <div className="flex items-center gap-3">
              <DentalLogo size="md" />
              <div>
                <span className="text-lg font-extrabold text-[#14283F] dark:text-[#F1F5F9] block">
                  {t.appTitle}
                </span>
                <span className="text-xs font-medium text-[#0D9488] dark:text-[#2DD4BF]">
                  {t.clinicLabel}
                </span>
              </div>
            </div>
          </div>

          <h1 className="text-2xl font-extrabold tracking-tight text-[#14283F] dark:text-[#F1F5F9]">
            {t.loginTitle}
          </h1>
          <p className="mt-1.5 text-sm text-[#64748B] dark:text-[#A5B4C7]">
            {t.loginSubtitle}
          </p>

          <div className="mt-7 rounded-3xl border border-[#DCE9EE] bg-white p-7 sm:p-8 shadow-xl shadow-slate-900/5 dark:border-[#253F5B] dark:bg-[#12243A] dark:shadow-black/30">
            {displayError && (
              <div className="mb-5">
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
                <label className="block text-xs font-semibold uppercase tracking-wider text-[#14283F] dark:text-[#F1F5F9]">
                  {t.phoneLabel}
                </label>
                <div className="relative mt-1.5">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 text-[#64748B] dark:text-[#A5B4C7]">
                    <Phone className="h-4 w-4" />
                  </div>
                  <input
                    type="tel"
                    required
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder={t.phonePlaceholder}
                    disabled={isSubmitting}
                    className="block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] py-3 pr-3.5 pl-10 text-sm text-[#14283F] placeholder-[#64748B]/75 shadow-2xs focus:border-[#0D9488] focus:bg-white focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 disabled:opacity-60 dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728] dark:focus:text-[#F1F5F9]"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-[#14283F] dark:text-[#F1F5F9]">
                  {t.passwordLabel}
                </label>
                <div className="relative mt-1.5">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3.5 text-[#64748B] dark:text-[#A5B4C7]">
                    <Lock className="h-4 w-4" />
                  </div>
                  <input
                    type={showPassword ? 'text' : 'password'}
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder={t.passwordPlaceholder}
                    disabled={isSubmitting}
                    className="block w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] py-3 pr-10 pl-10 text-sm text-[#14283F] placeholder-[#64748B]/75 shadow-2xs focus:border-[#0D9488] focus:bg-white focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 disabled:opacity-60 dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728] dark:focus:text-[#F1F5F9]"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((prev) => !prev)}
                    aria-label="Toggle password visibility"
                    className="absolute inset-y-0 right-0 flex items-center pr-3 text-[#64748B] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:text-[#F1F5F9] cursor-pointer"
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>

              <AppButton
                type="submit"
                variant="primary"
                size="lg"
                loading={isSubmitting}
                className="w-full"
              >
                {isSubmitting ? t.loggingIn : t.loginButton}
              </AppButton>
            </form>
          </div>
        </div>
      </main>
    </div>
  );
};
