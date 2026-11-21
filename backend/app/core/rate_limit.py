"""
Lightweight in-memory sliding-window rate limiter with safe reverse-proxy IP extraction.

Single-process limitation:
State is held per-process in memory. Multiple backend workers or instance restarts reset
the counters and do not share limits across workers. For single-worker Render staging/WebSocket
deployments, this avoids external Redis infrastructure while remaining deterministic and fast.
"""
from collections import defaultdict, deque
from collections.abc import Callable
import ipaddress
import math
import threading
import time

from fastapi import HTTPException, Request, status

from app.core.config import settings


def get_client_ip(request: Request, trusted_proxy_hops: int | None = None) -> str:
    """
    Extracts the client IP address safely without trusting arbitrary spoofed headers.

    When trusted_proxy_hops == 0 (direct connection / local dev), X-Forwarded-For is ignored
    and request.client.host is returned.
    When trusted_proxy_hops >= 1 (e.g. Render edge proxy in front of FastAPI), the IP is selected
    from right to left across X-Forwarded-For by stepping back `trusted_proxy_hops` hops so a
    client-injected leftmost IP cannot bypass rate limits.
    """
    direct_host = request.client.host if request.client and request.client.host else "unknown"
    hops = settings.TRUSTED_PROXY_HOPS if trusted_proxy_hops is None else trusted_proxy_hops
    if hops <= 0:
        return direct_host

    xff_header = request.headers.get("x-forwarded-for", "")
    if not xff_header:
        return direct_host

    candidates = [part.strip() for part in xff_header.split(",") if part.strip()]
    if len(candidates) < hops:
        return direct_host

    selected = candidates[-hops]
    try:
        return str(ipaddress.ip_address(selected))
    except ValueError:
        return direct_host


class SlidingWindowRateLimiter:
    """Thread-safe in-memory sliding-window rate limiter."""

    def __init__(self, time_func: Callable[[], float] | None = None) -> None:
        self._time_func = time_func or time.monotonic
        self._lock = threading.Lock()
        self._buckets: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str, max_requests: int, window_seconds: int) -> tuple[bool, int]:
        """
        Records a request for `key` if allowed and returns (allowed, retry_after_seconds).
        """
        now = self._time_func()
        cutoff = now - window_seconds

        with self._lock:
            timestamps = self._buckets[key]
            while timestamps and timestamps[0] <= cutoff:
                timestamps.popleft()

            if len(timestamps) >= max_requests:
                retry_after = max(1, int(math.ceil(timestamps[0] + window_seconds - now)))
                return False, retry_after

            timestamps.append(now)
            return True, 0

    def reset(self) -> None:
        """Clears all tracked rate-limit buckets (used between automated tests)."""
        with self._lock:
            self._buckets.clear()


rate_limiter = SlidingWindowRateLimiter()


def make_rate_limit_dependency(
    bucket_name: str,
    max_requests: int,
    window_seconds: int,
    limiter: SlidingWindowRateLimiter | None = None,
) -> Callable[[Request], None]:
    """Builds a FastAPI dependency enforcing `max_requests` per `window_seconds` per client IP."""
    active_limiter = limiter or rate_limiter

    def _rate_limit_dependency(request: Request) -> None:
        if not settings.RATE_LIMIT_ENABLED:
            return

        client_ip = get_client_ip(request)
        bucket_key = f"{bucket_name}:{client_ip}"
        allowed, retry_after = active_limiter.check(
            key=bucket_key,
            max_requests=max_requests,
            window_seconds=window_seconds,
        )
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
                headers={"Retry-After": str(retry_after)},
            )

    return _rate_limit_dependency


limit_login = make_rate_limit_dependency("auth_login", max_requests=15, window_seconds=60)
limit_register = make_rate_limit_dependency("auth_register", max_requests=10, window_seconds=60)
limit_refresh = make_rate_limit_dependency("auth_refresh", max_requests=30, window_seconds=60)
limit_public_display = make_rate_limit_dependency("public_display", max_requests=120, window_seconds=60)
limit_health_db = make_rate_limit_dependency("health_db", max_requests=60, window_seconds=60)
