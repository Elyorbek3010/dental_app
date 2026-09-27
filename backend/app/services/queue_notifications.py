import logging
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select, update

from app.db.session import SessionLocal
from app.models.push_device import PushDevice
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.services.notifications import PushNotificationResult, send_push_notification

logger = logging.getLogger("app.services.queue_notifications")


def dispatch_patient_notification(
    patient_id: int | None,
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> list[PushNotificationResult]:
    """
    Sends a push notification to all active devices of a registered patient.
    
    Rules:
    - Never raises uncaught exceptions.
    - Only sends if patient_id is not None.
    - Only sends to PushDevice rows where is_active == True.
    - If a token is reported stale/unregistered by FCM (is_unregistered=True),
      safely marks that PushDevice is_active=False in the database.
    - Transient failures do NOT deactivate the device.
    - Uses its own SessionLocal to be decoupled from request-scoped sessions.
    """
    if patient_id is None:
        return []

    results: list[PushNotificationResult] = []
    try:
        with SessionLocal() as db:
            active_devices = list(
                db.scalars(
                    select(PushDevice).where(
                        PushDevice.user_id == patient_id,
                        PushDevice.is_active == True,
                    )
                ).all()
            )

            if not active_devices:
                logger.info(
                    "No active push devices found for patient_id=%s. Notification skipped.",
                    patient_id,
                )
                return []

            stale_device_ids: list[int] = []
            for device in active_devices:
                res = send_push_notification(
                    token=device.fcm_token,
                    title=title,
                    body=body,
                    data=data,
                )
                results.append(res)
                if res.is_unregistered:
                    stale_device_ids.append(device.id)

            if stale_device_ids:
                db.execute(
                    update(PushDevice)
                    .where(PushDevice.id.in_(stale_device_ids))
                    .values(is_active=False)
                )
                db.commit()
                logger.info(
                    "Deactivated %d stale PushDevice(s) for patient_id=%s (IDs=%s)",
                    len(stale_device_ids),
                    patient_id,
                    stale_device_ids,
                )
    except Exception as exc:
        logger.error(
            "Failed to dispatch push notification for patient_id=%s: %s",
            patient_id,
            exc,
            exc_info=True,
        )
    return results


def trigger_joined_notification(ticket_id: int) -> None:
    """
    Triggered after a patient successfully joins a queue.
    Title: "Dental Queue"
    Body: "Navbatga muvaffaqiyatli qo‘shildingiz. Ticket: №{ticket_number}"
    """
    try:
        with SessionLocal() as db:
            ticket = db.scalar(
                select(QueueTicket).where(QueueTicket.id == ticket_id)
            )
            if not ticket or ticket.patient_id is None:
                return

            patient_id = ticket.patient_id
            ticket_number = ticket.ticket_number
            queue_id = ticket.queue_id

        dispatch_patient_notification(
            patient_id=patient_id,
            title="Dental Queue",
            body=f"Navbatga muvaffaqiyatli qo‘shildingiz. Ticket: №{ticket_number}",
            data={
                "type": "QUEUE_JOINED",
                "ticket_id": str(ticket_id),
                "ticket_number": str(ticket_number),
                "queue_id": str(queue_id),
            },
        )
    except Exception as exc:
        logger.error(
            "Error triggering joined notification for ticket %s: %s",
            ticket_id,
            exc,
            exc_info=True,
        )


def trigger_called_notification(ticket_id: int, room_number: str | None = None) -> None:
    """
    Triggered when a waiting registered ticket is called (WAITING -> CALLED).
    Title: "Dental Queue"
    Body: "Navbatingiz keldi! Iltimos, {room_number}-xonaga kiring."
    Fallback (if room_number is null/empty): "Navbatingiz keldi! Iltimos, qabulga kiring."
    """
    try:
        resolved_room = room_number
        with SessionLocal() as db:
            ticket = db.scalar(
                select(QueueTicket).where(QueueTicket.id == ticket_id)
            )
            if not ticket or ticket.patient_id is None:
                return

            patient_id = ticket.patient_id
            queue_id = ticket.queue_id

            if resolved_room is None:
                from app.models.doctor import Doctor
                from app.models.queue import Queue

                queue = db.scalar(select(Queue).where(Queue.id == ticket.queue_id))
                if queue:
                    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
                    if doctor and doctor.room_number:
                        resolved_room = doctor.room_number

        if resolved_room and str(resolved_room).strip():
            body = f"Navbatingiz keldi! Iltimos, {str(resolved_room).strip()}-xonaga kiring."
        else:
            body = "Navbatingiz keldi! Iltimos, qabulga kiring."

        dispatch_patient_notification(
            patient_id=patient_id,
            title="Dental Queue",
            body=body,
            data={
                "type": "QUEUE_CALLED",
                "ticket_id": str(ticket_id),
                "room_number": str(resolved_room or ""),
                "queue_id": str(queue_id),
            },
        )
    except Exception as exc:
        logger.error(
            "Error triggering called notification for ticket %s: %s",
            ticket_id,
            exc,
            exc_info=True,
        )


def trigger_missed_turn_notification(ticket_id: int) -> None:
    """
    Triggered when an online/registered waiting patient misses a turn and is moved to the end.
    Title: "Dental Queue"
    Body: "Navbatingiz o‘tkazib yuborildi. Siz navbat oxiriga ko‘chirildingiz."
    """
    try:
        with SessionLocal() as db:
            ticket = db.scalar(
                select(QueueTicket).where(QueueTicket.id == ticket_id)
            )
            if not ticket or ticket.patient_id is None:
                return

            patient_id = ticket.patient_id
            queue_id = ticket.queue_id

        dispatch_patient_notification(
            patient_id=patient_id,
            title="Dental Queue",
            body="Navbatingiz o‘tkazib yuborildi. Siz navbat oxiriga ko‘chirildingiz.",
            data={
                "type": "QUEUE_MISSED_TURN",
                "ticket_id": str(ticket_id),
                "queue_id": str(queue_id),
            },
        )
    except Exception as exc:
        logger.error(
            "Error triggering missed turn notification for ticket %s: %s",
            ticket_id,
            exc,
            exc_info=True,
        )


def trigger_paused_notification(queue_id: int) -> None:
    """
    Triggered when a queue transitions from active to paused.
    Notifies ALL WAITING registered tickets in that queue (including not checked-in).
    Title: "Dental Queue"
    Body: "Navbat vaqtincha to‘xtatildi."
    """
    try:
        with SessionLocal() as db:
            waiting_tickets = list(
                db.scalars(
                    select(QueueTicket).where(
                        QueueTicket.queue_id == queue_id,
                        QueueTicket.status == TicketStatus.WAITING,
                        QueueTicket.patient_id.is_not(None),
                    )
                ).all()
            )
            patient_ids = {t.patient_id for t in waiting_tickets if t.patient_id is not None}

        for pid in patient_ids:
            dispatch_patient_notification(
                patient_id=pid,
                title="Dental Queue",
                body="Navbat vaqtincha to‘xtatildi.",
                data={
                    "type": "QUEUE_PAUSED",
                    "queue_id": str(queue_id),
                },
            )
    except Exception as exc:
        logger.error(
            "Error triggering paused notification for queue %s: %s",
            queue_id,
            exc,
            exc_info=True,
        )


def trigger_resumed_notification(queue_id: int) -> None:
    """
    Triggered when a queue transitions from paused to resumed.
    Notifies ALL WAITING registered tickets in that queue (including not checked-in).
    Title: "Dental Queue"
    Body: "Navbat yana davom etmoqda."
    """
    try:
        with SessionLocal() as db:
            waiting_tickets = list(
                db.scalars(
                    select(QueueTicket).where(
                        QueueTicket.queue_id == queue_id,
                        QueueTicket.status == TicketStatus.WAITING,
                        QueueTicket.patient_id.is_not(None),
                    )
                ).all()
            )
            patient_ids = {t.patient_id for t in waiting_tickets if t.patient_id is not None}

        for pid in patient_ids:
            dispatch_patient_notification(
                patient_id=pid,
                title="Dental Queue",
                body="Navbat yana davom etmoqda.",
                data={
                    "type": "QUEUE_RESUMED",
                    "queue_id": str(queue_id),
                },
            )
    except Exception as exc:
        logger.error(
            "Error triggering resumed notification for queue %s: %s",
            queue_id,
            exc,
            exc_info=True,
        )


def trigger_completed_notification(ticket_id: int) -> None:
    """
    Triggered when SERVING transitions to COMPLETED.
    Title: "Dental Queue"
    Body: "Tashrifingiz yakunlandi. Bizni tanlaganingiz uchun rahmat. Tez orada ko‘rishguncha! 👋"
    """
    try:
        with SessionLocal() as db:
            ticket = db.scalar(
                select(QueueTicket).where(QueueTicket.id == ticket_id)
            )
            if not ticket or ticket.patient_id is None:
                return

            patient_id = ticket.patient_id
            queue_id = ticket.queue_id

        dispatch_patient_notification(
            patient_id=patient_id,
            title="Dental Queue",
            body="Tashrifingiz yakunlandi. Bizni tanlaganingiz uchun rahmat. Tez orada ko‘rishguncha! 👋",
            data={
                "type": "QUEUE_COMPLETED",
                "ticket_id": str(ticket_id),
                "queue_id": str(queue_id),
            },
        )
    except Exception as exc:
        logger.error(
            "Error triggering completed notification for ticket %s: %s",
            ticket_id,
            exc,
            exc_info=True,
        )


def check_and_trigger_approaching(queue_id: int) -> None:
    """
    Evaluates whether any WAITING ticket in queue_id now has exactly 3 active people ahead.
    Uses existing real queue ordering semantics based on queue_position and active statuses
    (WAITING, CALLED, SERVING).
    
    By definition of distinct queue_position ordering, the 4th active ticket (offset 3)
    has exactly 3 active tickets ahead. No other ticket can have exactly 3 people ahead.
    
    If that 4th active ticket is WAITING, has a registered patient_id, and approaching_notified_at
    is NULL, it is atomically claimed and notified.
    
    Concurrency safety:
    Atomic SQL update ensures that even if concurrent queue mutations run this check simultaneously,
    only ONE worker claims approaching_notified_at and dispatches the notification.
    """
    try:
        with SessionLocal() as db:
            candidate = db.scalar(
                select(QueueTicket)
                .where(
                    QueueTicket.queue_id == queue_id,
                    QueueTicket.status.in_([
                        TicketStatus.WAITING,
                        TicketStatus.CALLED,
                        TicketStatus.SERVING,
                    ]),
                )
                .order_by(QueueTicket.queue_position.asc())
                .offset(3)
                .limit(1)
            )

            if (
                candidate is None
                or candidate.status != TicketStatus.WAITING
                or candidate.patient_id is None
                or candidate.approaching_notified_at is not None
            ):
                return

            now = datetime.now(timezone.utc)
            # Atomic update claim:
            claimed = db.execute(
                update(QueueTicket)
                .where(
                    QueueTicket.id == candidate.id,
                    QueueTicket.approaching_notified_at.is_(None),
                )
                .values(approaching_notified_at=now)
            ).rowcount
            db.commit()

            if claimed > 0:
                logger.info(
                    "Approaching notification claimed for ticket_id=%s (patient_id=%s, queue_id=%s)",
                    candidate.id,
                    candidate.patient_id,
                    queue_id,
                )
                dispatch_patient_notification(
                    patient_id=candidate.patient_id,
                    title="Dental Queue",
                    body="Navbatingiz yaqinlashmoqda. Oldingizda 3 kishi qoldi.",
                    data={
                        "type": "QUEUE_APPROACHING",
                        "ticket_id": str(candidate.id),
                        "queue_id": str(queue_id),
                    },
                )
    except Exception as exc:
        logger.error(
            "Error checking approaching notifications for queue %s: %s",
            queue_id,
            exc,
            exc_info=True,
        )


# =========================================================================
# Background Task Scheduling Helpers
# =========================================================================

def schedule_joined_notification(ticket_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_joined_notification, ticket_id)
    else:
        trigger_joined_notification(ticket_id)


def schedule_called_notification(ticket_id: int, room_number: str | None = None, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_called_notification, ticket_id, room_number)
    else:
        trigger_called_notification(ticket_id, room_number)


def schedule_missed_turn_notification(ticket_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_missed_turn_notification, ticket_id)
    else:
        trigger_missed_turn_notification(ticket_id)


def schedule_paused_notification(queue_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_paused_notification, queue_id)
    else:
        trigger_paused_notification(queue_id)


def schedule_resumed_notification(queue_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_resumed_notification, queue_id)
    else:
        trigger_resumed_notification(queue_id)


def schedule_completed_notification(ticket_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_completed_notification, ticket_id)
    else:
        trigger_completed_notification(ticket_id)


def schedule_approaching_check(queue_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(check_and_trigger_approaching, queue_id)
    else:
        check_and_trigger_approaching(queue_id)
