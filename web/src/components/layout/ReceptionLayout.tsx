import React, { useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  Activity,
  Globe,
  LayoutDashboard,
  LogOut,
  RefreshCw,
  Users,
} from 'lucide-react';
import { useAuth } from '../../context/useAuth';
import { useI18n } from '../../i18n/useI18n';
import type { Language } from '../../i18n/types';
import { ConfirmModal } from '../common/ConfirmModal';

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
  const { language, setLanguage, t } = useI18n();
  const navigate = useNavigate();
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showLangMenu, setShowLangMenu] = useState(false);

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  const navItems = [
    {
      to: '/reception',
      end: true,
      label: t.dashboard,
      icon: <LayoutDashboard className="h-5 w-5" />,
    },
    {
      to: '/reception/queues',
      label: t.todayQueues,
      icon: <Activity className="h-5 w-5" />,
    },
    {
      to: '/reception/manage',
      label: t.queueManagement,
      icon: <Users className="h-5 w-5" />,
    },
  ];

  const languages: { code: Language; label: string }[] = [
    { code: 'uz', label: "O'zbek (UZ)" },
    { code: 'ru', label: 'Русский (RU)' },
    { code: 'en', label: 'English (EN)' },
  ];

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-zinc-50 dark:bg-zinc-950 font-sans">
      {/* Sidebar */}
      <aside className="w-64 shrink-0 flex flex-col border-r border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900 shadow-xs">
        {/* Brand */}
        <div className="flex h-16 items-center gap-3 px-6 border-b border-zinc-100 dark:border-zinc-800/80">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-indigo-600 text-white shadow-xs shadow-indigo-500/20 font-bold text-lg">
            D
          </div>
          <div>
            <h1 className="text-sm font-bold text-zinc-900 dark:text-zinc-100 leading-tight">
              {t.appTitle}
            </h1>
            <p className="text-xs font-medium text-zinc-500 dark:text-zinc-400">
              {t.receptionPortal}
            </p>
          </div>
        </div>

        {/* Navigation Links */}
        <nav className="flex-1 space-y-1.5 p-4 overflow-y-auto">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-indigo-50 text-indigo-700 dark:bg-indigo-950/60 dark:text-indigo-300 font-semibold'
                    : 'text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-zinc-800/60 dark:hover:text-zinc-200'
                }`
              }
            >
              {item.icon}
              {item.label}
            </NavLink>
          ))}
        </nav>

        {/* Clinic & Logout Area */}
        <div className="border-t border-zinc-100 p-4 dark:border-zinc-800/80">
          <button
            onClick={() => setShowLogoutModal(true)}
            className="flex w-full items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium text-rose-600 hover:bg-rose-50 dark:text-rose-400 dark:hover:bg-rose-950/40 transition-colors"
          >
            <LogOut className="h-5 w-5" />
            {t.logout}
          </button>
        </div>
      </aside>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Top Header */}
        <header className="h-16 shrink-0 border-b border-zinc-200 bg-white/80 backdrop-blur-md px-6 flex items-center justify-between dark:border-zinc-800 dark:bg-zinc-900/80">
          {/* Left Context */}
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2">
              <span className="text-xs font-semibold uppercase tracking-wider text-zinc-400 dark:text-zinc-500">
                {t.clinicLabel}:
              </span>
              <span className="inline-flex items-center rounded-lg bg-zinc-100 px-2.5 py-1 text-xs font-bold text-zinc-800 dark:bg-zinc-800 dark:text-zinc-200">
                {user?.clinic_id ? `Clinic #${user.clinic_id}` : t.unassignedClinic}
              </span>
            </div>

            {/* Realtime WebSocket Badge */}
            <div className="flex items-center gap-1.5 pl-3 border-l border-zinc-200 dark:border-zinc-800">
              <span
                className={`h-2.5 w-2.5 rounded-full ${
                  isRealtimeConnected
                    ? 'bg-emerald-500 animate-pulse'
                    : 'bg-amber-400'
                }`}
              />
              <span className="text-xs font-medium text-zinc-500 dark:text-zinc-400">
                {isRealtimeConnected ? t.connected : t.reconnecting}
              </span>
            </div>
          </div>

          {/* Right Header Controls */}
          <div className="flex items-center gap-4">
            {/* Manual Refresh Button */}
            {onRefresh && (
              <button
                type="button"
                onClick={onRefresh}
                disabled={isRefreshing}
                title={t.refresh}
                className="flex items-center gap-1.5 rounded-xl border border-zinc-200 bg-white px-3 py-1.5 text-xs font-semibold text-zinc-700 shadow-2xs hover:bg-zinc-50 disabled:opacity-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200 dark:hover:bg-zinc-700/60"
              >
                <RefreshCw
                  className={`h-3.5 w-3.5 ${isRefreshing ? 'animate-spin text-indigo-600' : ''}`}
                />
                <span className="hidden sm:inline">{t.refresh}</span>
              </button>
            )}

            {/* Language Switcher Dropdown */}
            <div className="relative">
              <button
                type="button"
                onClick={() => setShowLangMenu(!showLangMenu)}
                className="flex items-center gap-2 rounded-xl border border-zinc-200 bg-white px-3 py-1.5 text-xs font-semibold text-zinc-700 shadow-2xs hover:bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-200"
              >
                <Globe className="h-3.5 w-3.5 text-zinc-500" />
                <span>{language.toUpperCase()}</span>
              </button>

              {showLangMenu && (
                <div className="absolute right-0 mt-2 w-36 rounded-xl border border-zinc-200 bg-white p-1.5 shadow-lg dark:border-zinc-700 dark:bg-zinc-800 z-50">
                  {languages.map((l) => (
                    <button
                      key={l.code}
                      onClick={() => {
                        setLanguage(l.code);
                        setShowLangMenu(false);
                      }}
                      className={`w-full text-left px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
                        language === l.code
                          ? 'bg-indigo-50 text-indigo-600 font-bold dark:bg-indigo-950/60 dark:text-indigo-400'
                          : 'text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-700'
                      }`}
                    >
                      {l.label}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* User Profile Pill */}
            <div className="flex items-center gap-2.5 pl-3 border-l border-zinc-200 dark:border-zinc-800">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-indigo-100 text-indigo-700 dark:bg-indigo-950/60 dark:text-indigo-300 font-bold text-xs">
                {user?.full_name ? user.full_name.charAt(0).toUpperCase() : 'U'}
              </div>
              <div className="hidden md:block text-left">
                <div className="text-xs font-bold text-zinc-800 dark:text-zinc-200 leading-tight">
                  {user?.full_name}
                </div>
                <div className="text-[10px] font-semibold text-indigo-600 dark:text-indigo-400">
                  {user?.role === 'ADMIN' ? t.roleAdmin : t.roleReceptionist}
                </div>
              </div>
            </div>
          </div>
        </header>

        {/* Page Outlet */}
        <main className="flex-1 overflow-y-auto p-6">
          <Outlet />
        </main>
      </div>

      {/* Logout Confirmation Modal */}
      <ConfirmModal
        isOpen={showLogoutModal}
        title={t.logoutConfirmTitle}
        message={t.logoutConfirmMessage}
        confirmLabel={t.logout}
        isDestructive={true}
        onConfirm={handleLogout}
        onCancel={() => setShowLogoutModal(false)}
      />
    </div>
  );
};
