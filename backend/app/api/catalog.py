from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, get_language, require_roles
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue, ShiftStatus
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.schemas.catalog import DoctorResponse, SpecializationResponse
from app.schemas.queue import DoctorQueuePreviewResponse
from app.services.shift_service import ACTIVE_SHIFT_STATUSES

router = APIRouter(
    prefix="/api/catalog",
    tags=["Catalog"],
)


@router.get(
    "/specializations",
    response_model=list[SpecializationResponse],
)
def get_specializations(
    clinic_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT, UserRole.RECEPTIONIST, UserRole.ADMIN)),
    lang: str = Depends(get_language),
) -> list[SpecializationResponse]:
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

    order_col = Specialization.name_uz
    if lang == "ru":
        order_col = func.coalesce(Specialization.name_ru, Specialization.name_uz)
    elif lang == "en":
        order_col = func.coalesce(Specialization.name_en, Specialization.name_uz)

    specializations = db.scalars(
        select(Specialization)
        .where(
            Specialization.clinic_id == clinic_id,
            Specialization.is_active == True,
        )
        .order_by(order_col.asc())
    ).all()

    return [
        SpecializationResponse(
            id=s.id,
            clinic_id=s.clinic_id,
            name=s.get_localized_name(lang),
        )
        for s in specializations
    ]


@router.get(
    "/doctors",
    response_model=list[DoctorResponse],
)
def get_doctors(
    clinic_id: int,
    specialization_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT, UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> list[Doctor]:
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

    query = select(Doctor).where(
        Doctor.clinic_id == clinic_id,
        Doctor.is_active == True,
    )

    if specialization_id is not None:
        specialization = db.scalar(
            select(Specialization).where(Specialization.id == specialization_id)
        )
        if not specialization:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Specialization not found",
            )

        if specialization.clinic_id != clinic_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Specialization does not belong to this clinic",
            )
        query = query.where(Doctor.specialization_id == specialization_id)

    doctors = db.scalars(
        query.order_by(Doctor.full_name.asc())
    ).all()

    return list(doctors)


@router.get(
    "/doctors/{doctor_id}/queue",
    response_model=DoctorQueuePreviewResponse,
)
def get_doctor_queue(
    doctor_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT, UserRole.RECEPTIONIST, UserRole.ADMIN)),
) -> DoctorQueuePreviewResponse:
    doctor = db.scalar(select(Doctor).where(Doctor.id == doctor_id))
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if not doctor.is_active:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Doctor is inactive",
        )

    queue = db.scalar(
        select(Queue)
        .where(
            Queue.doctor_id == doctor_id,
            Queue.is_active == True,
            Queue.shift_status.in_(ACTIVE_SHIFT_STATUSES),
        )
        .order_by(Queue.id.desc())
    )
    if not queue:
        # Preserve visibility of non-finished inactive pre-queue row if created for today
        queue = db.scalar(
            select(Queue)
            .where(
                Queue.doctor_id == doctor_id,
                Queue.queue_date == date.today(),
                Queue.shift_status != ShiftStatus.FINISHED,
            )
            .order_by(Queue.id.desc())
        )
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active queue for this doctor today",
        )

    counts = db.execute(
        select(
            func.count(
                case((QueueTicket.status == TicketStatus.WAITING, QueueTicket.id))
            ).label("waiting_count"),
            func.count(
                case((QueueTicket.status == TicketStatus.CALLED, QueueTicket.id))
            ).label("called_count"),
            func.count(
                case((QueueTicket.status == TicketStatus.SERVING, QueueTicket.id))
            ).label("serving_count"),
            func.coalesce(func.max(QueueTicket.queue_position), 0).label("max_pos"),
        ).where(QueueTicket.queue_id == queue.id)
    ).one()

    return DoctorQueuePreviewResponse(
        id=queue.id,
        queue_id=queue.id,
        doctor_id=queue.doctor_id,
        queue_date=queue.queue_date,
        is_paused=queue.is_paused,
        is_active=queue.is_active,
        shift_status=queue.shift_status,
        started_at=queue.started_at,
        waiting_count=counts.waiting_count,
        called_count=counts.called_count,
        serving_count=counts.serving_count,
        estimated_position_if_joined=counts.max_pos + 1,
    )
