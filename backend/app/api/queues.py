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
from app.models.queue import Queue, ShiftStatus, SmartCallMode
from app.models.queue_ticket import CheckInMethod, QueueTicket, TicketSource, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.realtime import notify_display_update
from app.services.shift_service import ACTIVE_SHIFT_STATUSES, get_clinic_local_date
from app.services.queue_notifications import (
    check_and_trigger_approaching,
    get_active_tickets_with_four_plus_ahead,
    reset_approaching_on_requeue,
    schedule_approaching_check,
    schedule_called_notification,
    schedule_completed_notification,
    schedule_joined_notification,
    schedule_missed_turn_notification,
    schedule_paused_notification,
    schedule_restored_notification,
    schedule_resumed_notification,
    schedule_skipped_notification,
    trigger_missed_turn_notification,
)
from app.services.smart_call_timer import (
    SmartCallAdvanceResult,
    advance_smart_call_for_queue,
    clear_ticket_call_countdown,
    freeze_ticket_call_countdown,
    get_clinic_timeout_seconds,
    resume_ticket_call_countdown,
    start_ticket_call_countdown,
)
from app.schemas.queue import (
    CheckInQRResponse,
    CompleteTicketResponse,
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
    SmartCallModeUpdateRequest,
    WalkInPatientCreate,
)

router = APIRouter(
    prefix="/api/queues",
    tags=["Queues"],
)


def _build_my_queue_ticket_response(
    db: Session,
    ticket: QueueTicket,
    queue: Queue,
    doctor: Doctor,
    specialization: Specialization,
    lang: str,
    server_now: datetime | None = None,
) -> MyQueueTicketResponse:
    if ticket.status == TicketStatus.SKIPPED:
        people_ahead = 0
    else:
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
        queue_position=ticket.queue_position,
        status=ticket.status,
        created_at=ticket.created_at,
        checked_in_at=ticket.checked_in_at,
        check_in_method=ticket.check_in_method,
        people_ahead=people_ahead,
        clinic_id=doctor.clinic_id,
        called_at=ticket.called_at,
        call_deadline_at=ticket.call_deadline_at,
        paused_remaining_seconds=ticket.paused_remaining_seconds,
        is_queue_paused=bool(queue.is_paused),
        server_time=server_now or datetime.now(timezone.utc),
        doctor=MyTicketDoctorResponse(
            id=doctor.id,
            full_name=doctor.full_name,
            room_number=doctor.room_number,
            clinic_id=doctor.clinic_id,
        ),
        specialization=MyTicketSpecializationResponse(
            id=specialization.id,
            name=specialization.get_localized_name(lang),
        ),
    )


@router.get(
    "/my-ticket",
    response_model=MyQueueTicketResponse,
)
def get_my_ticket(
    include_skipped: bool = Query(
        default=False,
        description="If true, fall back to today's active-queue SKIPPED ticket when no WAITING/CALLED/SERVING ticket exists",
    ),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
    lang: str = Depends(get_language),
) -> MyQueueTicketResponse:
    result = db.execute(
        select(QueueTicket, Queue, Doctor, Specialization)
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

    if not result and include_skipped:
        result = db.execute(
            select(QueueTicket, Queue, Doctor, Specialization)
            .join(Queue, QueueTicket.queue_id == Queue.id)
            .join(Doctor, Queue.doctor_id == Doctor.id)
            .join(Specialization, Doctor.specialization_id == Specialization.id)
            .where(
                QueueTicket.patient_id == current_user.id,
                QueueTicket.status == TicketStatus.SKIPPED,
                Queue.is_active == True,
                Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
            )
            .order_by(QueueTicket.created_at.desc())
        ).first()

    if not result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active queue ticket found",
        )

    ticket, queue, doctor, specialization = result
    return _build_my_queue_ticket_response(db, ticket, queue, doctor, specialization, lang)


