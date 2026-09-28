from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


# --- Specialization Schemas ---
class AdminSpecializationCreate(BaseModel):
    name_uz: str = Field(..., min_length=1, max_length=100)
    name_ru: str | None = Field(default=None, max_length=100)
    name_en: str | None = Field(default=None, max_length=100)


class AdminSpecializationUpdate(BaseModel):
    name_uz: str | None = Field(default=None, min_length=1, max_length=100)
    name_ru: str | None = Field(default=None, max_length=100)
    name_en: str | None = Field(default=None, max_length=100)
    is_active: bool | None = None


class AdminSpecializationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    clinic_id: int
    name_uz: str
    name_ru: str | None = None
    name_en: str | None = None
    is_active: bool


# --- Doctor Schemas ---
class AdminDoctorCreate(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=255)
    specialization_id: int
    room_number: str | None = Field(default=None, max_length=50)
    is_active: bool = True


class AdminDoctorUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=1, max_length=255)
    specialization_id: int | None = None
    room_number: str | None = Field(default=None, max_length=50)
    is_active: bool | None = None


class AdminDoctorResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    clinic_id: int
    specialization_id: int
    full_name: str
    room_number: str | None = None
    is_active: bool
    specialization_name_uz: str | None = None
    specialization_name_ru: str | None = None
    specialization_name_en: str | None = None


# --- Receptionist Schemas ---
class AdminReceptionistCreate(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=255)
    phone: str = Field(..., min_length=4, max_length=30)
    password: str = Field(..., min_length=6, max_length=100)


class AdminReceptionistUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=1, max_length=255)
    phone: str | None = Field(default=None, min_length=4, max_length=30)
    password: str | None = Field(default=None, min_length=6, max_length=100)
    is_active: bool | None = None


class AdminReceptionistResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    clinic_id: int | None = None
    full_name: str
    phone: str
    role: str
    is_active: bool
    created_at: datetime


# --- Clinic Schemas ---
class AdminClinicResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str


class AdminClinicUpdate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)


# --- Analytics Schemas ---
class DoctorQueueSummary(BaseModel):
    doctor_id: int
    doctor_name: str
    room_number: str | None = None
    specialization_name: str
    has_queue_today: bool
    queue_is_active: bool
    total_tickets: int
    waiting_tickets: int
    serving_tickets: int
    completed_tickets: int


class AdminAnalyticsOverview(BaseModel):
    active_doctors_count: int
    total_doctors_count: int
    active_specializations_count: int
    active_receptionists_count: int
    today_opened_queues_count: int
    today_tickets_total: int
    today_tickets_waiting: int
    today_tickets_called: int
    today_tickets_serving: int
    today_tickets_completed: int
    today_tickets_skipped: int
    today_tickets_cancelled: int
    doctors_today: list[DoctorQueueSummary]
