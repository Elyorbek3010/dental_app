import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { I18nProvider } from './i18n/I18nContext';
import { ProtectedRoute } from './components/auth/ProtectedRoute';
import { LoginPage } from './pages/LoginPage';
import { ReceptionApp } from './pages/ReceptionApp';
import { DashboardOverviewPage } from './pages/DashboardOverviewPage';
import { TodayQueuesPage } from './pages/TodayQueuesPage';
import { QueueManagementPage } from './pages/QueueManagementPage';
import { PublicDisplayPage } from './pages/PublicDisplayPage';

function App() {
  return (
    <I18nProvider>
      <AuthProvider>
        <BrowserRouter>
          <Routes>
            {/* Public TV display */}
            <Route path="/display/:clinicId" element={<PublicDisplayPage />} />

            {/* Reception Login */}
            <Route path="/login" element={<LoginPage />} />

            {/* Protected Reception Dashboard */}
            <Route
              path="/reception"
              element={
                <ProtectedRoute>
                  <ReceptionApp />
                </ProtectedRoute>
              }
            >
              <Route index element={<DashboardOverviewPage />} />
              <Route path="queues" element={<TodayQueuesPage />} />
              <Route path="manage" element={<QueueManagementPage />} />
            </Route>

            {/* Fallback route */}
            <Route path="*" element={<Navigate to="/reception" replace />} />
          </Routes>
        </BrowserRouter>
      </AuthProvider>
    </I18nProvider>
  );
}

export default App;
