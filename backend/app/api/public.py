from datetime import date, datetime, timezone
import json

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_db, get_language
from app.core.rate_limit import limit_public_display
from app.db.session import SessionLocal
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.models.specialization import Specialization
from app.realtime import manager
from app.schemas.public import (
    PublicDisplayClinic,
    PublicDisplayDoctor,
    PublicDisplayQueue,
    PublicDisplayResponse,
    PublicDisplaySpecialization,
    PublicDisplayTicket,
)
from app.services.shift_service import ACTIVE_SHIFT_STATUSES

router = APIRouter(
    prefix="/api/public",
    tags=["Public"],
)


@router.websocket("/ws/clinics/{clinic_id}/display")
async def public_clinic_display_websocket(
    websocket: WebSocket,
    clinic_id: int,
) -> None:
    # Validate clinic existence using a short-lived DB session
    # Avoid holding a PostgreSQL connection during the long-running socket lifetime
    with SessionLocal() as db:
        clinic_exists = db.scalar(
            select(Clinic.id).where(Clinic.id == clinic_id)
        ) is not None

    if not clinic_exists:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Clinic not found")
        return

    # Accept connection and register with connection manager
    await manager.connect(clinic_id, websocket)

    try:
        # Send safe initial connection handshake message
        await websocket.send_json({
            "type": "connected",
            "clinic_id": clinic_id,
        })

        # Keep connection alive; process client messages (safe ping/pong)
        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
                if isinstance(payload, dict) and payload.get("type") == "ping":
                    await websocket.send_json({"type": "pong"})
            except json.JSONDecodeError:
                if data.strip().lower() == "ping":
                    await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        manager.disconnect(clinic_id, websocket)



@router.get(
    "/clinics/{clinic_id}/display",
    response_model=PublicDisplayResponse,
    dependencies=[Depends(limit_public_display)],
)
def get_public_clinic_display(
    clinic_id: int,
    db: Session = Depends(get_db),
    lang: str = Depends(get_language),
) -> PublicDisplayResponse:
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

    # Fetch currently active shifts (OPEN or CLOSING, including overnight shifts)
    queue_rows = db.execute(
        select(Queue, Doctor, Specialization)
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .join(Specialization, Doctor.specialization_id == Specialization.id)
        .where(
            Doctor.clinic_id == clinic_id,
            Queue.is_active == True,
            Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
        )
        .order_by(Doctor.id.asc(), Queue.id.desc())
    ).all()

    clinic_dto = PublicDisplayClinic(
        id=clinic.id,
        name=clinic.name,
    )

    if not queue_rows:
        return PublicDisplayResponse(
            clinic=clinic_dto,
            queues=[],
            server_time=datetime.now(timezone.utc),
        )

    queue_ids = [q.id for q, _d, _s in queue_rows]

    # Fetch only relevant tickets in one query:
    # 1. CALLED tickets (status == CALLED)
    # 2. WAITING tickets physically checked in (status == WAITING and checked_in_at IS NOT NULL)
    # Ordered by queue_position asc
    tickets = db.scalars(
        select(QueueTicket)
        .where(
            QueueTicket.queue_id.in_(queue_ids),
            (
                (QueueTicket.status == TicketStatus.CALLED)
                | (
                    (QueueTicket.status == TicketStatus.WAITING)
                    & (QueueTicket.checked_in_at.is_not(None))
                )
            ),
        )
        .order_by(QueueTicket.queue_position.asc())
    ).all()

    called_by_queue: dict[int, PublicDisplayTicket] = {}
    waiting_by_queue: dict[int, list[PublicDisplayTicket]] = {qid: [] for qid in queue_ids}

    for t in tickets:
        if t.status == TicketStatus.CALLED:
            if t.queue_id not in called_by_queue:
                called_by_queue[t.queue_id] = PublicDisplayTicket(
                    ticket_number=t.ticket_number,
                    called_at=t.called_at,
                    call_deadline_at=t.call_deadline_at,
                    paused_remaining_seconds=t.paused_remaining_seconds,
                )
        elif t.status == TicketStatus.WAITING and t.checked_in_at is not None:
            waiting_by_queue[t.queue_id].append(PublicDisplayTicket(ticket_number=t.ticket_number))

    display_queues: list[PublicDisplayQueue] = []
    for queue, doctor, specialization in queue_rows:
        display_queues.append(
            PublicDisplayQueue(
                doctor=PublicDisplayDoctor(
                    id=doctor.id,
                    full_name=doctor.full_name,
                    room_number=doctor.room_number,
                ),
                specialization=PublicDisplaySpecialization(
                    id=specialization.id,
                    name=specialization.get_localized_name(lang),
                ),
                is_paused=queue.is_paused,
                shift_status=queue.shift_status,
                called_ticket=called_by_queue.get(queue.id),
                waiting_tickets=waiting_by_queue.get(queue.id, []),
            )
        )

    return PublicDisplayResponse(
        clinic=clinic_dto,
        queues=display_queues,
        server_time=datetime.now(timezone.utc),
    )
