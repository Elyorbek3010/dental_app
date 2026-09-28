import { useEffect, useRef, useState } from 'react';
import { getPublicDisplayWsUrl } from '../api/display';
import type { PublicDisplayWsMessage } from '../types/display';

export interface UseReceptionRealtimeOptions {
  clinicId: number | null | undefined;
  onUpdate: () => void;
  enabled?: boolean;
}

const INITIAL_RECONNECT_DELAY_MS = 1000;
const MAX_RECONNECT_DELAY_MS = 10000;

export function useReceptionRealtime({
  clinicId,
  onUpdate,
  enabled = true,
}: UseReceptionRealtimeOptions): { isConnected: boolean } {
  const [isConnected, setIsConnected] = useState(false);
  const onUpdateRef = useRef(onUpdate);

  useEffect(() => {
    onUpdateRef.current = onUpdate;
  });

  useEffect(() => {
    if (!enabled || !clinicId) {
      return;
    }

    if (typeof WebSocket === 'undefined') return;

    let isCancelled = false;
    let ws: WebSocket | null = null;
    let reconnectTimer: number | null = null;
    let retryDelay = INITIAL_RECONNECT_DELAY_MS;

    function cleanupSocket() {
      if (ws) {
        ws.onopen = null;
        ws.onmessage = null;
        ws.onerror = null;
        ws.onclose = null;
        if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
          ws.close();
        }
        ws = null;
      }
    }

    function clearTimer() {
      if (reconnectTimer !== null) {
        window.clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
    }

    function scheduleReconnect() {
      if (isCancelled) return;
      setIsConnected(false);
      clearTimer();

      const delay = retryDelay;
      retryDelay = Math.min(retryDelay * 2, MAX_RECONNECT_DELAY_MS);

      reconnectTimer = window.setTimeout(() => {
        if (!isCancelled) {
          connect();
        }
      }, delay);
    }

    function connect() {
      if (isCancelled) return;
      cleanupSocket();
      clearTimer();

      let wsUrl: string;
      try {
        wsUrl = getPublicDisplayWsUrl(clinicId!);
      } catch {
        scheduleReconnect();
        return;
      }

      try {
        ws = new WebSocket(wsUrl);
      } catch {
        scheduleReconnect();
        return;
      }

      ws.onopen = () => {
        if (isCancelled) return;
        setIsConnected(true);
        retryDelay = INITIAL_RECONNECT_DELAY_MS;
      };

      ws.onmessage = (event: MessageEvent) => {
        if (isCancelled) return;
        try {
          const payload = JSON.parse(event.data) as PublicDisplayWsMessage;
          if (
            payload &&
            typeof payload === 'object' &&
            payload.type === 'display_updated'
          ) {
            if (
              payload.clinic_id === undefined ||
              String(payload.clinic_id) === String(clinicId)
            ) {
              onUpdateRef.current();
            }
          }
        } catch {
          // ignore malformed payloads
        }
      };

      ws.onerror = () => {
        if (!isCancelled && ws && ws.readyState === WebSocket.CLOSED) {
          scheduleReconnect();
        }
      };

      ws.onclose = () => {
        if (isCancelled) return;
        setIsConnected(false);
        scheduleReconnect();
      };
    }

    connect();

    return () => {
      isCancelled = true;
      setIsConnected(false);
      clearTimer();
      cleanupSocket();
    };
  }, [clinicId, enabled]);

  return { isConnected };
}
