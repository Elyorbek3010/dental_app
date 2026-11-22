import logging
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.db import session as db_session
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
        with db_session.SessionLocal() as db:
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
                if not res.success:
                    logger.warning(
                        "Push notification delivery failed for patient_id=%s device_id=%s error_code=%s",
                        patient_id,
                        device.id,
                        res.error_code,
                    )
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
        with db_session.SessionLocal() as db:
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
        with db_session.SessionLocal() as db:
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
        with db_session.SessionLocal() as db:
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


def trigger_skipped_notification(ticket_id: int) -> None:
    """
    Triggered when a patient ticket is manually marked SKIPPED by reception.
    Distinct from QUEUE_MISSED_TURN (which repositions an unchecked-in WAITING ticket).
    """
    try:
        with db_session.SessionLocal() as db:
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
            body=(
                f"Taloningiz №{ticket_number} navbatdan vaqtincha chetlatildi (Skipped). "
                "Qayta tiklash uchun qabulxonaga murojaat qiling."
            ),
            data={
                "type": "QUEUE_SKIPPED",
                "ticket_id": str(ticket_id),
                "ticket_number": str(ticket_number),
                "queue_id": str(queue_id),
            },
        )
    except Exception as exc:
        logger.error(
            "Error triggering skipped notification for ticket %s: %s",
            ticket_id,
            exc,
            exc_info=True,
        )


def trigger_restored_notification(ticket_id: int) -> None:
    """
    Triggered when a SKIPPED ticket is manually restored to WAITING at the end of the queue.
    """
    try:
        with db_session.SessionLocal() as db:
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
            body=(
                f"Taloningiz №{ticket_number} navbatga qayta tiklandi "
                "va navbat oxiriga qo‘shildi."
            ),
            data={
                "type": "QUEUE_RESTORED",
                "ticket_id": str(ticket_id),
                "ticket_number": str(ticket_number),
                "queue_id": str(queue_id),
            },
        )
    except Exception as exc:
        logger.error(
            "Error triggering restored notification for ticket %s: %s",
            ticket_id,
            exc,
            exc_info=True,
        )


def build_cancelled_notification_content(
    lang: str = "uz",
    doctor_name: str | None = None,
    clinic_name: str | None = None,
) -> tuple[str, str]:
    """
    Formats localized (title, body) for a Reception-initiated ticket cancellation
    in Uzbek ('uz'), Russian ('ru'), or English ('en') with dynamic doctor/clinic context.
    """
    normalized_lang = (lang or "uz").strip().lower()
    if normalized_lang not in ("uz", "ru", "en"):
        normalized_lang = "uz"

    clean_doctor = doctor_name.strip() if doctor_name and doctor_name.strip() else None
    clean_clinic = clinic_name.strip() if clinic_name and clinic_name.strip() else None

    if clean_doctor and clean_clinic:
        context = f"{clean_doctor} ({clean_clinic})"
    else:
        context = clean_doctor or clean_clinic

    if normalized_lang == "ru":
        title = "Ваша запись отменена"
        if context:
            body = (
                f"Ваша очередь к {context} отменена регистратурой. "
                "Для подробной информации обратитесь в регистратуру."
            )
        else:
            body = (
                "Ваша очередь отменена регистратурой. "
                "Для подробной информации обратитесь в регистратуру."
            )
        return title, body

    if normalized_lang == "en":
        title = "Queue ticket cancelled"
        if context:
            body = (
                f"Your queue ticket for {context} was cancelled by reception. "
                "Please contact reception for details."
            )
        else:
            body = (
                "Your queue ticket was cancelled by reception. "
                "Please contact reception for details."
            )
        return title, body

    title = "Navbatingiz bekor qilindi"
    if context:
        body = (
            f"{context} qabulidagi navbatingiz qabulxona tomonidan bekor qilindi. "
            "Batafsil ma'lumot uchun qabulxonaga murojaat qiling."
        )
    else:
        body = (
            "Navbatingiz qabulxona tomonidan bekor qilindi. "
            "Batafsil ma'lumot uchun qabulxonaga murojaat qiling."
        )
    return title, body


