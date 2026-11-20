from __future__ import annotations

import asyncio
import logging
import math
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

from app.db import session as db_session
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue, SmartCallMode
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.realtime import notify_display_update
from app.services.queue_notifications import (
    check_and_trigger_approaching,
    trigger_called_notification,
    trigger_missed_turn_notification,
    trigger_skipped_notification,
)

logger = logging.getLogger("app.services.smart_call_timer")

DEFAULT_SMART_CALL_TIMEOUT_SECONDS = 120
SWEEP_INTERVAL_SECONDS = 1.0


@dataclass
class SmartCallAdvanceResult:
    called_ticket: QueueTicket | None = None
    passed_ticket_ids: list[int] = field(default_factory=list)
    repositioned_any: bool = False


@dataclass
class SmartCallSweepEvent:
    clinic_id: int
    queue_id: int
    room_number: str | None = None
    skipped_ticket_ids: list[int] = field(default_factory=list)
    passed_ticket_ids: list[int] = field(default_factory=list)
    called_ticket_id: int | None = None
    repositioned_any: bool = False


def _as_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def get_clinic_timeout_seconds(db: Session, clinic_id: int) -> int:
    timeout = db.scalar(
        select(Clinic.smart_call_timeout_seconds).where(Clinic.id == clinic_id)
    )
    if timeout is None:
        return DEFAULT_SMART_CALL_TIMEOUT_SECONDS
    return int(timeout)


def start_ticket_call_countdown(
    ticket: QueueTicket,
    timeout_seconds: int,
    now: datetime | None = None,
) -> None:
    current_now = _as_utc(now) if now is not None else datetime.now(timezone.utc)
    ticket.status = TicketStatus.CALLED
    ticket.called_at = current_now
    ticket.call_deadline_at = current_now + timedelta(seconds=timeout_seconds)
    ticket.paused_remaining_seconds = None


def clear_ticket_call_countdown(ticket: QueueTicket) -> None:
    ticket.call_deadline_at = None
    ticket.paused_remaining_seconds = None


def freeze_ticket_call_countdown(
    ticket: QueueTicket,
    now: datetime | None = None,
) -> None:
    if ticket.call_deadline_at is None:
        return
    current_now = _as_utc(now) if now is not None else datetime.now(timezone.utc)
    deadline_utc = _as_utc(ticket.call_deadline_at)
    remaining = max(0, int(math.ceil((deadline_utc - current_now).total_seconds())))
    ticket.paused_remaining_seconds = remaining
    ticket.call_deadline_at = None


def resume_ticket_call_countdown(
    ticket: QueueTicket,
    now: datetime | None = None,
) -> None:
    if ticket.paused_remaining_seconds is None:
        return
    current_now = _as_utc(now) if now is not None else datetime.now(timezone.utc)
    ticket.call_deadline_at = current_now + timedelta(seconds=ticket.paused_remaining_seconds)
    ticket.paused_remaining_seconds = None


def advance_smart_call_for_queue(
    db: Session,
    queue_id: int,
    timeout_seconds: int,
    now: datetime | None = None,
) -> SmartCallAdvanceResult:
    """
    Single-pass Smart Call ticket selection for an already-locked, active, non-paused queue
    that has no existing CALLED or SERVING ticket.
    """
    waiting_tickets = list(
        db.scalars(
            select(QueueTicket)
            .where(
                QueueTicket.queue_id == queue_id,
                QueueTicket.status == TicketStatus.WAITING,
            )
            .order_by(QueueTicket.queue_position.asc())
        ).all()
    )

    if not waiting_tickets:
        return SmartCallAdvanceResult()

    current_max_pos = db.scalar(
        select(func.coalesce(func.max(QueueTicket.queue_position), 0)).where(
            QueueTicket.queue_id == queue_id
        )
    ) or 0

    result = SmartCallAdvanceResult()
    current_now = _as_utc(now) if now is not None else datetime.now(timezone.utc)

    for ticket in waiting_tickets:
        if ticket.checked_in_at is None:
            current_max_pos += 1
            ticket.missed_turns += 1
            ticket.queue_position = current_max_pos
            result.repositioned_any = True
            if ticket.patient_id is not None:
                result.passed_ticket_ids.append(ticket.id)
        else:
            start_ticket_call_countdown(ticket, timeout_seconds, now=current_now)
            result.called_ticket = ticket
            break

    return result


def dispatch_sweep_notifications(event: SmartCallSweepEvent) -> None:
    """Send post-commit push notifications and approaching checks for an expired queue sweep."""
    for skipped_id in event.skipped_ticket_ids:
        trigger_skipped_notification(skipped_id)
    for passed_id in event.passed_ticket_ids:
        trigger_missed_turn_notification(passed_id)
    if event.called_ticket_id is not None:
        trigger_called_notification(event.called_ticket_id, event.room_number)
    check_and_trigger_approaching(event.queue_id)