@router.get(
    "/my-tickets",
    response_model=list[MyQueueTicketResponse],
)
def get_my_tickets(
    include_skipped: bool = Query(
        default=False,
        description="If true, also include today's unresolved SKIPPED tickets alongside active tickets",
    ),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
    lang: str = Depends(get_language),
) -> list[MyQueueTicketResponse]:
    active_filter = QueueTicket.status.in_([
        TicketStatus.WAITING,
        TicketStatus.CALLED,
        TicketStatus.SERVING,
    ])
    status_filter = (
        active_filter | (QueueTicket.status == TicketStatus.SKIPPED)
        if include_skipped
        else active_filter
    )

    priority_order = case(
        (QueueTicket.status == TicketStatus.CALLED, 0),
        (QueueTicket.status == TicketStatus.SERVING, 1),
        (QueueTicket.status == TicketStatus.WAITING, 2),
        (QueueTicket.status == TicketStatus.SKIPPED, 3),
        else_=4,
    )

    rows = db.execute(
        select(QueueTicket, Queue, Doctor, Specialization)
        .join(Queue, QueueTicket.queue_id == Queue.id)
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .join(Specialization, Doctor.specialization_id == Specialization.id)
        .where(
            QueueTicket.patient_id == current_user.id,
            Queue.is_active == True,
            Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
            status_filter,
        )
        .order_by(
            priority_order.asc(),
            QueueTicket.created_at.asc(),
            QueueTicket.id.asc(),
        )
    ).all()

    server_now = datetime.now(timezone.utc)
    return [
        _build_my_queue_ticket_response(
            db, ticket, queue, doctor, specialization, lang, server_now=server_now
        )
        for ticket, queue, doctor, specialization in rows
    ]


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

    queue = db.scalar(select(Queue).where(Queue.id == ticket.queue_id).with_for_update())
    # Re-fetch ticket under queue lock so concurrent timer/serve transitions are serialized
    ticket = db.scalar(select(QueueTicket).where(QueueTicket.id == ticket.id))
    if not ticket or ticket.status not in (TicketStatus.WAITING, TicketStatus.CALLED, TicketStatus.SKIPPED):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ticket can no longer be cancelled",
        )
    doctor = db.scalar(select(Doctor).where(Doctor.id == queue.doctor_id)) if queue else None
    jumped_ids = get_active_tickets_with_four_plus_ahead(db, queue.id) if queue else []

    ticket.status = TicketStatus.CANCELLED
    clear_ticket_call_countdown(ticket)
    db.commit()
    db.refresh(ticket)

    if doctor and queue:
        notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    elif doctor:
        notify_display_update(doctor.clinic_id, background_tasks)
    if queue:
        schedule_approaching_check(queue.id, background_tasks, jumped_candidate_ids=jumped_ids)

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
    # Lock Doctor row to serialize concurrent Start Shift requests per doctor
    doctor = db.scalar(
        select(Doctor).where(Doctor.id == request.doctor_id).with_for_update()
    )
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

    clinic = db.scalar(select(Clinic).where(Clinic.id == doctor.clinic_id))
    target_date = request.queue_date or get_clinic_local_date(clinic)

    existing_unfinished = db.scalar(
        select(Queue)
        .where(
            Queue.doctor_id == doctor.id,
            Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
        )
        .order_by(Queue.id.desc())
    )

    if existing_unfinished:
        if existing_unfinished.is_active:
            if request.idempotent:
                return existing_unfinished
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An active shift already exists for this doctor",
            )
        # Re-open legacy/pre-finish deactivated queue row
        existing_unfinished.is_active = True
        existing_unfinished.is_paused = False
        existing_unfinished.shift_status = ShiftStatus.OPEN
        if existing_unfinished.started_at is None:
            existing_unfinished.started_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(existing_unfinished)
        notify_display_update(doctor.clinic_id, background_tasks, queue_id=existing_unfinished.id)
        return existing_unfinished

    new_queue = Queue(
        doctor_id=doctor.id,
        queue_date=target_date,
        is_paused=False,
        is_active=True,
        smart_call_mode=SmartCallMode.MANUAL,
        shift_status=ShiftStatus.OPEN,
        started_at=datetime.now(timezone.utc),
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
                Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
            )
        )
        if existing and request.idempotent:
            return existing
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An active shift already exists for this doctor",
        )

    notify_display_update(doctor.clinic_id, background_tasks, queue_id=new_queue.id)
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
            func.count(
                case((QueueTicket.status == TicketStatus.COMPLETED, QueueTicket.id))
            ).label("completed_count"),
            func.count(
                case((QueueTicket.status == TicketStatus.SKIPPED, QueueTicket.id))
            ).label("skipped_count"),
            func.count(
                case((QueueTicket.status == TicketStatus.CANCELLED, QueueTicket.id))
            ).label("cancelled_count"),
        )
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .join(Specialization, Doctor.specialization_id == Specialization.id)
        .outerjoin(QueueTicket, QueueTicket.queue_id == Queue.id)
        .where(
            Queue.is_active == True,
            Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
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
            smart_call_mode=queue.smart_call_mode,
            shift_status=queue.shift_status,
            started_at=queue.started_at,
            ended_at=queue.ended_at,
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
            completed_count=completed_count,
            skipped_count=skipped_count,
            cancelled_count=cancelled_count,
        )
        for (
            queue,
            doctor,
            specialization,
            waiting_count,
            called_count,
            serving_count,
            completed_count,
            skipped_count,
            cancelled_count,
        ) in results
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

    if request.ticket_id is not None:
        row = db.execute(
            select(QueueTicket, Queue, Doctor)
            .join(Queue, QueueTicket.queue_id == Queue.id)
            .join(Doctor, Queue.doctor_id == Doctor.id)
            .where(QueueTicket.id == request.ticket_id)
        ).first()
        if not row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No active waiting ticket found for this clinic",
            )
        ticket, ticket_queue, ticket_doctor = row
        if ticket.patient_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cannot check in another patient's ticket",
            )
        if (
            ticket_doctor.clinic_id != clinic_id
            or not ticket_queue.is_active
            or ticket_queue.shift_status not in ACTIVE_SHIFT_STATUSES
        ):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No active waiting ticket found for this clinic",
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
    else:
        tickets = db.scalars(
            select(QueueTicket)
            .join(Queue, QueueTicket.queue_id == Queue.id)
            .join(Doctor, Queue.doctor_id == Doctor.id)
            .where(
                QueueTicket.patient_id == current_user.id,
                QueueTicket.source == TicketSource.ONLINE,
                QueueTicket.status == TicketStatus.WAITING,
                Doctor.clinic_id == clinic_id,
                Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
                Queue.is_active == True,
            )
        ).all()

        if not tickets:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No active waiting ticket found for this clinic",
            )

        unchecked_tickets = [t for t in tickets if t.checked_in_at is None]
        if len(unchecked_tickets) > 1:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Multiple active waiting tickets found for this clinic. Please select a ticket to check in.",
            )

        ticket = unchecked_tickets[0] if len(unchecked_tickets) == 1 else tickets[0]

        if ticket.checked_in_at is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Ticket is already checked in",
            )

    ticket.checked_in_at = datetime.now(timezone.utc)
    ticket.check_in_method = CheckInMethod.QR
    db.commit()
    db.refresh(ticket)
    notify_display_update(clinic_id, background_tasks, queue_id=ticket.queue_id)
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
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
    queue = db.scalar(select(Queue).where(Queue.id == queue_id).with_for_update())
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
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
    pause_now = datetime.now(timezone.utc)
    called_tickets = db.scalars(
        select(QueueTicket).where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.status == TicketStatus.CALLED,
        )
    ).all()
    for called_ticket in called_tickets:
        freeze_ticket_call_countdown(called_ticket, now=pause_now)
    db.commit()
    db.refresh(queue)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
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
    queue = db.scalar(select(Queue).where(Queue.id == queue_id).with_for_update())
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
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
    resume_now = datetime.now(timezone.utc)
    called_tickets = db.scalars(
        select(QueueTicket).where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.status == TicketStatus.CALLED,
            QueueTicket.paused_remaining_seconds.is_not(None),
        )
    ).all()
    for called_ticket in called_tickets:
        resume_ticket_call_countdown(called_ticket, now=resume_now)
    db.commit()
    db.refresh(queue)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
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

    timeout_seconds = get_clinic_timeout_seconds(db, doctor.clinic_id)
    pre_jumped_ids = get_active_tickets_with_four_plus_ahead(db, queue.id)
    advance_result = advance_smart_call_for_queue(
        db,
        queue.id,
        timeout_seconds,
    )
    called_ticket = advance_result.called_ticket
    passed_ticket_ids = advance_result.passed_ticket_ids
    repositioned_any = advance_result.repositioned_any
    jumped_ids = [tid for tid in pre_jumped_ids if tid not in set(passed_ticket_ids)]

    if not called_ticket:
        db.commit()
        if repositioned_any:
            notify_display_update(doctor.clinic_id, None, queue_id=queue.id)
        for passed_id in passed_ticket_ids:
            trigger_missed_turn_notification(passed_id)
        check_and_trigger_approaching(
            queue.id,
            jumped_candidate_ids=jumped_ids,
            exclude_ticket_ids=advance_result.suppress_approaching_ticket_ids,
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No checked-in patient available",
        )

    db.commit()
    db.refresh(called_ticket)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    for passed_id in passed_ticket_ids:
        schedule_missed_turn_notification(passed_id, background_tasks)
    if called_ticket.patient_id is not None:
        schedule_called_notification(called_ticket.id, doctor.room_number, background_tasks)
    schedule_approaching_check(
        queue.id,
        background_tasks,
        jumped_candidate_ids=jumped_ids,
        exclude_ticket_ids=advance_result.suppress_approaching_ticket_ids,
    )
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
    queue = db.scalar(select(Queue).where(Queue.id == queue_id).with_for_update())
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is not active",
        )

    if queue.is_paused:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is paused",
        )

    active_ticket = db.scalar(
        select(QueueTicket)
        .where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.status.in_([TicketStatus.CALLED, TicketStatus.SERVING]),
        )
        .limit(1)
    )
    if active_ticket:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue already has an active patient",
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

    timeout_seconds = get_clinic_timeout_seconds(db, doctor.clinic_id)
    start_ticket_call_countdown(ticket, timeout_seconds)
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
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
    queue = db.scalar(select(Queue).where(Queue.id == queue_id).with_for_update())
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
    clear_ticket_call_countdown(ticket)
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket


