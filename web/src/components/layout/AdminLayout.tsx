import React, { useCallback, useEffect, useRef, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  BarChart3,
  Building2,
  LayoutDashboard,
  LogOut,
  Menu,
  QrCode,
  Settings2,
  Stethoscope,
  UserCog,
  Users,
  X,
} from 'lucide-react';
import { useAuth } from '../../context/useAuth';
import { useI18n } from '../../i18n/useI18n';
import { ClinicQrModal } from '../common/ClinicQrModal';
import { ConfirmModal } from '../common/ConfirmModal';
import { DentalLogo } from '../common/DentalLogo';
import { LanguageSwitcher } from '../common/LanguageSwitcher';
import { ThemeToggle } from '../common/ThemeToggle';
import { getAdminClinicApi, updateAdminClinicApi } from '../../api/admin';
import { useReceptionRealtime } from '../../hooks/useReceptionRealtime';
import type { AdminClinic } from '../../types/admin';

export const AdminLayout: React.FC = () => {
  const { user, logout } = useAuth();
  const { t } = useI18n();
  const navigate = useNavigate();

  const [clinic, setClinic] = useState<AdminClinic | null>(null);
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showClinicModal, setShowClinicModal] = useState(false);
  const [showQrModal, setShowQrModal] = useState(false);
  const [isMobileNavOpen, setIsMobileNavOpen] = useState(false);
  const [editClinicName, setEditClinicName] = useState('');
  const [editTimeoutSeconds, setEditTimeoutSeconds] = useState('120');
  const [isSavingClinic, setIsSavingClinic] = useState(false);
  const [clinicError, setClinicError] = useState<string | null>(null);

  const clinicId = clinic?.id ?? user?.clinic_id;
  const hasConnectedOnceRef = useRef(false);
  const wasDisconnectedRef = useRef(false);

  const handleRealtimeUpdate = useCallback(() => {
    window.dispatchEvent(new CustomEvent('admin:refresh'));
  }, []);

  const { isConnected } = useReceptionRealtime({
    clinicId,
    onUpdate: handleRealtimeUpdate,
    enabled: !!clinicId,
  });

  useEffect(() => {
    hasConnectedOnceRef.current = false;
    wasDisconnectedRef.current = false;
  }, [clinicId]);

  useEffect(() => {
    if (isConnected) {
      if (hasConnectedOnceRef.current && wasDisconnectedRef.current) {
        window.dispatchEvent(new CustomEvent('admin:refresh'));
      }
      hasConnectedOnceRef.current = true;
      wasDisconnectedRef.current = false;
    } else if (hasConnectedOnceRef.current) {
      wasDisconnectedRef.current = true;
    }
  }, [isConnected]);

  useEffect(() => {
    getAdminClinicApi()
      .then((data) => {
        setClinic(data);
        setEditClinicName(data.name);
        setEditTimeoutSeconds(String(data.smart_call_timeout_seconds ?? 120));
      })
      .catch(() => {
        // Fallback if clinic not assigned yet
      });
  }, []);

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const handleSaveClinic = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editClinicName.trim()) return;
    const parsedTimeout = Number(editTimeoutSeconds);
    if (
      !Number.isInteger(parsedTimeout) ||
      parsedTimeout < 15 ||
      parsedTimeout > 1800
    ) {
      setClinicError(t.adminSmartCallTimeoutInvalid);
      return;
    }
    setIsSavingClinic(true);
    setClinicError(null);
    try {
      const updated = await updateAdminClinicApi(editClinicName.trim(), parsedTimeout);
      setClinic(updated);
      setEditTimeoutSeconds(String(updated.smart_call_timeout_seconds));
      setShowClinicModal(false);
    } catch (err: unknown) {
      if (err instanceof Error) {
        setClinicError(err.message);
      } else {
        setClinicError(t.errorGeneric);
      }
    } finally {
      setIsSavingClinic(false);
    }
  };

  const openClinicSettingsModal = () => {
    setEditClinicName(clinic?.name || '');
    setEditTimeoutSeconds(String(clinic?.smart_call_timeout_seconds ?? 120));
    setClinicError(null);
    setShowClinicModal(true);
  };

  const navItems = [
    {
      to: '/admin',
      end: true,
      label: t.adminNavDashboard,
      icon: <LayoutDashboard className="h-4.5 w-4.5" />,
    },
    {
      to: '/admin/specializations',
      label: t.adminNavSpecializations,
      icon: <Stethoscope className="h-4.5 w-4.5" />,
    },
    {
      to: '/admin/doctors',
      label: t.adminNavDoctors,
      icon: <Users className="h-4.5 w-4.5" />,
    },
    {
      to: '/admin/receptionists',
      label: t.adminNavReceptionists,
      icon: <UserCog className="h-4.5 w-4.5" />,
    },
    {
      to: '/admin/analytics',
      label: t.adminNavAnalytics,
      icon: <BarChart3 className="h-4.5 w-4.5" />,
    },
  ];

  const renderSidebarContent = (onNavClick?: () => void) => (
    <>
      <div className="flex h-16 items-center justify-between gap-3 px-5 border-b border-[#DCE9EE] dark:border-[#253F5B]">
        <div className="flex items-center gap-3 min-w-0">
          <DentalLogo size="md" />
          <div className="min-w-0">
            <h1 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9] truncate leading-tight">
              {clinic?.name || t.appTitle}
            </h1>
            <p className="text-[11px] font-semibold text-[#0284C7] dark:text-[#38BDF8] truncate">
              {t.adminPortal}
            </p>
          </div>
        </div>
        {onNavClick && (
          <button
            type="button"
            onClick={onNavClick}
            className="lg:hidden rounded-lg p-1.5 text-[#64748B] hover:bg-[#EDF6F8] dark:text-[#A5B4C7] dark:hover:bg-[#1A3047]"
          >
            <X className="h-5 w-5" />
          </button>
        )}
      </div>

      <nav className="flex-1 space-y-1.5 p-3.5 overflow-y-auto">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            onClick={onNavClick}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm transition-all ${
                isActive
                  ? 'bg-[#0D9488] text-white font-semibold shadow-xs dark:bg-[#14B8A6] dark:text-[#07131D]'
                  : 'font-medium text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:bg-[#1A3047] dark:hover:text-[#F1F5F9]'
              }`
            }
          >
            {item.icon}
            <span>{item.label}</span>
          </NavLink>
        ))}

        <div className="pt-3 mt-3 border-t border-[#DCE9EE] dark:border-[#253F5B] space-y-1.5">
          <button
            type="button"
            onClick={() => {
              onNavClick?.();
              openClinicSettingsModal();
            }}
            className="flex w-full items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium text-[#64748B] hover:bg-[#EDF6F8] hover:text-[#14283F] dark:text-[#A5B4C7] dark:hover:bg-[#1A3047] dark:hover:text-[#F1F5F9] transition-colors cursor-pointer"
          >
            <Settings2 className="h-4.5 w-4.5" />
            <span>{t.adminClinicSettings}</span>
          </button>

          {clinicId && (
            <button
              type="button"
              onClick={() => {
                onNavClick?.();
                setShowQrModal(true);
              }}
              className="flex w-full items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-semibold text-[#0284C7] bg-[#E0F2FE]/70 hover:bg-[#E0F2FE] dark:text-[#38BDF8] dark:bg-[#10324F]/70 dark:hover:bg-[#10324F] transition-colors cursor-pointer"
            >
              <QrCode className="h-4.5 w-4.5" />
              <span>{t.showClinicQr}</span>
            </button>
          )}
        </div>
      </nav>

      <div className="p-3.5 border-t border-[#DCE9EE] dark:border-[#253F5B] space-y-2.5">
        <div className="flex items-center gap-2.5 rounded-xl bg-[#F5FAFB] px-3 py-2 dark:bg-[#0B1728]/60">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#E0F2FE] text-[#0369A1] dark:bg-[#10324F] dark:text-[#38BDF8] font-bold text-xs">
            {user?.full_name ? user.full_name.charAt(0).toUpperCase() : 'A'}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs font-bold text-[#14283F] dark:text-[#F1F5F9] truncate">
              {user?.full_name || 'Admin'}
            </p>
            <p className="text-[11px] font-medium text-[#0284C7] dark:text-[#38BDF8] truncate">
              {t.roleAdmin}
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={() => setShowLogoutModal(true)}
          className="flex w-full items-center gap-2.5 px-3.5 py-2 rounded-xl text-xs font-semibold text-rose-600 hover:bg-rose-50 dark:text-rose-400 dark:hover:bg-rose-950/40 transition-colors cursor-pointer"
        >
          <LogOut className="h-4 w-4" />
          {t.logout}
        </button>
      </div>
    </>
  );

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-[#F5FAFB] dark:bg-[#0B1728]">
      {/* Desktop Sidebar */}
      <aside className="hidden lg:flex w-64 shrink-0 flex-col border-r border-[#DCE9EE] bg-white dark:border-[#253F5B] dark:bg-[#12243A]">
        {renderSidebarContent()}
      </aside>

      {/* Mobile Drawer */}
      {isMobileNavOpen && (
        <div className="fixed inset-0 z-50 flex lg:hidden">
          <div
            className="fixed inset-0 bg-[#0B1728]/60 backdrop-blur-xs"
            onClick={() => setIsMobileNavOpen(false)}
          />
          <aside className="relative z-10 flex w-72 max-w-[85vw] flex-col bg-white dark:bg-[#12243A] border-r border-[#DCE9EE] dark:border-[#253F5B] shadow-2xl">
            {renderSidebarContent(() => setIsMobileNavOpen(false))}
          </aside>
        </div>
      )}

      {/* Main Content */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <header className="relative z-30 h-16 shrink-0 flex items-center justify-between gap-3 px-4 sm:px-6 border-b border-[#DCE9EE] bg-white/90 backdrop-blur-md dark:border-[#253F5B] dark:bg-[#12243A]/90">
          <div className="flex items-center gap-3 min-w-0">
            <button
              type="button"
              onClick={() => setIsMobileNavOpen(true)}
              aria-label="Open navigation"
              className="lg:hidden rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] p-2 text-[#14283F] dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9]"
            >
              <Menu className="h-4 w-4" />
            </button>

            <button
              type="button"
              onClick={openClinicSettingsModal}
              className="flex items-center gap-2 px-3 py-1.5 rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] hover:bg-[#EDF6F8] dark:border-[#253F5B] dark:bg-[#1A3047] dark:hover:bg-[#223C58] transition-colors text-xs font-semibold text-[#14283F] dark:text-[#F1F5F9] cursor-pointer truncate"
              title={t.adminEditClinic}
            >
              <Building2 className="h-3.5 w-3.5 text-[#0D9488] dark:text-[#2DD4BF] shrink-0" />
              <span className="truncate">{clinic?.name || t.unassignedClinic}</span>
            </button>

            <div className="flex items-center gap-1.5 pl-3 border-l border-[#DCE9EE] dark:border-[#253F5B]">
              <span
                className={`h-2.5 w-2.5 rounded-full ${
                  isConnected ? 'bg-emerald-500 animate-pulse' : 'bg-amber-400'
                }`}
              />
              <span className="text-xs font-semibold text-[#64748B] dark:text-[#A5B4C7] hidden sm:inline">
                {isConnected ? t.connected : t.reconnecting}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 sm:gap-3">
            <ThemeToggle compact />

            {/* Language Selector */}
            <LanguageSwitcher />
          </div>
        </header>

        <main className="flex-1 overflow-y-auto p-3.5 sm:p-4 lg:p-5">
          <Outlet />
        </main>
      </div>

      {/* Clinic Settings Modal */}
      {showClinicModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-[#0B1728]/65 backdrop-blur-xs">
          <div className="w-full max-w-md max-h-[90vh] overflow-y-auto rounded-2xl border border-[#DCE9EE] bg-white p-6 shadow-2xl dark:border-[#253F5B] dark:bg-[#1A3047]">
            <h3 className="text-base font-bold text-[#14283F] dark:text-[#F1F5F9]">
              {t.adminEditClinic}
            </h3>
            <p className="mt-1 text-xs text-[#64748B] dark:text-[#A5B4C7]">
              {t.adminClinicSettings}
            </p>

            {clinicError && (
              <div className="mt-3 rounded-xl bg-rose-50 p-2.5 text-xs text-rose-700 dark:bg-rose-950/40 dark:text-rose-300">
                {clinicError}
              </div>
            )}

            <form onSubmit={handleSaveClinic} className="mt-4 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.adminClinicName}
                </label>
                <input
                  type="text"
                  value={editClinicName}
                  onChange={(e) => setEditClinicName(e.target.value)}
                  className="mt-1.5 w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-sm text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[#14283F] dark:text-[#F1F5F9]">
                  {t.adminSmartCallTimeoutLabel}
                </label>
                <input
                  type="number"
                  min={15}
                  max={1800}
                  step={1}
                  value={editTimeoutSeconds}
                  onChange={(e) => setEditTimeoutSeconds(e.target.value)}
                  className="mt-1.5 w-full rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] px-3.5 py-2.5 text-sm text-[#14283F] placeholder-[#64748B]/75 focus:border-[#0D9488] focus:bg-white focus:outline-hidden focus:ring-2 focus:ring-[#0D9488]/20 dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] dark:placeholder-[#A5B4C7]/70 dark:focus:border-[#2DD4BF] dark:focus:bg-[#0B1728]"
                  required
                />
                <p className="mt-1.5 text-[11px] text-[#64748B] dark:text-[#A5B4C7]">
                  {t.adminSmartCallTimeoutHelp}
                </p>
              </div>

              <div className="flex justify-end gap-2.5 pt-2">
                <button
                  type="button"
                  onClick={() => setShowClinicModal(false)}
                  className="rounded-xl border border-[#DCE9EE] bg-white px-4 py-2 text-xs font-semibold text-[#14283F] hover:bg-[#EDF6F8] dark:border-[#253F5B] dark:bg-[#12243A] dark:text-[#F1F5F9] cursor-pointer"
                >
                  {t.cancel}
                </button>
                <button
                  type="submit"
                  disabled={isSavingClinic}
                  className="rounded-xl bg-[#0D9488] px-4 py-2 text-xs font-semibold text-white hover:bg-[#0F766E] disabled:opacity-50 dark:bg-[#14B8A6] dark:text-[#07131D] dark:hover:bg-[#2DD4BF] cursor-pointer"
                >
                  {isSavingClinic ? t.adminSaving : t.adminSave}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <ConfirmModal
        isOpen={showLogoutModal}
        title={t.logoutConfirmTitle}
        message={t.logoutConfirmMessage}
        confirmLabel={t.logout}
        isDestructive={true}
        onConfirm={handleLogout}
        onCancel={() => setShowLogoutModal(false)}
      />

      <ClinicQrModal
        isOpen={showQrModal}
        clinicId={clinicId ?? undefined}
        isAdminRole={true}
        onClose={() => setShowQrModal(false)}
      />
    </div>
  );
};
