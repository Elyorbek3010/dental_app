import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { PublicDisplayPage } from './pages/PublicDisplayPage';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/display/:clinicId" element={<PublicDisplayPage />} />
        {/* Default route redirects to clinic 1 display */}
        <Route path="*" element={<Navigate to="/display/1" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