def _get_locked_queue_and_doctor_for_staff(
    db: Session,
    queue_id: int,
    current_user: User,
) -> tuple[Queue, Doctor]:
    """Fetch a row-locked queue and doctor, enforcing clinic authorization for receptionists."""
    queue = db.scalar(select(Queue).where(Queue.id == queue_id).with_for_update())
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

    return queue, doctor


@router.patch(
    "/{queue_id}/smart-call-mode",
    response_model=QueueResponse,
)
def update_queue_smart_call_mode(
    queue_id: int,
    payload: SmartCallModeUpdateRequest,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> Queue:
    queue, doctor = _get_locked_queue_and_doctor_for_staff(db, queue_id, current_user)

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    if queue.smart_call_mode != payload.mode:
        queue.smart_call_mode = payload.mode
        db.commit()
        db.refresh(queue)
        notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)

    return queue


@router.patch(
    "/{queue_id}/stop-admissions",
    response_model=QueueResponse,
)
def stop_shift_admissions(
    queue_id: int,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> Queue:
    queue, doctor = _get_locked_queue_and_doctor_for_staff(db, queue_id, current_user)

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift is already finished",
        )
    if queue.shift_status == ShiftStatus.CLOSING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift is already closing admissions",
        )

    queue.shift_status = ShiftStatus.CLOSING
    db.commit()
    db.refresh(queue)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    return queue


