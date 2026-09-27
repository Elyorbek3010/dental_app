from datetime import date
import json

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_db
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
)
def get_public_clinic_display(
    clinic_id: int,
    db: Session = Depends(get_db),
) -> PublicDisplayResponse:
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

    today = date.today()

    # Fetch active queues for this clinic today, ordered by doctor id
    queue_rows = db.execute(
        select(Queue, Doctor, Specialization)
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .join(Specialization, Doctor.specialization_id == Specialization.id)
        .where(
            Doctor.clinic_id == clinic_id,
            Queue.queue_date == today,
            Queue.is_active == True,
        )
        .order_by(Doctor.id.asc())
    ).all()

    clinic_dto = PublicDisplayClinic(
        id=clinic.id,
        name=clinic.name,
    )

    if not queue_rows:
        return PublicDisplayResponse(
            clinic=clinic_dto,
            queues=[],
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
                called_by_queue[t.queue_id] = PublicDisplayTicket(ticket_number=t.ticket_number)
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
                    name=specialization.name,
                ),
                is_paused=queue.is_paused,
                called_ticket=called_by_queue.get(queue.id),
                waiting_tickets=waiting_by_queue.get(queue.id, []),
            )
        )

    return PublicDisplayResponse(
        clinic=clinic_dto,
        queues=display_queues,
    )
