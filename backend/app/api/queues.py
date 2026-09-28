from datetime import date, datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from jose import JWTError
from sqlalchemy import case, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import get_db, get_language, require_roles
from app.core.config import settings
from app.core.security import create_check_in_qr_token, decode_check_in_qr_token
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.realtime import notify_display_update
from app.services.queue_notifications import (
    schedule_approaching_check,
    schedule_called_notification,
    schedule_completed_notification,
    schedule_joined_notification,
    schedule_missed_turn_notification,
    schedule_paused_notification,
    schedule_resumed_notification,
    trigger_missed_turn_notification,
)
from app.schemas.queue import (
    CheckInQRResponse,
    MyQueueTicketResponse,
    MyTicketDoctorResponse,
    MyTicketSpecializationResponse,
    PatientQRCheckInRequest,
    QueueCreateRequest,
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
    lang: str = Depends(get_language),
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
        checked_in_at=ticket.checked_in_at,
        check_in_method=ticket.check_in_method,
        people_ahead=people_ahead,
        doctor=MyTicketDoctorResponse(
            id=doctor.id,
            full_name=doctor.full_name,
            room_number=doctor.room_number,
        ),
        specialization=MyTicketSpecializationResponse(
            id=specialization.id,
            name=specialization.get_localized_name(lang),
        ),
    )


@router.patch(
    "/my-ticket/cancel",
    response_model=QueueTicketResponse,
)
def cancel_my_ticket(
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> QueueTicket:
    ticket = db.scalar(
        select(QueueTicket)
        .where(
            QueueTicket.patient_id == current_user.id,
            QueueTicket.status.in_([
                TicketStatus.WAITING,
                TicketStatus.CALLED,
                TicketStatus.SKIPPED,
            ]),
        )
        .order_by(QueueTicket.created_at.desc())
    )

    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active ticket found to cancel",
        )

    queue = db.scalar(select(Queue).where(Queue.id == ticket.queue_id))
    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id)) if queue else None

    ticket.status = TicketStatus.CANCELLED
    db.commit()
    db.refresh(ticket)

    if doctor:
        notify_display_update(doctor.clinic_id, background_tasks)
    if queue:
        schedule_approaching_check(queue.id, background_tasks)

    return ticket


@router.post(
    "",
    response_model=QueueResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create or open today's queue for a doctor",
)
@router.post(
    "/open",
    response_model=QueueResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Open today's queue for a doctor (alias)",
)
def open_today_queue(
    request: QueueCreateRequest,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> Queue:
    doctor = db.scalar(select(Doctor).where(Doctor.id == request.doctor_id))
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
        if doctor.clinic_id != current_user.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot open queue for another clinic's doctor",
            )

    if not doctor.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Doctor is inactive",
        )

    target_date = request.queue_date or date.today()

    existing_queue = db.scalar(
        select(Queue).where(
            Queue.doctor_id == doctor.id,
            Queue.queue_date == target_date,
        )
    )

    if existing_queue:
        if existing_queue.is_active:
            if request.idempotent:
                return existing_queue
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Queue already exists for this doctor today",
            )
        else:
            existing_queue.is_active = True
            existing_queue.is_paused = False
            db.commit()
            db.refresh(existing_queue)
            notify_display_update(doctor.clinic_id, background_tasks)
            return existing_queue

    new_queue = Queue(
        doctor_id=doctor.id,
        queue_date=target_date,
        is_paused=False,
        is_active=True,
    )
    db.add(new_queue)
    try:
        db.commit()
        db.refresh(new_queue)
    except IntegrityError:
        db.rollback()
        existing = db.scalar(
            select(Queue).where(
                Queue.doctor_id == doctor.id,
                Queue.queue_date == target_date,
            )
        )
        if existing and request.idempotent:
            return existing
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue already exists for this doctor today",
        )

    notify_display_update(doctor.clinic_id, background_tasks)
    return new_queue


