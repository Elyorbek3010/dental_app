from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_roles
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.schemas.queue import (
    MyQueueTicketResponse,
    MyTicketDoctorResponse,
    MyTicketSpecializationResponse,
    QueueResponse,
    QueueStatusResponse,
    QueueTicketResponse,
    ReceptionQueueDoctorResponse,
    ReceptionQueueOverviewResponse,
    ReceptionQueueSpecializationResponse,
    WalkInPatientCreate,
)

router = APIRouter(
    prefix="/api/queues",
    tags=["Queues"],
)


@router.get(
    "/my-ticket",
    response_model=MyQueueTicketResponse,
)
def get_my_ticket(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> MyQueueTicketResponse:
    result = db.execute(
        select(QueueTicket, Doctor, Specialization)
        .join(Queue, QueueTicket.queue_id == Queue.id)
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .join(Specialization, Doctor.specialization_id == Specialization.id)
        .where(
            QueueTicket.patient_id == current_user.id,
            QueueTicket.status.in_([
                TicketStatus.WAITING,
                TicketStatus.CALLED,
                TicketStatus.SERVING,
            ]),
        )
        .order_by(QueueTicket.created_at.desc())
    ).first()

    if not result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active queue ticket found",
        )

    ticket, doctor, specialization = result

    people_ahead = (
        db.scalar(
            select(func.count(QueueTicket.id)).where(
                QueueTicket.queue_id == ticket.queue_id,
                QueueTicket.queue_position < ticket.queue_position,
                QueueTicket.status.in_([
                    TicketStatus.WAITING,
                    TicketStatus.CALLED,
                    TicketStatus.SERVING,
                ]),
            )
        )
        or 0
    )

    return MyQueueTicketResponse(
        id=ticket.id,
        queue_id=ticket.queue_id,
        ticket_number=ticket.ticket_number,
        status=ticket.status,
        created_at=ticket.created_at,
        people_ahead=people_ahead,
        doctor=MyTicketDoctorResponse(
            id=doctor.id,
            full_name=doctor.full_name,
            room_number=doctor.room_number,
        ),
        specialization=MyTicketSpecializationResponse(
            id=specialization.id,
            name=specialization.name,
        ),
    )


@router.get(
    "/reception/today",
    response_model=list[ReceptionQueueOverviewResponse],
)
def get_reception_today_queues(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> list[ReceptionQueueOverviewResponse]:
    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )

    today = date.today()

    query = (
        select(
            Queue,
            Doctor,
            Specialization,
            func.count(
                case((QueueTicket.status == TicketStatus.WAITING, QueueTicket.id))
            ).label("waiting_count"),
            func.count(
                case((QueueTicket.status == TicketStatus.CALLED, QueueTicket.id))
            ).label("called_count"),
            func.count(
                case((QueueTicket.status == TicketStatus.SERVING, QueueTicket.id))
            ).label("serving_count"),
        )
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .join(Specialization, Doctor.specialization_id == Specialization.id)
        .outerjoin(QueueTicket, QueueTicket.queue_id == Queue.id)
        .where(
            Queue.queue_date == today,
            Queue.is_active == True,
        )
    )

    if current_user.role == UserRole.RECEPTIONIST:
        query = query.where(Doctor.clinic_id == current_user.clinic_id)

    query = query.group_by(Queue.id, Doctor.id, Specialization.id).order_by(
        Doctor.full_name.asc()
    )

    results = db.execute(query).all()

    return [
        ReceptionQueueOverviewResponse(
            queue_id=queue.id,
            queue_date=queue.queue_date,
            is_paused=queue.is_paused,
            is_active=queue.is_active,
            doctor=ReceptionQueueDoctorResponse(
                id=doctor.id,
                full_name=doctor.full_name,
                room_number=doctor.room_number,
            ),
            specialization=ReceptionQueueSpecializationResponse(
                id=specialization.id,
                name=specialization.name,
            ),
            waiting_count=waiting_count,
            called_count=called_count,
            serving_count=serving_count,
        )
        for queue, doctor, specialization, waiting_count, called_count, serving_count in results
    ]