@router.patch(
    "/{queue_id}/reopen-admissions",
    response_model=QueueResponse,
)
def reopen_shift_admissions(
    queue_id: int,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> Queue:
    queue, doctor = _get_locked_queue_and_doctor_for_staff(db, queue_id, current_user)

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Cannot reopen a finished shift",
        )
    if queue.shift_status == ShiftStatus.OPEN:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift admissions are already open",
        )

    queue.shift_status = ShiftStatus.OPEN
    db.commit()
    db.refresh(queue)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    return queue


@router.patch(
    "/{queue_id}/finish",
    response_model=QueueResponse,
)
def finish_shift(
    queue_id: int,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> Queue:
    queue, doctor = _get_locked_queue_and_doctor_for_staff(db, queue_id, current_user)

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift is already finished",
        )

    unresolved_active = db.scalar(
        select(QueueTicket.id)
        .where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.status.in_([
                TicketStatus.WAITING,
                TicketStatus.CALLED,
                TicketStatus.SERVING,
            ]),
        )
        .limit(1)
    )
    if unresolved_active is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Cannot finish shift while waiting, called, or serving patients remain",
        )

    queue.shift_status = ShiftStatus.FINISHED
    queue.is_active = False
    queue.is_paused = False
    queue.ended_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(queue)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    return queue


