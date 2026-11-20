import React, { useCallback, useEffect, useState } from 'react';
import QRCode from 'qrcode';
import {
  Clock,
  Maximize2,
  Minimize2,
  QrCode,
  RefreshCw,
  ShieldCheck,
  X,
} from 'lucide-react';
import { fetchCheckInQrToken } from '../../api/reception';
import { useI18n } from '../../i18n/useI18n';
import { AppButton } from './AppButton';
import { AlertBanner } from './AlertBanner';

interface ClinicQrModalProps {
  isOpen: boolean;
  clinicId?: number;
  isAdminRole?: boolean;
  onClose: () => void;
}

function formatDurationHhMmSs(totalSeconds: number): string {
  const clamped = Math.max(0, totalSeconds);
  const hours = Math.floor(clamped / 3600);
  const minutes = Math.floor((clamped % 3600) / 60);
  const seconds = clamped % 60;
  if (hours > 0) {
    return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  }
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

export const ClinicQrModal: React.FC<ClinicQrModalProps> = ({
  isOpen,
  clinicId,
  isAdminRole = false,
  onClose,
}) => {
  const { t } = useI18n();
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [remainingSeconds, setRemainingSeconds] = useState<number>(0);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [isEnlarged, setIsEnlarged] = useState<boolean>(false);
  const [refreshTick, setRefreshTick] = useState<number>(0);

  const handleRefresh = useCallback(() => {
    setIsLoading(true);
    setError(null);
    setRefreshTick((prev) => prev + 1);
  }, []);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;

    fetchCheckInQrToken(isAdminRole ? clinicId : undefined)
      .then(async (res) => {
        const dataUrl = await QRCode.toDataURL(res.token, {
          width: 440,
          margin: 2,
          errorCorrectionLevel: 'M',
          color: {
            dark: '#14283F',
            light: '#FFFFFF',
          },
        });
        if (cancelled) return;
        setQrDataUrl(dataUrl);
        setRemainingSeconds(res.expires_in_seconds);
        setError(null);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        const msg = err instanceof Error ? err.message : t.errorGeneric;
        setError(msg);
        setQrDataUrl(null);
      })
      .finally(() => {
        if (!cancelled) {
          setIsLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [isOpen, clinicId, isAdminRole, refreshTick, t.errorGeneric]);

  useEffect(() => {
    if (!isOpen || remainingSeconds <= 0) return;
    const timer = window.setInterval(() => {
      setRemainingSeconds((prev) => Math.max(0, prev - 1));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [isOpen, remainingSeconds]);

  if (!isOpen) return null;

  const isFetching = isLoading || (qrDataUrl === null && error === null);
  const isExpired = !isFetching && !error && remainingSeconds <= 0 && qrDataUrl !== null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[#0B1728]/70 backdrop-blur-xs animate-dental-in"
      role="dialog"
      aria-modal="true"
      aria-labelledby="clinic-qr-title"
    >
      <div
        className={`relative w-full rounded-2xl border border-[#DCE9EE] bg-white p-6 shadow-2xl dark:border-[#253F5B] dark:bg-[#12243A] transition-all ${
          isEnlarged ? 'max-w-xl' : 'max-w-md'
        }`}
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF]">
              <QrCode className="h-5 w-5" />
            </div>
            <div>
              <h3
                id="clinic-qr-title"
                className="text-base font-bold text-[#14283F] dark:text-[#F1F5F9]"
              >
                {t.clinicQrTitle}
              </h3>
              <p className="mt-0.5 text-xs text-[#64748B] dark:text-[#A5B4C7]">
                {t.clinicQrSubtitle}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={() => setIsEnlarged((v) => !v)}
              title={isEnlarged ? t.clinicQrReduce : t.clinicQrEnlarge}
              aria-label={isEnlarged ? t.clinicQrReduce : t.clinicQrEnlarge}
              className="rounded-lg p-1.5 text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:bg-[#1A3047] dark:hover:text-[#F1F5F9] cursor-pointer"
            >
              {isEnlarged ? (
                <Minimize2 className="h-4 w-4" />
              ) : (
                <Maximize2 className="h-4 w-4" />
              )}
            </button>
            <button
              type="button"
              onClick={onClose}
              aria-label={t.cancel}
              className="rounded-lg p-1.5 text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:bg-[#1A3047] dark:hover:text-[#F1F5F9] cursor-pointer"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        <div className="mt-5 flex flex-col items-center">
          {error ? (
            <div className="w-full">
              <AlertBanner type="error" message={error} onClose={() => setError(null)} />
            </div>
          ) : isFetching ? (
            <div
              className={`flex items-center justify-center rounded-2xl border border-[#DCE9EE] bg-[#F5FAFB] dark:border-[#253F5B] dark:bg-[#0B1728] ${
                isEnlarged ? 'h-80 w-80' : 'h-60 w-60'
              }`}
            >
              <div className="h-9 w-9 animate-spin rounded-full border-3 border-[#0D9488] border-t-transparent" />
            </div>
          ) : qrDataUrl ? (
            <div className="relative rounded-2xl border border-[#DCE9EE] bg-white p-4 shadow-sm dark:border-[#253F5B]">
              <img
                src={qrDataUrl}
                alt={t.clinicQrTitle}
                className={`block select-none transition-all ${
                  isEnlarged ? 'h-72 w-72 sm:h-80 sm:w-80' : 'h-56 w-56'
                } ${isExpired ? 'opacity-25 blur-[1px]' : ''}`}
              />
              {isExpired && (
                <div className="absolute inset-0 flex items-center justify-center p-4 text-center">
                  <span className="rounded-xl bg-rose-600 px-3 py-2 text-xs font-bold text-white shadow-lg">
                    {t.clinicQrExpired}
                  </span>
                </div>
              )}
            </div>
          ) : null}

          <div className="mt-4 flex flex-wrap items-center justify-center gap-3">
            <span
              className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-semibold tabular-nums ${
                isExpired
                  ? 'border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-900/50 dark:bg-rose-950/40 dark:text-rose-300'
                  : 'border-[#DCE9EE] bg-[#EDF6F8] text-[#14283F] dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9]'
              }`}
            >
              <Clock className="h-3.5 w-3.5 text-[#0D9488] dark:text-[#2DD4BF]" />
              <span>{t.clinicQrExpiresIn}:</span>
              <span className="font-mono font-bold">
                {formatDurationHhMmSs(remainingSeconds)}
              </span>
            </span>

            <AppButton
              variant="secondary"
              size="sm"
              loading={isFetching}
              onClick={handleRefresh}
              icon={<RefreshCw className="h-3.5 w-3.5" />}
            >
              {t.clinicQrRefresh}
            </AppButton>
          </div>

          <div className="mt-4 flex items-start gap-2 rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-[11px] leading-relaxed text-[#64748B] dark:border-[#253F5B] dark:bg-[#0B1728]/70 dark:text-[#A5B4C7]">
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-[#0D9488] dark:text-[#2DD4BF]" />
            <span>{t.clinicQrSecurityNote}</span>
          </div>
        </div>
      </div>
    </div>
  );
};
