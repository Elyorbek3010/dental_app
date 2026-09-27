import { useEffect, useRef } from 'react';
import { getPublicDisplayWsUrl } from '../api/display';
import type { PublicDisplayWsMessage } from '../types/display';

export interface UsePublicDisplayRealtimeOptions {
  clinicId: string | undefined;
  onDisplayUpdated: () => void;
  enabled?: boolean;
}

const INITIAL_RECONNECT_DELAY_MS = 1000;
const MAX_RECONNECT_DELAY_MS = 10000;

export function usePublicDisplayRealtime({
  clinicId,
  onDisplayUpdated,
  enabled = true,
}: UsePublicDisplayRealtimeOptions): void {
  const onDisplayUpdatedRef = useRef(onDisplayUpdated);

  useEffect(() => {
    onDisplayUpdatedRef.current = onDisplayUpdated;
  });

  useEffect(() => {
    // If not enabled or no clinicId provided, do not connect
    if (!enabled || !clinicId) return;

    // Guard against non-browser environments
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
      clearTimer();

      const delay = retryDelay;
      // Exponential backoff capped at MAX_RECONNECT_DELAY_MS (1s -> 2s -> 4s -> 8s -> 10s)
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
        // Reset retry backoff on successful connection
        retryDelay = INITIAL_RECONNECT_DELAY_MS;
      };

      ws.onmessage = (event: MessageEvent) => {
        if (isCancelled) return;
        try {
          const payload = JSON.parse(event.data) as PublicDisplayWsMessage;
          // Validate event is display_updated and matches active clinic
          if (
            payload &&
            typeof payload === 'object' &&
            payload.type === 'display_updated'
          ) {
            if (
              payload.clinic_id === undefined ||
              String(payload.clinic_id) === String(clinicId)
            ) {
              onDisplayUpdatedRef.current();
            }
          }
          // "connected" handshake and any other events are safely ignored
        } catch {
          // Malformed messages are safely ignored without crashing
        }
      };

      ws.onerror = () => {
        if (!isCancelled && ws && ws.readyState === WebSocket.CLOSED) {
          scheduleReconnect();
        }
      };

      ws.onclose = () => {
        if (isCancelled) return;
        // Unexpected disconnect: trigger reconnect with bounded exponential backoff
        scheduleReconnect();
      };
    }

    connect();

    return () => {
      isCancelled = true;
      clearTimer();
      cleanupSocket();
    };
  }, [clinicId, enabled]);
}
