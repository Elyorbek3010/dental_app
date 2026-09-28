from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_roles
from app.core.security import get_password_hash
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.queue import Queue
from app.models.queue_ticket import QueueTicket, TicketStatus
from app.models.specialization import Specialization
from app.models.user import User, UserRole
from app.schemas.admin import (
    AdminAnalyticsOverview,
    AdminClinicResponse,
    AdminClinicUpdate,
    AdminDoctorCreate,
    AdminDoctorResponse,
    AdminDoctorUpdate,
    AdminReceptionistCreate,
    AdminReceptionistResponse,
    AdminReceptionistUpdate,
    AdminSpecializationCreate,
    AdminSpecializationResponse,
    AdminSpecializationUpdate,
    DoctorQueueSummary,
)

router = APIRouter(
    prefix="/api/admin",
    tags=["Admin"],
    dependencies=[Depends(require_roles(UserRole.ADMIN))],
)


def _get_admin_clinic_id(admin: User) -> int:
    if not admin.clinic_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin is not assigned to any clinic",
        )
    return admin.clinic_id


# =========================================================================
# Clinic Information
# =========================================================================

@router.get("/clinic", response_model=AdminClinicResponse)
def get_clinic_info(
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> Clinic:
    clinic_id = _get_admin_clinic_id(admin)
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )
    return clinic


@router.patch("/clinic", response_model=AdminClinicResponse)
def update_clinic_info(
    payload: AdminClinicUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> Clinic:
    clinic_id = _get_admin_clinic_id(admin)
    clinic = db.scalar(select(Clinic).where(Clinic.id == clinic_id))
    if not clinic:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Clinic not found",
        )

    clinic.name = payload.name.strip()
    db.commit()
    db.refresh(clinic)
    return clinic


# =========================================================================
# Specializations Management
# =========================================================================

@router.get("/specializations", response_model=list[AdminSpecializationResponse])
def list_specializations(
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> list[Specialization]:
    clinic_id = _get_admin_clinic_id(admin)
    specs = db.scalars(
        select(Specialization)
        .where(Specialization.clinic_id == clinic_id)
        .order_by(Specialization.name_uz.asc())
    ).all()
    return list(specs)


@router.post("/specializations", response_model=AdminSpecializationResponse, status_code=status.HTTP_201_CREATED)
def create_specialization(
    payload: AdminSpecializationCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> Specialization:
    clinic_id = _get_admin_clinic_id(admin)
    name_uz = payload.name_uz.strip()
    if not name_uz:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="name_uz cannot be empty",
        )

    spec = Specialization(
        clinic_id=clinic_id,
        name_uz=name_uz,
        name_ru=payload.name_ru.strip() if payload.name_ru else None,
        name_en=payload.name_en.strip() if payload.name_en else None,
        is_active=True,
    )
    db.add(spec)
    db.commit()
    db.refresh(spec)
    return spec


@router.patch("/specializations/{specialization_id}", response_model=AdminSpecializationResponse)
def update_specialization(
    specialization_id: int,
    payload: AdminSpecializationUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> Specialization:
    clinic_id = _get_admin_clinic_id(admin)
    spec = db.scalar(
        select(Specialization).where(
            Specialization.id == specialization_id,
            Specialization.clinic_id == clinic_id,
        )
    )
    if not spec:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Specialization not found",
        )

    if payload.name_uz is not None:
        trimmed = payload.name_uz.strip()
        if not trimmed:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="name_uz cannot be empty",
            )
        spec.name_uz = trimmed

    if payload.name_ru is not None:
        spec.name_ru = payload.name_ru.strip() if payload.name_ru.strip() else None

    if payload.name_en is not None:
        spec.name_en = payload.name_en.strip() if payload.name_en.strip() else None

    if payload.is_active is not None:
        spec.is_active = payload.is_active

    db.commit()
    db.refresh(spec)
    return spec


# =========================================================================
# Doctors Management
# =========================================================================

