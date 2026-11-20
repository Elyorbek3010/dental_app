from datetime import date, datetime
from pydantic import BaseModel, ConfigDict, Field

from app.models.queue import ShiftStatus, SmartCallMode


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
    smart_call_timeout_seconds: int
    timezone: str = "Asia/Tashkent"


class AdminClinicUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    smart_call_timeout_seconds: int | None = Field(default=None, ge=15, le=1800)
    timezone: str | None = Field(default=None, min_length=1, max_length=64)


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


# --- Doctor Performance & Shift History Schemas ---
class DoctorPerformanceSummary(BaseModel):
    completed_today: int
    completed_this_week: int
    completed_this_month: int
    completed_this_year: int
    completed_all_time: int
    completed_in_selected_range: int
    legacy_unattributed_completed_count: int
    total_shifts: int
    active_shifts: int
    finished_shifts: int


class DoctorPerformanceItem(BaseModel):
    doctor_id: int
    doctor_name: str
    specialization_id: int | None = None
    specialization_name: str
    room_number: str | None = None
    is_active: bool
    current_shift_status: str
    completed_today: int
    completed_this_week: int
    completed_this_month: int
    completed_this_year: int
    completed_all_time: int
    completed_in_selected_range: int
    legacy_unattributed_completed_count: int
    shifts_count: int
    avg_shift_duration_minutes: float | None = None


class DoctorShiftHistoryItem(BaseModel):
    queue_id: int
    doctor_id: int
    doctor_name: str
    specialization_id: int | None = None
    specialization_name: str
    room_number: str | None = None
    queue_date: date
    shift_status: ShiftStatus
    is_paused: bool
    smart_call_mode: SmartCallMode
    started_at: datetime | None = None
    ended_at: datetime | None = None
    duration_seconds: int | None = None
    total_tickets: int
    completed_count: int
    waiting_count: int
    called_count: int
    serving_count: int
    skipped_count: int
    cancelled_count: int


class AdminDoctorPerformanceResponse(BaseModel):
    clinic_id: int
    clinic_name: str
    clinic_timezone: str
    period: str
    date_from: date | None = None
    date_to: date | None = None
    generated_at: datetime
    summary: DoctorPerformanceSummary
    doctors: list[DoctorPerformanceItem]
    shifts: list[DoctorShiftHistoryItem]
