import React, { useCallback, useEffect, useRef, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  BarChart3,
  Building2,
  Globe,
  LayoutDashboard,
  LogOut,
  Stethoscope,
  UserCog,
  Users,
} from 'lucide-react';
import { useAuth } from '../../context/useAuth';
import { useI18n } from '../../i18n/useI18n';
import type { Language } from '../../i18n/types';
import { ConfirmModal } from '../common/ConfirmModal';
import { getAdminClinicApi, updateAdminClinicApi } from '../../api/admin';
import { useReceptionRealtime } from '../../hooks/useReceptionRealtime';
import type { AdminClinic } from '../../types/admin';

export const AdminLayout: React.FC = () => {
  const { user, logout } = useAuth();
  const { language, setLanguage, t } = useI18n();
  const navigate = useNavigate();

  const [clinic, setClinic] = useState<AdminClinic | null>(null);
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showLangMenu, setShowLangMenu] = useState(false);
  const [showClinicModal, setShowClinicModal] = useState(false);
  const [editClinicName, setEditClinicName] = useState('');
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
    setIsSavingClinic(true);
    setClinicError(null);
    try {
      const updated = await updateAdminClinicApi(editClinicName.trim());
      setClinic(updated);
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

  const navItems = [
    {
      to: '/admin',
      end: true,
      label: t.adminNavDashboard,
      icon: <LayoutDashboard className="h-5 w-5" />,
    },
    {
      to: '/admin/specializations',
      label: t.adminNavSpecializations,
      icon: <Stethoscope className="h-5 w-5" />,
    },
    {
      to: '/admin/doctors',
      label: t.adminNavDoctors,
      icon: <Users className="h-5 w-5" />,
    },
    {
      to: '/admin/receptionists',
      label: t.adminNavReceptionists,
      icon: <UserCog className="h-5 w-5" />,
    },
    {
      to: '/admin/analytics',
      label: t.adminNavAnalytics,
      icon: <BarChart3 className="h-5 w-5" />,
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
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-purple-600 text-white shadow-xs shadow-purple-500/20 font-bold text-lg">
            A
          </div>
          <div>
            <h1 className="text-sm font-bold text-zinc-900 dark:text-zinc-100 leading-tight">
              {clinic?.name || t.appTitle}
            </h1>
            <p className="text-xs font-medium text-purple-600 dark:text-purple-400">
              {t.adminPortal}
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
                    ? 'bg-purple-50 text-purple-700 dark:bg-purple-950/60 dark:text-purple-300 font-semibold'
                    : 'text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-400 dark:hover:bg-zinc-800/60 dark:hover:text-zinc-200'
                }`
              }
            >
              {item.icon}
              {item.label}
            </NavLink>
          ))}
        </nav>

        {/* Bottom User & Logout Area */}
        <div className="p-4 border-t border-zinc-100 dark:border-zinc-800/80 space-y-3">
          <div className="flex items-center gap-3 px-2 py-1">
            <div className="flex h-9 w-9 items-center justify-center rounded-full bg-purple-100 dark:bg-purple-950 text-purple-700 dark:text-purple-300 font-semibold text-xs shrink-0">
              {user?.full_name ? user.full_name.charAt(0).toUpperCase() : 'A'}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-xs font-semibold text-zinc-900 dark:text-zinc-100 truncate">
                {user?.full_name || 'Admin'}
              </p>
              <p className="text-2xs text-purple-600 dark:text-purple-400 font-medium">
                {t.roleAdmin}
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={() => setShowLogoutModal(true)}
            className="flex w-full items-center gap-2.5 px-3.5 py-2 rounded-xl text-xs font-medium text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950/40 transition-colors cursor-pointer"
          >
            <LogOut className="h-4 w-4" />
            {t.logout}
          </button>
        </div>
      </aside>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Top Header Bar */}
        <header className="h-16 shrink-0 flex items-center justify-between px-6 border-b border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900 shadow-2xs">
          {/* Clinic context pill */}
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={() => {
                setEditClinicName(clinic?.name || '');
                setShowClinicModal(true);
              }}
              className="flex items-center gap-2 px-3 py-1.5 rounded-xl border border-zinc-200 bg-zinc-50 dark:border-zinc-800 dark:bg-zinc-800/60 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors text-xs font-medium text-zinc-700 dark:text-zinc-300 cursor-pointer"
              title={t.adminEditClinic}
            >
              <Building2 className="h-3.5 w-3.5 text-purple-600 dark:text-purple-400" />
              <span>{clinic?.name || t.unassignedClinic}</span>
            </button>

            {/* Realtime WebSocket Badge */}
            <div className="flex items-center gap-1.5 pl-3 border-l border-zinc-200 dark:border-zinc-800">
              <span
                className={`h-2.5 w-2.5 rounded-full ${
                  isConnected ? 'bg-emerald-500 animate-pulse' : 'bg-amber-400'
                }`}
              />
              <span className="text-xs font-medium text-zinc-500 dark:text-zinc-400">
                {isConnected ? t.connected : t.reconnecting}
              </span>
            </div>
          </div>

          {/* Right Header Actions */}
          <div className="flex items-center gap-3">
            {/* Language Selector */}
            <div className="relative">
              <button
                type="button"
                onClick={() => setShowLangMenu(!showLangMenu)}
                className="flex items-center gap-2 px-3 py-1.5 rounded-xl border border-zinc-200 bg-zinc-50 hover:bg-zinc-100 dark:border-zinc-700 dark:bg-zinc-800 dark:hover:bg-zinc-700/80 text-xs font-semibold text-zinc-700 dark:text-zinc-200 transition-colors cursor-pointer"
              >
                <Globe className="h-3.5 w-3.5 text-zinc-500" />
                <span className="uppercase">{language}</span>
              </button>

              {showLangMenu && (
                <>
                  <div
                    className="fixed inset-0 z-40"
                    onClick={() => setShowLangMenu(false)}
                  />
                  <div className="absolute right-0 mt-1.5 w-36 rounded-xl border border-zinc-200 bg-white py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-800 z-50">
                    {languages.map((l) => (
                      <button
                        key={l.code}
                        type="button"
                        onClick={() => {
                          setLanguage(l.code);
                          setShowLangMenu(false);
                        }}
                        className={`flex w-full items-center px-3.5 py-1.5 text-xs font-medium transition-colors ${
                          language === l.code
                            ? 'bg-purple-50 text-purple-700 dark:bg-purple-950/60 dark:text-purple-300 font-semibold'
                            : 'text-zinc-600 hover:bg-zinc-50 dark:text-zinc-400 dark:hover:bg-zinc-700/50'
                        }`}
                      >
                        {l.label}
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>
          </div>
        </header>

        {/* Page Content */}
        <main className="flex-1 overflow-y-auto p-6 lg:p-8 bg-zinc-50 dark:bg-zinc-950">
          <Outlet />
        </main>
      </div>

      {/* Clinic Name Edit Modal */}
      {showClinicModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-2xl border border-zinc-200 bg-white p-6 shadow-xl dark:border-zinc-800 dark:bg-zinc-900">
            <h3 className="text-base font-bold text-zinc-900 dark:text-zinc-100">
              {t.adminEditClinic}
            </h3>
            <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
              {t.adminClinicSettings}
            </p>

            {clinicError && (
              <div className="mt-3 rounded-xl bg-red-50 p-2.5 text-xs text-red-600 dark:bg-red-950/40 dark:text-red-400">
                {clinicError}
              </div>
            )}

            <form onSubmit={handleSaveClinic} className="mt-4 space-y-4">
              <div>
                <label className="block text-xs font-semibold text-zinc-700 dark:text-zinc-300">
                  {t.adminClinicName}
                </label>
                <input
                  type="text"
                  required
                  value={editClinicName}
                  onChange={(e) => setEditClinicName(e.target.value)}
                  className="mt-1 block w-full rounded-xl border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 shadow-2xs focus:border-purple-500 focus:outline-hidden dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-100"
                />
              </div>

              <div className="flex justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowClinicModal(false)}
                  disabled={isSavingClinic}
                  className="rounded-xl px-4 py-2 text-xs font-semibold text-zinc-700 hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800"
                >
                  {t.cancel}
                </button>
                <button
                  type="submit"
                  disabled={isSavingClinic || !editClinicName.trim()}
                  className="rounded-xl bg-purple-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-purple-700 disabled:opacity-50"
                >
                  {isSavingClinic ? t.adminSaving : t.adminSave}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Logout Confirmation Modal */}
      <ConfirmModal
        isOpen={showLogoutModal}
        title={t.logoutConfirmTitle}
        message={t.logoutConfirmMessage}
        confirmLabel={t.logout}
        cancelLabel={t.cancel}
        isDestructive={true}
        onConfirm={handleLogout}
        onCancel={() => setShowLogoutModal(false)}
      />
    </div>
  );
};
