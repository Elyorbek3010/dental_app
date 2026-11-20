import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { ThemeProvider } from './context/ThemeContext';
import { I18nProvider } from './i18n/I18nContext';
import { ProtectedRoute } from './components/auth/ProtectedRoute';
import { LoginPage } from './pages/LoginPage';
import { ReceptionApp } from './pages/ReceptionApp';
import { DashboardOverviewPage } from './pages/DashboardOverviewPage';
import { TodayQueuesPage } from './pages/TodayQueuesPage';
import { QueueManagementPage } from './pages/QueueManagementPage';
import { PublicDisplayPage } from './pages/PublicDisplayPage';

import { AdminLayout } from './components/layout/AdminLayout';
import { AdminOverviewPage } from './pages/admin/AdminOverviewPage';
import { AdminSpecializationsPage } from './pages/admin/AdminSpecializationsPage';
import { AdminDoctorsPage } from './pages/admin/AdminDoctorsPage';
import { AdminReceptionistsPage } from './pages/admin/AdminReceptionistsPage';
import { AdminAnalyticsPage } from './pages/admin/AdminAnalyticsPage';

function App() {
  return (
    <ThemeProvider>
      <I18nProvider>
        <AuthProvider>
        <BrowserRouter>
          <Routes>
            {/* Public TV display */}
            <Route path="/display/:clinicId" element={<PublicDisplayPage />} />

            {/* Reception / Staff Login */}
            <Route path="/login" element={<LoginPage />} />

            {/* Protected Reception Dashboard */}
            <Route
              path="/reception"
              element={
                <ProtectedRoute allowedRoles={['RECEPTIONIST', 'ADMIN']}>
                  <ReceptionApp />
                </ProtectedRoute>
              }
            >
              <Route index element={<DashboardOverviewPage />} />
              <Route path="queues" element={<TodayQueuesPage />} />
              <Route path="manage" element={<QueueManagementPage />} />
            </Route>

            {/* Protected Admin Dashboard */}
            <Route
              path="/admin"
              element={
                <ProtectedRoute allowedRoles={['ADMIN']}>
                  <AdminLayout />
                </ProtectedRoute>
              }
            >
              <Route index element={<AdminOverviewPage />} />
              <Route path="specializations" element={<AdminSpecializationsPage />} />
              <Route path="doctors" element={<AdminDoctorsPage />} />
              <Route path="receptionists" element={<AdminReceptionistsPage />} />
              <Route path="analytics" element={<AdminAnalyticsPage />} />
            </Route>

            {/* Fallback route */}
            <Route path="*" element={<Navigate to="/reception" replace />} />
          </Routes>
        </BrowserRouter>
      </AuthProvider>
    </I18nProvider>
    </ThemeProvider>
  );
}

export default App;
