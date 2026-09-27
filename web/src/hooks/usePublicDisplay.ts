/* oxlint-disable react/set-state-in-effect */
import { useCallback, useEffect, useRef, useState } from 'react';
import { fetchPublicDisplay } from '../api/display';
import type { PublicDisplayResponse } from '../types/display';
import { usePublicDisplayRealtime } from './usePublicDisplayRealtime';

const POLL_INTERVAL_MS = 10000;

export interface UsePublicDisplayResult {
  data: PublicDisplayResponse | null;
  loading: boolean;
  error: string | null;
  lastUpdated: Date | null;
  refetch: () => void;
}

export function usePublicDisplay(clinicId: string | undefined): UsePublicDisplayResult {
  const [data, setData] = useState<PublicDisplayResponse | null>(null);
  const [loading, setLoading] = useState<boolean>(Boolean(clinicId));
  const [error, setError] = useState<string | null>(clinicId ? null : 'Invalid clinic ID');
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

  const isMountedRef = useRef<boolean>(true);

  const performFetch = useCallback(async (isInitial: boolean) => {
    if (!clinicId) return;

    try {
      const result = await fetchPublicDisplay(clinicId);
      if (isMountedRef.current) {
        setData(result);
        setError(null);
        setLastUpdated(new Date());
      }
    } catch (err: unknown) {
      if (isMountedRef.current) {
        if (err instanceof Error && err.message === 'Clinic not found') {
          setError('Clinic not found');
        } else {
          setError('Unable to load queue information');
        }
      }
    } finally {
      if (isMountedRef.current && isInitial) {
        setLoading(false);
      }
    }
  }, [clinicId]);

  // Realtime WebSocket listener: triggers immediate HTTP refetch when display_updated event is received
  usePublicDisplayRealtime({
    clinicId,
    onDisplayUpdated: useCallback(() => {
      void performFetch(false);
    }, [performFetch]),
  });

  useEffect(() => {
    isMountedRef.current = true;

    if (clinicId) {
      // Async data fetching initiated on mount / clinicId change
      void performFetch(true);
    }

    const intervalId = window.setInterval(() => {
      if (clinicId) {
        void performFetch(false);
      }
    }, POLL_INTERVAL_MS);

    return () => {
      isMountedRef.current = false;
      window.clearInterval(intervalId);
    };
  }, [clinicId, performFetch]);

  const refetch = useCallback(() => {
    if (clinicId) {
      void performFetch(false);
    }
  }, [clinicId, performFetch]);

  return {
    data,
    loading,
    error,
    lastUpdated,
    refetch,
  };
}

export { usePublicDisplayRealtime };