def _maybe_auto_advance_queue(
    db: Session,
    queue: Queue,
    doctor: Doctor,
) -> SmartCallAdvanceResult:
    """Trigger Smart Call handoff only in active, unpaused AUTOMATIC queues with no active patient."""
    if (
        queue.smart_call_mode != SmartCallMode.AUTOMATIC
        or not queue.is_active
        or queue.is_paused
    ):
        return SmartCallAdvanceResult()

    remaining_active = db.scalar(
        select(QueueTicket.id)
        .where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.status.in_([TicketStatus.CALLED, TicketStatus.SERVING]),
        )
        .limit(1)
    )
    if remaining_active is not None:
        return SmartCallAdvanceResult()

    timeout_seconds = get_clinic_timeout_seconds(db, doctor.clinic_id)
    return advance_smart_call_for_queue(db, queue.id, timeout_seconds)


def _commit_and_build_handoff_response(
    db: Session,
    queue: Queue,
    doctor: Doctor,
    ticket: QueueTicket,
    advance_result: SmartCallAdvanceResult,
    primary_notification_fn,
    background_tasks: BackgroundTasks = None,
    *,
    jumped_candidate_ids: list[int] | None = None,
) -> CompleteTicketResponse:
    """Commit ticket transition + optional auto-call atomically and schedule notifications."""
    auto_called_ticket = advance_result.called_ticket
    db.commit()
    db.refresh(ticket)
    if auto_called_ticket is not None:
        db.refresh(auto_called_ticket)

    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    if ticket.patient_id is not None:
        primary_notification_fn(ticket.id, background_tasks)
    for passed_id in advance_result.passed_ticket_ids:
        schedule_missed_turn_notification(passed_id, background_tasks)
    if auto_called_ticket is not None and auto_called_ticket.patient_id is not None:
        schedule_called_notification(auto_called_ticket.id, doctor.room_number, background_tasks)
    repositioned_set = set(advance_result.passed_ticket_ids)
    filtered_jumped = [
        tid for tid in (jumped_candidate_ids or []) if tid not in repositioned_set
    ]
    schedule_approaching_check(
        queue.id,
        background_tasks,
        jumped_candidate_ids=filtered_jumped,
        exclude_ticket_ids=advance_result.suppress_approaching_ticket_ids,
    )

    response = CompleteTicketResponse.model_validate(ticket)
    if auto_called_ticket is not None:
        response.auto_called_ticket = QueueTicketResponse.model_validate(auto_called_ticket)
    return response


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/complete",
    response_model=CompleteTicketResponse,
)
def complete_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> CompleteTicketResponse:
    queue, doctor = _get_locked_queue_and_doctor_for_staff(db, queue_id, current_user)

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift has already finished",
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

    jumped_ids = get_active_tickets_with_four_plus_ahead(db, queue.id)
    ticket.status = TicketStatus.COMPLETED
    ticket.completed_at = datetime.now(timezone.utc)
    # Flush COMPLETED transition before checking active tickets or running Smart Call advance
    db.flush()

    advance_result = _maybe_auto_advance_queue(db, queue, doctor)
    return _commit_and_build_handoff_response(
        db=db,
        queue=queue,
        doctor=doctor,
        ticket=ticket,
        advance_result=advance_result,
        primary_notification_fn=schedule_completed_notification,
        background_tasks=background_tasks,
        jumped_candidate_ids=jumped_ids,
    )


