from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_roles
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.schemas.catalog import DoctorResponse, SpecializationResponse
from app.schemas.queue import QueueResponse

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
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> list[Specialization]:
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

    specializations = db.scalars(
        select(Specialization)
        .where(Specialization.clinic_id == clinic_id)
        .order_by(Specialization.name.asc())
    ).all()

    return list(specializations)


@router.get(
    "/doctors",
    response_model=list[DoctorResponse],
)
def get_doctors(
    clinic_id: int,
    specialization_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> list[Doctor]:
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

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

    doctors = db.scalars(
        select(Doctor)
        .where(
            Doctor.clinic_id == clinic_id,
            Doctor.specialization_id == specialization_id,
            Doctor.is_active == True,
        )
        .order_by(Doctor.full_name.asc())
    ).all()

    return list(doctors)


@router.get(
    "/doctors/{doctor_id}/queue",
    response_model=QueueResponse,
)
def get_doctor_queue(
    doctor_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> Queue:
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
        select(Queue).where(
            Queue.doctor_id == doctor_id,
            Queue.queue_date == date.today(),
            Queue.is_active == True,
        )
    )
    if not queue:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active queue for this doctor today",
        )

    return queue