@router.get(
    "/{queue_id}/status",
    response_model=QueueStatusResponse,
)
def get_queue_status(
    queue_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> QueueStatusResponse:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    if not queue.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    waiting_count = (
        db.scalar(
            select(func.count(QueueTicket.id)).where(
                QueueTicket.queue_id == queue.id,
                QueueTicket.status == TicketStatus.WAITING,
            )
        )
        or 0
    )

    return QueueStatusResponse(
        queue_id=queue.id,
        doctor_id=queue.doctor_id,
        is_paused=queue.is_paused,
        waiting_count=waiting_count,
    )


@router.patch(
    "/{queue_id}/pause",
    response_model=QueueResponse,
)
def pause_queue(
    queue_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> Queue:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    if not queue.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    if queue.is_paused:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is already paused",
        )

    queue.is_paused = True
    db.commit()
    db.refresh(queue)
    return queue


@router.patch(
    "/{queue_id}/resume",
    response_model=QueueResponse,
)
def resume_queue(
    queue_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> Queue:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    if not queue.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    if not queue.is_paused:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is not paused",
        )

    queue.is_paused = False
    db.commit()
    db.refresh(queue)
    return queue


@router.get(
    "/{queue_id}/tickets",
    response_model=list[QueueTicketResponse],
)
def get_queue_tickets(
    queue_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> list[QueueTicket]:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    tickets = db.scalars(
        select(QueueTicket)
        .where(QueueTicket.queue_id == queue.id)
        .order_by(QueueTicket.queue_position.asc())
    ).all()

    return list(tickets)


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/call",
    response_model=QueueTicketResponse,
)
def call_patient(
    queue_id: int,
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.id == ticket_id,
            QueueTicket.queue_id == queue_id,
        )
    )
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found in this queue",
        )

    if ticket.status != TicketStatus.WAITING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only waiting tickets can be called",
        )

    ticket.status = TicketStatus.CALLED
    db.commit()
    db.refresh(ticket)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/serve",
    response_model=QueueTicketResponse,
)
def serve_patient(
    queue_id: int,
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.id == ticket_id,
            QueueTicket.queue_id == queue_id,
        )
    )
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found in this queue",
        )

    if ticket.status != TicketStatus.CALLED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only called tickets can be served",
        )

    ticket.status = TicketStatus.SERVING
    db.commit()
    db.refresh(ticket)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/complete",
    response_model=QueueTicketResponse,
)
def complete_patient(
    queue_id: int,
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.id == ticket_id,
            QueueTicket.queue_id == queue_id,
        )
    )
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found in this queue",
        )

    if ticket.status != TicketStatus.SERVING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only serving tickets can be completed",
        )

    ticket.status = TicketStatus.COMPLETED
    db.commit()
    db.refresh(ticket)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/skip",
    response_model=QueueTicketResponse,
)
def skip_patient(
    queue_id: int,
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.id == ticket_id,
            QueueTicket.queue_id == queue_id,
        )
    )
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found in this queue",
        )

    if ticket.status not in (TicketStatus.WAITING, TicketStatus.CALLED):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only waiting or called tickets can be skipped",
        )

    ticket.status = TicketStatus.SKIPPED
    db.commit()
    db.refresh(ticket)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/restore",
    response_model=QueueTicketResponse,
)
def restore_patient(
    queue_id: int,
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    # Lock the Queue row for update to ensure concurrency-safe queue_position calculation
    queue = db.scalar(
        select(Queue).where(Queue.id == queue_id).with_for_update()
    )
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.id == ticket_id,
            QueueTicket.queue_id == queue_id,
        )
    )
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found in this queue",
        )

    if ticket.status != TicketStatus.SKIPPED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only skipped tickets can be restored",
        )

    current_max_pos = db.scalar(
        select(func.coalesce(func.max(QueueTicket.queue_position), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    )
    new_queue_position = (current_max_pos or 0) + 1

    ticket.status = TicketStatus.WAITING
    ticket.queue_position = new_queue_position
    db.commit()
    db.refresh(ticket)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/cancel",
    response_model=QueueTicketResponse,
)
def cancel_patient(
    queue_id: int,
    ticket_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    queue = db.scalar(select(Queue).where(Queue.id == queue_id))
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.id == ticket_id,
            QueueTicket.queue_id == queue_id,
        )
    )
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ticket not found in this queue",
        )

    if ticket.status not in (TicketStatus.WAITING, TicketStatus.CALLED, TicketStatus.SKIPPED):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only waiting, called, or skipped tickets can be cancelled",
        )

    ticket.status = TicketStatus.CANCELLED
    db.commit()
    db.refresh(ticket)
    return ticket


@router.post(
    "/{queue_id}/join",
    response_model=QueueTicketResponse,
    status_code=status.HTTP_201_CREATED,
)
def join_queue(
    queue_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> QueueTicket:
    # Lock the Queue row for update to ensure concurrency-safe ticket number generation
    queue = db.scalar(
        select(Queue).where(Queue.id == queue_id).with_for_update()
    )
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    if not queue.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    if queue.is_paused:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is paused",
        )

    # Check whether current_user already has an active ticket in this queue
    active_ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.patient_id == current_user.id,
            QueueTicket.status.in_([
                TicketStatus.WAITING,
                TicketStatus.CALLED,
                TicketStatus.SERVING,
            ]),
        )
    )
    if active_ticket:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Patient already has an active ticket in this queue",
        )

    # Generate the next ticket number and queue position while queue row is locked
    current_max_ticket = db.scalar(
        select(func.coalesce(func.max(QueueTicket.ticket_number), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    )
    next_ticket_number = (current_max_ticket or 0) + 1

    current_max_pos = db.scalar(
        select(func.coalesce(func.max(QueueTicket.queue_position), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    )
    next_queue_position = (current_max_pos or 0) + 1

    ticket = QueueTicket(
        queue_id=queue.id,
        patient_id=current_user.id,
        patient_name=current_user.full_name,
        patient_phone=current_user.phone,
        ticket_number=next_ticket_number,
        queue_position=next_queue_position,
        source=TicketSource.ONLINE,
        status=TicketStatus.WAITING,
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    return ticket


@router.post(
    "/{queue_id}/walk-in",
    response_model=QueueTicketResponse,
    status_code=status.HTTP_201_CREATED,
)
def add_walk_in_patient(
    queue_id: int,
    request: WalkInPatientCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    # Lock the Queue row for update to ensure concurrency-safe ticket number generation
    queue = db.scalar(
        select(Queue).where(Queue.id == queue_id).with_for_update()
    )
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    if not queue.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    if queue.is_paused:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is paused",
        )

    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if current_user.clinic_id != doctor.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot access another clinic's queue",
            )

    # Generate the next ticket number and queue position while queue row is locked
    current_max_ticket = db.scalar(
        select(func.coalesce(func.max(QueueTicket.ticket_number), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    )
    next_ticket_number = (current_max_ticket or 0) + 1

    current_max_pos = db.scalar(
        select(func.coalesce(func.max(QueueTicket.queue_position), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    )
    next_queue_position = (current_max_pos or 0) + 1

    ticket = QueueTicket(
        queue_id=queue.id,
        patient_id=None,
        patient_name=request.patient_name,
        patient_phone=request.patient_phone,
        ticket_number=next_ticket_number,
        queue_position=next_queue_position,
        source=TicketSource.WALK_IN,
        status=TicketStatus.WAITING,
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    return ticket