@router.get("/doctors", response_model=list[AdminDoctorResponse])
def list_doctors(
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> list[AdminDoctorResponse]:
    clinic_id = _get_admin_clinic_id(admin)
    results = db.execute(
        select(Doctor, Specialization)
        .outerjoin(Specialization, Doctor.specialization_id == Specialization.id)
        .where(Doctor.clinic_id == clinic_id)
        .order_by(Doctor.full_name.asc())
    ).all()

    doctor_list: list[AdminDoctorResponse] = []
    for doc, spec in results:
        doctor_list.append(
            AdminDoctorResponse(
                id=doc.id,
                clinic_id=doc.clinic_id,
                specialization_id=doc.specialization_id,
                full_name=doc.full_name,
                room_number=doc.room_number,
                is_active=doc.is_active,
                specialization_name_uz=spec.name_uz if spec else None,
                specialization_name_ru=spec.name_ru if spec else None,
                specialization_name_en=spec.name_en if spec else None,
            )
        )
    return doctor_list


@router.post("/doctors", response_model=AdminDoctorResponse, status_code=status.HTTP_201_CREATED)
def create_doctor(
    payload: AdminDoctorCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> AdminDoctorResponse:
    clinic_id = _get_admin_clinic_id(admin)
    spec = db.scalar(
        select(Specialization).where(
            Specialization.id == payload.specialization_id,
            Specialization.clinic_id == clinic_id,
        )
    )
    if not spec:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Specialization not found in this clinic",
        )

    full_name = payload.full_name.strip()
    if not full_name:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="full_name cannot be empty",
        )

    doctor = Doctor(
        clinic_id=clinic_id,
        specialization_id=payload.specialization_id,
        full_name=full_name,
        room_number=payload.room_number.strip() if payload.room_number else None,
        is_active=payload.is_active,
    )
    db.add(doctor)
    db.commit()
    db.refresh(doctor)

    return AdminDoctorResponse(
        id=doctor.id,
        clinic_id=doctor.clinic_id,
        specialization_id=doctor.specialization_id,
        full_name=doctor.full_name,
        room_number=doctor.room_number,
        is_active=doctor.is_active,
        specialization_name_uz=spec.name_uz,
        specialization_name_ru=spec.name_ru,
        specialization_name_en=spec.name_en,
    )


@router.patch("/doctors/{doctor_id}", response_model=AdminDoctorResponse)
def update_doctor(
    doctor_id: int,
    payload: AdminDoctorUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> AdminDoctorResponse:
    clinic_id = _get_admin_clinic_id(admin)
    doctor = db.scalar(
        select(Doctor).where(
            Doctor.id == doctor_id,
            Doctor.clinic_id == clinic_id,
        )
    )
    if not doctor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Doctor not found",
        )

    if payload.specialization_id is not None:
        spec = db.scalar(
            select(Specialization).where(
                Specialization.id == payload.specialization_id,
                Specialization.clinic_id == clinic_id,
            )
        )
        if not spec:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Specialization not found in this clinic",
            )
        doctor.specialization_id = payload.specialization_id

    if payload.full_name is not None:
        trimmed = payload.full_name.strip()
        if not trimmed:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="full_name cannot be empty",
            )
        doctor.full_name = trimmed

    if payload.room_number is not None:
        doctor.room_number = payload.room_number.strip() if payload.room_number.strip() else None

    if payload.is_active is not None:
        doctor.is_active = payload.is_active

    db.commit()
    db.refresh(doctor)

    spec = db.scalar(select(Specialization).where(Specialization.id == doctor.specialization_id))

    return AdminDoctorResponse(
        id=doctor.id,
        clinic_id=doctor.clinic_id,
        specialization_id=doctor.specialization_id,
        full_name=doctor.full_name,
        room_number=doctor.room_number,
        is_active=doctor.is_active,
        specialization_name_uz=spec.name_uz if spec else None,
        specialization_name_ru=spec.name_ru if spec else None,
        specialization_name_en=spec.name_en if spec else None,
    )


# =========================================================================
# Receptionists Management
# =========================================================================

@router.get("/receptionists", response_model=list[AdminReceptionistResponse])
def list_receptionists(
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> list[User]:
    clinic_id = _get_admin_clinic_id(admin)
    users = db.scalars(
        select(User)
        .where(
            User.clinic_id == clinic_id,
            User.role == UserRole.RECEPTIONIST,
        )
        .order_by(User.full_name.asc())
    ).all()
    return list(users)


@router.post("/receptionists", response_model=AdminReceptionistResponse, status_code=status.HTTP_201_CREATED)
def create_receptionist(
    payload: AdminReceptionistCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> User:
    clinic_id = _get_admin_clinic_id(admin)
    phone = payload.phone.strip()
    full_name = payload.full_name.strip()
    password = payload.password.strip()

    if not phone or not full_name or not password:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Required fields cannot be empty",
        )

    # Check unique phone
    existing_user = db.scalar(select(User).where(User.phone == phone))
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Phone number is already registered",
        )

    user = User(
        clinic_id=clinic_id,
        full_name=full_name,
        phone=phone,
        hashed_password=get_password_hash(password),
        role=UserRole.RECEPTIONIST,
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.patch("/receptionists/{user_id}", response_model=AdminReceptionistResponse)
def update_receptionist(
    user_id: int,
    payload: AdminReceptionistUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> User:
    clinic_id = _get_admin_clinic_id(admin)
    user = db.scalar(
        select(User).where(
            User.id == user_id,
            User.clinic_id == clinic_id,
            User.role == UserRole.RECEPTIONIST,
        )
    )
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receptionist not found",
        )

    if payload.phone is not None:
        trimmed_phone = payload.phone.strip()
        if not trimmed_phone:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Phone cannot be empty",
            )
        if trimmed_phone != user.phone:
            conflict = db.scalar(select(User).where(User.phone == trimmed_phone))
            if conflict:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Phone number is already registered",
                )
            user.phone = trimmed_phone

    if payload.full_name is not None:
        trimmed_name = payload.full_name.strip()
        if not trimmed_name:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Full name cannot be empty",
            )
        user.full_name = trimmed_name

    if payload.password is not None and payload.password.strip():
        user.hashed_password = get_password_hash(payload.password.strip())

    if payload.is_active is not None:
        user.is_active = payload.is_active

    db.commit()
    db.refresh(user)
    return user