@router.get(
    "/reception/today",
    response_model=list[ReceptionQueueOverviewResponse],
)
def get_reception_today_queues(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
    lang: str = Depends(get_language),
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
                name=specialization.get_localized_name(lang),
            ),
            waiting_count=waiting_count,
            called_count=called_count,
            serving_count=serving_count,
        )
        for queue, doctor, specialization, waiting_count, called_count, serving_count in results
    ]


@router.get(
    "/check-in/qr-token",
    response_model=CheckInQRResponse,
)
def get_check_in_qr_token(
    clinic_id: int | None = Query(default=None, description="Clinic ID (required for admin)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> CheckInQRResponse:
    if current_user.role == UserRole.RECEPTIONIST:
        if current_user.clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Receptionist is not assigned to a clinic",
            )
        if clinic_id is not None and clinic_id != current_user.clinic_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot request QR token for another clinic",
            )
        target_clinic_id = current_user.clinic_id
    else:  # ADMIN
        if clinic_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="clinic_id query parameter is required for admin",
            )
        target_clinic_id = clinic_id

    clinic = db.scalar(select(Clinic).where(Clinic.id == target_clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

    token = create_check_in_qr_token(target_clinic_id)
    return CheckInQRResponse(
        token=token,
        expires_in_seconds=settings.CHECK_IN_QR_EXPIRE_MINUTES * 60,
    )


@router.post(
    "/check-in/qr",
    response_model=QueueTicketResponse,
)
def qr_check_in_patient(
    request: PatientQRCheckInRequest,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> QueueTicket:
    try:
        clinic_id = decode_check_in_qr_token(request.token)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired check-in QR code",
        )

    today = date.today()

    tickets = db.scalars(
        select(QueueTicket)
        .join(Queue, QueueTicket.queue_id == Queue.id)
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .where(
            QueueTicket.patient_id == current_user.id,
            QueueTicket.source == TicketSource.ONLINE,
            QueueTicket.status == TicketStatus.WAITING,
            Doctor.clinic_id == clinic_id,
            Queue.queue_date == today,
            Queue.is_active == True,
        )
    ).all()

    if not tickets:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active waiting ticket found for this clinic",
        )

    if len(tickets) > 1:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Multiple active waiting tickets found for this clinic",
        )

    ticket = tickets[0]

    if ticket.checked_in_at is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ticket is already checked in",
        )

    ticket.checked_in_at = datetime.now(timezone.utc)
    ticket.check_in_method = CheckInMethod.QR
    db.commit()
    db.refresh(ticket)
    notify_display_update(clinic_id, background_tasks)
    return ticket


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
    background_tasks: BackgroundTasks = None,
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
    notify_display_update(doctor.clinic_id, background_tasks)
    schedule_paused_notification(queue.id, background_tasks)
    return queue


