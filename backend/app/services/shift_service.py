from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.clinic import Clinic
from app.models.queue import ShiftStatus

DEFAULT_CLINIC_TIMEZONE = "Asia/Tashkent"
ACTIVE_SHIFT_STATUSES = (ShiftStatus.OPEN, ShiftStatus.CLOSING)


def get_clinic_zoneinfo(timezone_name: str | None) -> ZoneInfo:
    """Resolve a clinic's configured IANA timezone cleanly, falling back to Asia/Tashkent."""
    if timezone_name:
        try:
            return ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError:
            pass
    return ZoneInfo(DEFAULT_CLINIC_TIMEZONE)


def validate_timezone_name(timezone_name: str) -> str:
    """Validate an IANA timezone string, raising ValueError if invalid."""
    cleaned = timezone_name.strip()
    if not cleaned:
        raise ValueError("Timezone cannot be empty")
    try:
        ZoneInfo(cleaned)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"Unknown timezone: {cleaned}") from exc
    return cleaned


def get_clinic_local_now(clinic: Clinic | None, now_utc: datetime | None = None) -> datetime:
    """Return current clinic-local timezone-aware datetime."""
    utc_now = now_utc.astimezone(timezone.utc) if now_utc is not None else datetime.now(timezone.utc)
    tz = get_clinic_zoneinfo(clinic.timezone if clinic is not None else DEFAULT_CLINIC_TIMEZONE)
    return utc_now.astimezone(tz)


def get_clinic_local_date(clinic: Clinic | None, now_utc: datetime | None = None) -> date:
    """Return current calendar date in the clinic's local timezone."""
    return get_clinic_local_now(clinic, now_utc=now_utc).date()


def local_date_range_to_utc(
    date_from: date,
    date_to: date,
    tz_name: str | None,
) -> tuple[datetime, datetime]:
    """
    Convert inclusive clinic-local calendar dates [date_from, date_to] to UTC bounds
    [utc_start, utc_end_exclusive) preserving wall-clock midnight across DST changes.
    """
    tz = get_clinic_zoneinfo(tz_name)
    local_start = datetime(date_from.year, date_from.month, date_from.day, 0, 0, 0, tzinfo=tz)
    next_day = date_to + timedelta(days=1)
    local_end = datetime(next_day.year, next_day.month, next_day.day, 0, 0, 0, tzinfo=tz)
    return local_start.astimezone(timezone.utc), local_end.astimezone(timezone.utc)