def trigger_cancelled_notification(ticket_id: int, lang: str = "uz") -> None:
    """
    Triggered when Reception or Admin manually cancels a registered patient's ticket.
    Verifies ticket status is CANCELLED before dispatching.
    """
    try:
        doctor_name: str | None = None
        clinic_name: str | None = None
        with db_session.SessionLocal() as db:
            ticket = db.scalar(
                select(QueueTicket).where(QueueTicket.id == ticket_id)
            )
            if (
                not ticket
                or ticket.patient_id is None
                or ticket.status != TicketStatus.CANCELLED
            ):
                return

            patient_id = ticket.patient_id
            ticket_number = ticket.ticket_number
            queue_id = ticket.queue_id

            from app.models.clinic import Clinic
            from app.models.doctor import Doctor
            from app.models.queue import Queue

            queue = db.scalar(select(Queue).where(Queue.id == queue_id))
            if queue:
                doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
                if doctor:
                    doctor_name = doctor.full_name
                    clinic = db.scalar(select(Clinic).where(Clinic.id == doctor.clinic_id))
                    if clinic:
                        clinic_name = clinic.name

        title, body = build_cancelled_notification_content(
            lang=lang,
            doctor_name=doctor_name,
            clinic_name=clinic_name,
        )
        dispatch_patient_notification(
            patient_id=patient_id,
            title=title,
            body=body,
            data={
                "type": "QUEUE_CANCELLED",
                "ticket_id": str(ticket_id),
                "ticket_number": str(ticket_number),
                "queue_id": str(queue_id),
                "doctor_name": doctor_name or "",
                "clinic_name": clinic_name or "",
            },
        )
    except Exception as exc:
        logger.error(
            "Error triggering cancelled notification for ticket %s: %s",
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
        with db_session.SessionLocal() as db:
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
        with db_session.SessionLocal() as db:
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
        with db_session.SessionLocal() as db:
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


ACTIVE_QUEUE_STATUSES = (
    TicketStatus.WAITING,
    TicketStatus.CALLED,
    TicketStatus.SERVING,
)


def get_active_tickets_with_four_plus_ahead(db: Session, queue_id: int) -> list[int]:
    """
    Returns IDs of unnotified WAITING registered tickets in `queue_id` that currently
    have 4 or more active tickets ahead (index >= 4), so subsequent jumps across
    the 3-ahead threshold can still be detected cleanly.
    """
    active_tickets = list(
        db.scalars(
            select(QueueTicket)
            .where(
                QueueTicket.queue_id == queue_id,
                QueueTicket.status.in_(ACTIVE_QUEUE_STATUSES),
            )
            .order_by(QueueTicket.queue_position.asc())
        ).all()
    )
    return [
        t.id
        for idx, t in enumerate(active_tickets)
        if idx >= 4
        and t.status == TicketStatus.WAITING
        and t.patient_id is not None
        and t.approaching_notified_at is None
    ]


def reset_approaching_on_requeue(db: Session, queue_id: int, ticket: QueueTicket) -> bool:
    """
    Re-evaluates 3-ahead notification eligibility after a ticket moves to the back
    via Miss Turn or Skip -> Restore.

    - If >= 4 active tickets are now ahead of `ticket`, clears `approaching_notified_at`
      so the patient receives a fresh notification on their new approach.
    - If <= 3 active tickets are ahead (queue is already short), keeps prior notified state
      and returns True so an immediate misleading second notification is suppressed.
    """
    ahead_count = len(
        db.scalars(
            select(QueueTicket.id).where(
                QueueTicket.queue_id == queue_id,
                QueueTicket.id != ticket.id,
                QueueTicket.status.in_(ACTIVE_QUEUE_STATUSES),
                QueueTicket.queue_position < ticket.queue_position,
            )
        ).all()
    )
    if ahead_count >= 4:
        ticket.approaching_notified_at = None
        return False
    return True


def check_and_trigger_approaching(
    queue_id: int,
    jumped_candidate_ids: list[int] | None = None,
    exclude_ticket_ids: list[int] | None = None,
) -> None:
    """
    Evaluates whether any unnotified WAITING registered ticket in `queue_id` now has
    3 active people ahead (`offset(3)`), OR crossed from >= 4 ahead down to 1..2 ahead
    because multiple tickets ahead left/repositioned in one step.

    Concurrency & status safety:
    Atomic SQL UPDATE claims `approaching_notified_at` only while `status == WAITING`
    and `approaching_notified_at IS NULL`, guaranteeing at most one notification per
    approach and never notifying cancelled, skipped, or completed tickets.
    """
    try:
        excluded = set(exclude_ticket_ids or ())
        jumped = set(jumped_candidate_ids or ())

        with db_session.SessionLocal() as db:
            active_tickets = list(
                db.scalars(
                    select(QueueTicket)
                    .where(
                        QueueTicket.queue_id == queue_id,
                        QueueTicket.status.in_(ACTIVE_QUEUE_STATUSES),
                    )
                    .order_by(QueueTicket.queue_position.asc())
                ).all()
            )

            targets: list[tuple[QueueTicket, int]] = []
            for idx, candidate in enumerate(active_tickets):
                if (
                    candidate.status != TicketStatus.WAITING
                    or candidate.patient_id is None
                    or candidate.approaching_notified_at is not None
                    or candidate.id in excluded
                ):
                    continue
                if idx == 3 or (idx in (1, 2) and candidate.id in jumped):
                    targets.append((candidate, idx))

            if not targets:
                return

            now = datetime.now(timezone.utc)
            to_notify: list[tuple[int, int, int]] = []
            for candidate, ahead_count in targets:
                claimed = db.execute(
                    update(QueueTicket)
                    .where(
                        QueueTicket.id == candidate.id,
                        QueueTicket.status == TicketStatus.WAITING,
                        QueueTicket.approaching_notified_at.is_(None),
                    )
                    .values(approaching_notified_at=now)
                ).rowcount
                if claimed > 0 and candidate.patient_id is not None:
                    to_notify.append((candidate.id, candidate.patient_id, ahead_count))

            if to_notify:
                db.commit()

            for claimed_ticket_id, patient_id, ahead_count in to_notify:
                logger.info(
                    "Approaching notification claimed for ticket_id=%s (patient_id=%s, queue_id=%s, ahead=%s)",
                    claimed_ticket_id,
                    patient_id,
                    queue_id,
                    ahead_count,
                )
                dispatch_patient_notification(
                    patient_id=patient_id,
                    title="Dental Queue",
                    body=f"Navbatingiz yaqinlashmoqda. Oldingizda {ahead_count} kishi qoldi.",
                    data={
                        "type": "QUEUE_APPROACHING",
                        "ticket_id": str(claimed_ticket_id),
                        "queue_id": str(queue_id),
                        "ahead_count": str(ahead_count),
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


def schedule_skipped_notification(ticket_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_skipped_notification, ticket_id)
    else:
        trigger_skipped_notification(ticket_id)


def schedule_restored_notification(ticket_id: int, background_tasks: Any = None) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_restored_notification, ticket_id)
    else:
        trigger_restored_notification(ticket_id)


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


def schedule_cancelled_notification(
    ticket_id: int,
    lang: str = "uz",
    background_tasks: Any = None,
) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(trigger_cancelled_notification, ticket_id, lang)
    else:
        trigger_cancelled_notification(ticket_id, lang=lang)


def schedule_approaching_check(
    queue_id: int,
    background_tasks: Any = None,
    *,
    jumped_candidate_ids: list[int] | None = None,
    exclude_ticket_ids: list[int] | None = None,
) -> None:
    if background_tasks is not None and hasattr(background_tasks, "add_task"):
        background_tasks.add_task(
            check_and_trigger_approaching,
            queue_id,
            jumped_candidate_ids,
            exclude_ticket_ids,
        )
    else:
        check_and_trigger_approaching(
            queue_id,
            jumped_candidate_ids=jumped_candidate_ids,
            exclude_ticket_ids=exclude_ticket_ids,
        )