# =========================================================================
# Analytics / Overview
# =========================================================================

@router.get("/analytics/overview", response_model=AdminAnalyticsOverview)
def get_analytics_overview(
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(UserRole.ADMIN)),
) -> AdminAnalyticsOverview:
    clinic_id = _get_admin_clinic_id(admin)
    today = date.today()

    # Active and total counts
    total_doctors = db.scalar(
        select(func.count(Doctor.id)).where(Doctor.clinic_id == clinic_id)
    ) or 0

    active_doctors = db.scalar(
        select(func.count(Doctor.id)).where(
            Doctor.clinic_id == clinic_id,
            Doctor.is_active == True,
        )
    ) or 0

    active_specs = db.scalar(
        select(func.count(Specialization.id)).where(
            Specialization.clinic_id == clinic_id,
            Specialization.is_active == True,
        )
    ) or 0

    active_receptionists = db.scalar(
        select(func.count(User.id)).where(
            User.clinic_id == clinic_id,
            User.role == UserRole.RECEPTIONIST,
            User.is_active == True,
        )
    ) or 0

    # Today's queues in this clinic
    today_queues = db.scalars(
        select(Queue)
        .join(Doctor, Queue.doctor_id == Doctor.id)
        .where(
            Doctor.clinic_id == clinic_id,
            Queue.queue_date == today,
            Queue.is_active == True,
        )
    ).all()
    today_opened_queues = len(today_queues)
    queue_ids = [q.id for q in today_queues]

    # Tickets breakdown today
    if queue_ids:
        ticket_counts = db.execute(
            select(QueueTicket.status, func.count(QueueTicket.id))
            .where(QueueTicket.queue_id.in_(queue_ids))
            .group_by(QueueTicket.status)
        ).all()
        status_map = {row[0]: row[1] for row in ticket_counts}
    else:
        status_map = {}

    waiting_count = status_map.get(TicketStatus.WAITING, 0)
    called_count = status_map.get(TicketStatus.CALLED, 0)
    serving_count = status_map.get(TicketStatus.SERVING, 0)
    completed_count = status_map.get(TicketStatus.COMPLETED, 0)
    skipped_count = status_map.get(TicketStatus.SKIPPED, 0)
    cancelled_count = status_map.get(TicketStatus.CANCELLED, 0)
    total_tickets = sum(status_map.values())

    # Doctors queue summaries for today
    doctors_query = db.execute(
        select(Doctor, Specialization, Queue)
        .outerjoin(Specialization, Doctor.specialization_id == Specialization.id)
        .outerjoin(
            Queue,
            (Queue.doctor_id == Doctor.id)
            & (Queue.queue_date == today)
            & (Queue.is_active == True),
        )
        .where(Doctor.clinic_id == clinic_id)
        .order_by(Doctor.full_name.asc())
    ).all()

    doctor_summaries: list[DoctorQueueSummary] = []
    for doc, spec, q in doctors_query:
        if q:
            # count tickets for this queue
            doc_tickets = db.execute(
                select(QueueTicket.status, func.count(QueueTicket.id))
                .where(QueueTicket.queue_id == q.id)
                .group_by(QueueTicket.status)
            ).all()
            d_map = {r[0]: r[1] for r in doc_tickets}
            d_total = sum(d_map.values())
            d_wait = d_map.get(TicketStatus.WAITING, 0)
            d_serv = d_map.get(TicketStatus.SERVING, 0)
            d_comp = d_map.get(TicketStatus.COMPLETED, 0)
        else:
            d_total = 0
            d_wait = 0
            d_serv = 0
            d_comp = 0

        doctor_summaries.append(
            DoctorQueueSummary(
                doctor_id=doc.id,
                doctor_name=doc.full_name,
                room_number=doc.room_number,
                specialization_name=spec.name_uz if spec else "-",
                has_queue_today=q is not None,
                queue_is_active=q.is_active if q else False,
                total_tickets=d_total,
                waiting_tickets=d_wait,
                serving_tickets=d_serv,
                completed_tickets=d_comp,
            )
        )

    return AdminAnalyticsOverview(
        active_doctors_count=active_doctors,
        total_doctors_count=total_doctors,
        active_specializations_count=active_specs,
        active_receptionists_count=active_receptionists,
        today_opened_queues_count=today_opened_queues,
        today_tickets_total=total_tickets,
        today_tickets_waiting=waiting_count,
        today_tickets_called=called_count,
        today_tickets_serving=serving_count,
        today_tickets_completed=completed_count,
        today_tickets_skipped=skipped_count,
        today_tickets_cancelled=cancelled_count,
        doctors_today=doctor_summaries,
    )