@router.patch(
    "/{queue_id}/resume",
    response_model=QueueResponse,
)
def resume_queue(
    queue_id: int,
    background_tasks: BackgroundTasks = None,
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
    notify_display_update(doctor.clinic_id, background_tasks)
    schedule_resumed_notification(queue.id, background_tasks)
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


@router.post(
    "/{queue_id}/call-next",
    response_model=QueueTicketResponse,
)
def call_next_patient(
    queue_id: int,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> QueueTicket:
    # Lock the Queue row for update before reading/reordering tickets
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

    if not queue.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is not active",
        )

    if queue.is_paused:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is paused",
        )

    # Active patient safety: check whether queue already has a CALLED or SERVING ticket
    active_ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.status.in_([TicketStatus.CALLED, TicketStatus.SERVING]),
        ).limit(1)
    )
    if active_ticket:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue already has an active patient",
        )

    # Load WAITING tickets for this queue in queue_position order
    waiting_tickets = list(
        db.scalars(
            select(QueueTicket)
            .where(
                QueueTicket.queue_id == queue.id,
                QueueTicket.status == TicketStatus.WAITING,
            )
            .order_by(QueueTicket.queue_position.asc())
        ).all()
    )

    if not waiting_tickets:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No waiting tickets",
        )

    current_max_pos = db.scalar(
        select(func.coalesce(func.max(QueueTicket.queue_position), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    ) or 0

    called_ticket: QueueTicket | None = None
    passed_ticket_ids: list[int] = []

    for ticket in waiting_tickets:
        if ticket.checked_in_at is None:
            current_max_pos += 1
            ticket.missed_turns += 1
            ticket.queue_position = current_max_pos
            if ticket.patient_id is not None:
                passed_ticket_ids.append(ticket.id)
        else:
            ticket.status = TicketStatus.CALLED
            called_ticket = ticket
            break

    if not called_ticket:
        db.commit()
        for passed_id in passed_ticket_ids:
            trigger_missed_turn_notification(passed_id)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No checked-in patient available",
        )

    db.commit()
    db.refresh(called_ticket)
    notify_display_update(doctor.clinic_id, background_tasks)
    for passed_id in passed_ticket_ids:
        schedule_missed_turn_notification(passed_id, background_tasks)
    if called_ticket.patient_id is not None:
        schedule_called_notification(called_ticket.id, doctor.room_number, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return called_ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/call",
    response_model=QueueTicketResponse,
)
def call_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
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
    notify_display_update(doctor.clinic_id, background_tasks)
    if ticket.patient_id is not None:
        schedule_called_notification(ticket.id, doctor.room_number, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/serve",
    response_model=QueueTicketResponse,
)
def serve_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
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
    notify_display_update(doctor.clinic_id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/complete",
    response_model=QueueTicketResponse,
)
def complete_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
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
    notify_display_update(doctor.clinic_id, background_tasks)
    if ticket.patient_id is not None:
        schedule_completed_notification(ticket.id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/skip",
    response_model=QueueTicketResponse,
)
def skip_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
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
    notify_display_update(doctor.clinic_id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/restore",
    response_model=QueueTicketResponse,
)
def restore_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
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
    notify_display_update(doctor.clinic_id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/cancel",
    response_model=QueueTicketResponse,
)
def cancel_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN, UserRole.PATIENT)),
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

    if current_user.role == UserRole.PATIENT:
        if ticket.patient_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot cancel another patient's ticket",
            )

    if ticket.status not in (TicketStatus.WAITING, TicketStatus.CALLED, TicketStatus.SKIPPED):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only waiting, called, or skipped tickets can be cancelled",
        )

    ticket.status = TicketStatus.CANCELLED
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/check-in",
    response_model=QueueTicketResponse,
)
def manual_check_in_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
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

    if ticket.source != TicketSource.ONLINE:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Walk-in tickets are already checked in",
        )

    if ticket.status != TicketStatus.WAITING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only waiting tickets can be checked in",
        )

    if ticket.checked_in_at is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ticket is already checked in",
        )

    ticket.checked_in_at = datetime.now(timezone.utc)
    ticket.check_in_method = CheckInMethod.RECEPTION
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks)
    return ticket


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/miss-turn",
    response_model=QueueTicketResponse,
)
def miss_turn_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
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

    if ticket.status != TicketStatus.WAITING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only waiting tickets can miss a turn",
        )

    if ticket.checked_in_at is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Checked-in ticket cannot miss a turn",
        )

    current_max_pos = db.scalar(
        select(func.coalesce(func.max(QueueTicket.queue_position), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    )
    next_queue_position = (current_max_pos or 0) + 1

    ticket.missed_turns += 1
    ticket.queue_position = next_queue_position
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks)
    if ticket.patient_id is not None:
        schedule_missed_turn_notification(ticket.id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.post(
    "/{queue_id}/join",
    response_model=QueueTicketResponse,
    status_code=status.HTTP_201_CREATED,
)
def join_queue(
    queue_id: int,
    background_tasks: BackgroundTasks = None,
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
    schedule_joined_notification(ticket.id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


@router.post(
    "/{queue_id}/walk-in",
    response_model=QueueTicketResponse,
    status_code=status.HTTP_201_CREATED,
)
def add_walk_in_patient(
    queue_id: int,
    request: WalkInPatientCreate,
    background_tasks: BackgroundTasks = None,
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
        checked_in_at=datetime.now(timezone.utc),
        check_in_method=CheckInMethod.WALK_IN,
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket
