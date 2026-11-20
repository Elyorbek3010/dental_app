import { useEffect, useState } from 'react';

interface UseSmartCallCountdownOptions {
  callDeadlineAt?: string | null;
  pausedRemainingSeconds?: number | null;
  serverTime?: string | null;
  fetchedAtMs?: number | null;
  isPaused?: boolean;
}

export function formatCountdownMmSs(seconds: number): string {
  const safeSeconds = Math.max(0, Math.floor(seconds));
  const mins = Math.floor(safeSeconds / 60);
  const secs = safeSeconds % 60;
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

export function useSmartCallCountdown({
  callDeadlineAt,
  pausedRemainingSeconds,
  serverTime,
  fetchedAtMs,
  isPaused = false,
}: UseSmartCallCountdownOptions): number | null {
  const [nowMs, setNowMs] = useState<number>(() => Date.now());

  useEffect(() => {
    if (!callDeadlineAt || isPaused) {
      return;
    }

    const intervalId = window.setInterval(() => {
      setNowMs(Date.now());
    }, 250);

    return () => {
      window.clearInterval(intervalId);
    };
  }, [callDeadlineAt, isPaused]);

  if (pausedRemainingSeconds !== undefined && pausedRemainingSeconds !== null) {
    return Math.max(0, Math.floor(pausedRemainingSeconds));
  }

  if (!callDeadlineAt) {
    return null;
  }

  const deadlineMs = Date.parse(callDeadlineAt);
  if (Number.isNaN(deadlineMs)) {
    return null;
  }

  let offsetMs = 0;
  if (serverTime && fetchedAtMs) {
    const serverMs = Date.parse(serverTime);
    if (!Number.isNaN(serverMs)) {
      offsetMs = serverMs - fetchedAtMs;
    }
  }

  const effectiveNowMs = fetchedAtMs ? Math.max(nowMs, fetchedAtMs) : nowMs;
  const remainingMs = deadlineMs - (effectiveNowMs + offsetMs);
  return Math.max(0, Math.ceil(remainingMs / 1000));
}