@router.patch(
    "/{queue_id}/tickets/{ticket_id}/skip",
    response_model=CompleteTicketResponse,
)
def skip_patient(
    queue_id: int,
    ticket_id: int,
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> CompleteTicketResponse:
    queue, doctor = _get_locked_queue_and_doctor_for_staff(db, queue_id, current_user)

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift has already finished",
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

    jumped_ids = get_active_tickets_with_four_plus_ahead(db, queue.id)
    previous_status = ticket.status
    ticket.status = TicketStatus.SKIPPED
    clear_ticket_call_countdown(ticket)
    # Flush SKIPPED transition before checking active tickets or advancing next eligible patient
    db.flush()

    # Only skipping the currently CALLED ticket triggers automatic Smart Call handoff
    advance_result = (
        _maybe_auto_advance_queue(db, queue, doctor)
        if previous_status == TicketStatus.CALLED
        else SmartCallAdvanceResult()
    )
    return _commit_and_build_handoff_response(
        db=db,
        queue=queue,
        doctor=doctor,
        ticket=ticket,
        advance_result=advance_result,
        primary_notification_fn=schedule_skipped_notification,
        background_tasks=background_tasks,
        jumped_candidate_ids=jumped_ids,
    )


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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift has already finished",
        )

    current_max_pos = db.scalar(
        select(func.coalesce(func.max(QueueTicket.queue_position), 0)).where(
            QueueTicket.queue_id == queue.id
        )
    )
    new_queue_position = (current_max_pos or 0) + 1

    ticket.status = TicketStatus.WAITING
    ticket.queue_position = new_queue_position
    db.flush()
    suppress_self = reset_approaching_on_requeue(db, queue.id, ticket)
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    if ticket.patient_id is not None:
        schedule_restored_notification(ticket.id, background_tasks)
    schedule_approaching_check(
        queue.id,
        background_tasks,
        exclude_ticket_ids=[ticket.id] if suppress_self else None,
    )
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
    queue = db.scalar(select(Queue).where(Queue.id == queue_id).with_for_update())
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift has already finished",
        )

    jumped_ids = get_active_tickets_with_four_plus_ahead(db, queue.id)
    ticket.status = TicketStatus.CANCELLED
    clear_ticket_call_countdown(ticket)
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    schedule_approaching_check(queue.id, background_tasks, jumped_candidate_ids=jumped_ids)
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift has already finished",
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
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Shift has already finished",
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

    jumped_ids = [
        tid
        for tid in get_active_tickets_with_four_plus_ahead(db, queue.id)
        if tid != ticket.id
    ]
    ticket.missed_turns += 1
    ticket.queue_position = next_queue_position
    db.flush()
    suppress_self = reset_approaching_on_requeue(db, queue.id, ticket)
    db.commit()
    db.refresh(ticket)
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    if ticket.patient_id is not None:
        schedule_missed_turn_notification(ticket.id, background_tasks)
    schedule_approaching_check(
        queue.id,
        background_tasks,
        jumped_candidate_ids=jumped_ids,
        exclude_ticket_ids=[ticket.id] if suppress_self else None,
    )
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
    # Consistent lock order: lock the patient User row FIRST to serialize concurrent
    # bookings across different doctors/specializations, then lock the target Queue row
    # for concurrency-safe ticket number and position generation.
    db.scalar(
        select(User).where(User.id == current_user.id).with_for_update()
    )

    queue = db.scalar(
        select(Queue).where(Queue.id == queue_id).with_for_update()
    )
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Queue not found",
        )

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    if queue.shift_status == ShiftStatus.CLOSING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue closed for new patients",
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

    unresolved_statuses = [
        TicketStatus.WAITING,
        TicketStatus.CALLED,
        TicketStatus.SERVING,
        TicketStatus.SKIPPED,
    ]

    # Check whether current_user already has an unresolved ticket in this exact queue
    active_ticket = db.scalar(
        select(QueueTicket).where(
            QueueTicket.queue_id == queue.id,
            QueueTicket.patient_id == current_user.id,
            QueueTicket.status.in_(unresolved_statuses),
        )
    )
    if active_ticket:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Patient already has an active ticket in this queue",
        )

    # Enforce at most one unresolved ticket per patient, specialization, clinic, and active shift
    same_spec_ticket = db.scalar(
        select(QueueTicket)
        .join(Queue, QueueTicket.queue_id == Queue.id)
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .where(
            QueueTicket.patient_id == current_user.id,
            Doctor.specialization_id == doctor.specialization_id,
            Doctor.clinic_id == doctor.clinic_id,
            Queue.is_active == True,
            Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
            QueueTicket.status.in_(unresolved_statuses),
        )
        .limit(1)
    )
    if same_spec_ticket:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Patient already has an active ticket in this specialization",
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
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
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

    if not queue.is_active or queue.shift_status == ShiftStatus.FINISHED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue is inactive",
        )

    if queue.shift_status == ShiftStatus.CLOSING:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Queue closed for new patients",
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
    notify_display_update(doctor.clinic_id, background_tasks, queue_id=queue.id)
    schedule_approaching_check(queue.id, background_tasks)
    return ticket
