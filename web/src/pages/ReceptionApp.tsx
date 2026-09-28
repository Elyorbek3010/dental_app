import React, { useState } from 'react';
import { ReceptionLayout } from '../components/layout/ReceptionLayout';
import { useAuth } from '../context/useAuth';
import { useReceptionRealtime } from '../hooks/useReceptionRealtime';

export const ReceptionApp: React.FC = () => {
  const { user } = useAuth();
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRealtimeUpdate = () => {
    // Notify all active reception pages of an incoming realtime event
    window.dispatchEvent(new CustomEvent('reception:refresh'));
  };

  const { isConnected } = useReceptionRealtime({
    clinicId: user?.clinic_id,
    onUpdate: handleRealtimeUpdate,
    enabled: !!user?.clinic_id,
  });

  const handleManualRefresh = () => {
    setIsRefreshing(true);
    window.dispatchEvent(new CustomEvent('reception:refresh'));
    setTimeout(() => {
      setIsRefreshing(false);
    }, 600);
  };

  return (
    <ReceptionLayout
      isRealtimeConnected={isConnected}
      onRefresh={handleManualRefresh}
      isRefreshing={isRefreshing}
    />
  );
};