def _sweep_single_queue(
    session_factory: sessionmaker[Session],
    queue_id: int,
    current_now: datetime,
) -> SmartCallSweepEvent | None:
    with session_factory() as db:
        queue = db.scalar(
            select(Queue)
            .where(Queue.id == queue_id)
            .with_for_update(skip_locked=True)
        )
        if not queue or not queue.is_active or queue.is_paused:
            db.rollback()
            return None

        expired_tickets = list(
            db.scalars(
                select(QueueTicket)
                .where(
                    QueueTicket.queue_id == queue.id,
                    QueueTicket.status == TicketStatus.CALLED,
                    QueueTicket.call_deadline_at.is_not(None),
                    QueueTicket.call_deadline_at <= current_now,
                )
                .order_by(QueueTicket.queue_position.asc())
            ).all()
        )
        if not expired_tickets:
            db.rollback()
            return None

        doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
        if not doctor:
            db.rollback()
            return None

        timeout_seconds = get_clinic_timeout_seconds(db, doctor.clinic_id)

        skipped_ticket_ids: list[int] = []
        for expired in expired_tickets:
            expired.status = TicketStatus.SKIPPED
            clear_ticket_call_countdown(expired)
            if expired.patient_id is not None:
                skipped_ticket_ids.append(expired.id)

        # SessionLocal uses autoflush=False; flush SKIPPED transitions before checking remaining active tickets
        db.flush()

        # Ensure we do not violate active-patient safety if another CALLED/SERVING exists
        remaining_active = db.scalar(
            select(QueueTicket.id)
            .where(
                QueueTicket.queue_id == queue.id,
                QueueTicket.status.in_([TicketStatus.CALLED, TicketStatus.SERVING]),
            )
            .limit(1)
        )

        advance_result = SmartCallAdvanceResult()
        if (
            remaining_active is None
            and queue.smart_call_mode == SmartCallMode.AUTOMATIC
        ):
            advance_result = advance_smart_call_for_queue(
                db,
                queue.id,
                timeout_seconds,
                now=current_now,
            )

        db.commit()

        return SmartCallSweepEvent(
            clinic_id=doctor.clinic_id,
            queue_id=queue.id,
            room_number=doctor.room_number,
            skipped_ticket_ids=skipped_ticket_ids,
            passed_ticket_ids=advance_result.passed_ticket_ids,
            called_ticket_id=(
                advance_result.called_ticket.id
                if advance_result.called_ticket is not None
                else None
            ),
            repositioned_any=advance_result.repositioned_any,
        )


def process_expired_called_tickets(
    now: datetime | None = None,
    *,
    session_factory: sessionmaker[Session] | None = None,
    dispatch_side_effects: bool = True,
) -> list[SmartCallSweepEvent]:
    """
    Sweep all active, non-paused queues with expired CALLED deadlines.
    Uses row-level Queue locking (`with_for_update(skip_locked=True)`) per queue
    so concurrent Reception actions (Serve/Skip/Cancel/Pause) cannot double-transition.
    """
    current_now = _as_utc(now) if now is not None else datetime.now(timezone.utc)
    factory = session_factory or db_session.SessionLocal

    with factory() as db:
        candidate_queue_ids = list(
            db.scalars(
                select(Queue.id)
                .join(QueueTicket, QueueTicket.queue_id == Queue.id)
                .where(
                    Queue.is_active == True,
                    Queue.is_paused == False,
                    QueueTicket.status == TicketStatus.CALLED,
                    QueueTicket.call_deadline_at.is_not(None),
                    QueueTicket.call_deadline_at <= current_now,
                )
                .distinct()
            ).all()
        )

    events: list[SmartCallSweepEvent] = []
    for queue_id in candidate_queue_ids:
        try:
            event = _sweep_single_queue(factory, queue_id, current_now)
            if event is None:
                continue
            events.append(event)
            if dispatch_side_effects:
                notify_display_update(event.clinic_id, None, queue_id=event.queue_id)
                dispatch_sweep_notifications(event)
        except Exception as exc:
            logger.error(
                "Error sweeping expired Smart Call ticket in queue %s: %s",
                queue_id,
                exc,
                exc_info=True,
            )

    return events


async def run_smart_call_timer_loop(
    stop_event: asyncio.Event,
    interval_seconds: float = SWEEP_INTERVAL_SECONDS,
) -> None:
    """Periodic background loop polling expired CALLED deadlines across all clinics."""
    logger.info("Smart Call timer loop started (interval=%.1fs)", interval_seconds)
    while not stop_event.is_set():
        try:
            events = await asyncio.to_thread(
                process_expired_called_tickets,
                None,
                dispatch_side_effects=False,
            )
            for event in events:
                notify_display_update(event.clinic_id, None, queue_id=event.queue_id)
                asyncio.create_task(
                    asyncio.to_thread(dispatch_sweep_notifications, event)
                )
        except Exception as exc:
            logger.error("Unexpected error in Smart Call timer loop: %s", exc, exc_info=True)

        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval_seconds)
        except asyncio.TimeoutError:
            continue
    logger.info("Smart Call timer loop stopped")
