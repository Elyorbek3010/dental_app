import React, { useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  Activity,
  LayoutDashboard,
  LogOut,
  Menu,
  QrCode,
  RefreshCw,
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

interface ReceptionLayoutProps {
  isRealtimeConnected?: boolean;
  onRefresh?: () => void;
  isRefreshing?: boolean;
}

export const ReceptionLayout: React.FC<ReceptionLayoutProps> = ({
  isRealtimeConnected = false,
  onRefresh,
  isRefreshing = false,
}) => {
  const { user, logout } = useAuth();
  const { t } = useI18n();
  const navigate = useNavigate();

  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showQrModal, setShowQrModal] = useState(false);
  const [isMobileNavOpen, setIsMobileNavOpen] = useState(false);

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const navItems = [
    {
      to: '/reception',
      end: true,
      label: t.dashboard,
      icon: <LayoutDashboard className="h-4.5 w-4.5" />,
    },
    {
      to: '/reception/queues',
      label: t.todayQueues,
      icon: <Activity className="h-4.5 w-4.5" />,
    },
    {
      to: '/reception/manage',
      label: t.queueManagement,
      icon: <Users className="h-4.5 w-4.5" />,
    },
  ];

  const renderSidebarContent = (onNavClick?: () => void) => (
    <>
      <div className="flex h-16 items-center justify-between gap-3 px-5 border-b border-[#DCE9EE] dark:border-[#253F5B]">
        <div className="flex items-center gap-3 min-w-0">
          <DentalLogo size="md" />
          <div className="min-w-0">
            <h1 className="text-sm font-bold text-[#14283F] dark:text-[#F1F5F9] truncate leading-tight">
              {t.appTitle}
            </h1>
            <p className="text-[11px] font-semibold text-[#0F766E] dark:text-[#2DD4BF] truncate">
              {t.receptionPortal}
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

        {user?.clinic_id && (
          <div className="pt-3 mt-3 border-t border-[#DCE9EE] dark:border-[#253F5B]">
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
          </div>
        )}
      </nav>

      <div className="border-t border-[#DCE9EE] p-3.5 dark:border-[#253F5B] space-y-2.5">
        <div className="flex items-center gap-2.5 rounded-xl bg-[#F5FAFB] px-3 py-2 dark:bg-[#0B1728]/60">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#DDF7F0] text-[#0F766E] dark:bg-[#12353D] dark:text-[#2DD4BF] font-bold text-xs">
            {user?.full_name ? user.full_name.charAt(0).toUpperCase() : 'R'}
          </div>
          <div className="min-w-0 flex-1">
            <div className="text-xs font-bold text-[#14283F] dark:text-[#F1F5F9] truncate">
              {user?.full_name}
            </div>
            <div className="text-[11px] font-medium text-[#0F766E] dark:text-[#2DD4BF] truncate">
              {user?.role === 'ADMIN' ? t.roleAdmin : t.roleReceptionist}
            </div>
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
        <header className="relative z-30 h-16 shrink-0 border-b border-[#DCE9EE] bg-white/90 backdrop-blur-md px-4 sm:px-6 flex items-center justify-between gap-3 dark:border-[#253F5B] dark:bg-[#12243A]/90">
          <div className="flex items-center gap-3 min-w-0">
            <button
              type="button"
              onClick={() => setIsMobileNavOpen(true)}
              aria-label="Open navigation"
              className="lg:hidden rounded-xl border border-[#DCE9EE] bg-[#F5FAFB] p-2 text-[#14283F] dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9]"
            >
              <Menu className="h-4 w-4" />
            </button>

            <div className="hidden sm:flex items-center gap-2">
              <span className="text-[11px] font-semibold uppercase tracking-wider text-[#64748B] dark:text-[#A5B4C7]">
                {t.clinicLabel}:
              </span>
              <span className="inline-flex items-center rounded-lg bg-[#EDF6F8] px-2.5 py-1 text-xs font-bold text-[#14283F] dark:bg-[#1A3047] dark:text-[#F1F5F9]">
                {user?.clinic_id ? `#${user.clinic_id}` : t.unassignedClinic}
              </span>
            </div>

            <div className="flex items-center gap-1.5 sm:pl-3 sm:border-l sm:border-[#DCE9EE] dark:sm:border-[#253F5B]">
              <span
                title={isRealtimeConnected ? t.connected : t.reconnecting}
                className={`h-2.5 w-2.5 shrink-0 rounded-full ${
                  isRealtimeConnected
                    ? 'bg-emerald-500 animate-pulse'
                    : 'bg-amber-400'
                }`}
              />
              <span className="hidden sm:inline text-xs font-semibold text-[#64748B] dark:text-[#A5B4C7] truncate">
                {isRealtimeConnected ? t.connected : t.reconnecting}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-1.5 sm:gap-2.5 shrink-0">
            {user?.clinic_id && (
              <button
                type="button"
                onClick={() => setShowQrModal(true)}
                className="inline-flex items-center gap-1.5 rounded-xl border border-[#0284C7]/25 bg-[#E0F2FE]/70 px-3 py-1.5 text-xs font-semibold text-[#0369A1] hover:bg-[#E0F2FE] dark:border-[#38BDF8]/30 dark:bg-[#10324F] dark:text-[#38BDF8] transition-colors cursor-pointer"
              >
                <QrCode className="h-3.5 w-3.5" />
                <span className="hidden md:inline">{t.showClinicQr}</span>
              </button>
            )}

            {onRefresh && (
              <button
                type="button"
                onClick={onRefresh}
                disabled={isRefreshing}
                title={t.refresh}
                className="inline-flex items-center gap-1.5 rounded-xl border border-[#DCE9EE] bg-white px-2.5 sm:px-3 py-1.5 text-xs font-semibold text-[#14283F] shadow-2xs hover:bg-[#EDF6F8] disabled:opacity-50 dark:border-[#253F5B] dark:bg-[#1A3047] dark:text-[#F1F5F9] dark:hover:bg-[#223C58] cursor-pointer"
              >
                <RefreshCw
                  className={`h-3.5 w-3.5 ${isRefreshing ? 'animate-spin text-[#0D9488] dark:text-[#2DD4BF]' : ''}`}
                />
                <span className="hidden sm:inline">{t.refresh}</span>
              </button>
            )}

            <ThemeToggle compact />

            {/* Language Switcher */}
            <LanguageSwitcher />
          </div>
        </header>

        <main className="flex-1 overflow-y-auto p-3.5 sm:p-4 lg:p-4">
          <Outlet />
        </main>
      </div>

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
        clinicId={user?.clinic_id ?? undefined}
        isAdminRole={user?.role === 'ADMIN'}
        onClose={() => setShowQrModal(false)}
      />
    </div>
  );
};
