from datetime import date, datetime, timezone

from pydantic import BaseModel, ConfigDict, Field

from app.models.queue import ShiftStatus, SmartCallMode
from app.models.queue_ticket import CheckInMethod, TicketSource, TicketStatus


class WalkInPatientCreate(BaseModel):
    patient_name: str = Field(..., min_length=2, max_length=255)
    patient_phone: str | None = Field(default=None, max_length=30)


class QueueCreateRequest(BaseModel):
    doctor_id: int = Field(..., description="ID of the doctor to open the queue for")
    queue_date: date | None = Field(
        default=None,
        description="Target queue date (defaults to today)",
    )
    idempotent: bool = Field(
        default=False,
        description="If True, return existing active queue instead of 409 Conflict",
    )


class QueueResponse(BaseModel):
    id: int
    doctor_id: int
    queue_date: date
    is_paused: bool
    is_active: bool
    smart_call_mode: SmartCallMode = SmartCallMode.MANUAL
    shift_status: ShiftStatus = ShiftStatus.OPEN
    started_at: datetime | None = None
    ended_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)


class SmartCallModeUpdateRequest(BaseModel):
    mode: SmartCallMode = Field(..., description="Smart Call mode: MANUAL or AUTOMATIC")


class DoctorQueuePreviewResponse(BaseModel):
    id: int
    queue_id: int
    doctor_id: int
    queue_date: date
    is_paused: bool
    is_active: bool
    shift_status: ShiftStatus = ShiftStatus.OPEN
    started_at: datetime | None = None
    waiting_count: int
    called_count: int
    serving_count: int
    estimated_position_if_joined: int

    model_config = ConfigDict(from_attributes=True)


class QueueTicketResponse(BaseModel):
    id: int
    queue_id: int
    patient_id: int | None = None
    ticket_number: int
    queue_position: int
    patient_name: str
    patient_phone: str | None = None
    source: TicketSource
    status: TicketStatus
    created_at: datetime
    checked_in_at: datetime | None = None
    check_in_method: CheckInMethod | None = None
    missed_turns: int = 0
    called_at: datetime | None = None
    call_deadline_at: datetime | None = None
    paused_remaining_seconds: int | None = None
    completed_at: datetime | None = None
    server_time: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    model_config = ConfigDict(from_attributes=True)


class CompleteTicketResponse(QueueTicketResponse):
    auto_called_ticket: QueueTicketResponse | None = None


class MyTicketDoctorResponse(BaseModel):
    id: int
    full_name: str
    room_number: str | None = None
    clinic_id: int | None = None

    model_config = ConfigDict(from_attributes=True)


class MyTicketSpecializationResponse(BaseModel):
    id: int
    name: str

    model_config = ConfigDict(from_attributes=True)


class MyQueueTicketResponse(BaseModel):
    id: int
    queue_id: int
    ticket_number: int
    queue_position: int | None = None
    status: TicketStatus
    created_at: datetime
    people_ahead: int
    doctor: MyTicketDoctorResponse
    specialization: MyTicketSpecializationResponse
    checked_in_at: datetime | None = None
    check_in_method: CheckInMethod | None = None
    clinic_id: int | None = None
    called_at: datetime | None = None
    call_deadline_at: datetime | None = None
    paused_remaining_seconds: int | None = None
    is_queue_paused: bool = False
    server_time: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    model_config = ConfigDict(from_attributes=True)


class QueueStatusResponse(BaseModel):
    queue_id: int
    doctor_id: int
    is_paused: bool
    waiting_count: int


class ReceptionQueueDoctorResponse(BaseModel):
    id: int
    full_name: str
    room_number: str | None = None

    model_config = ConfigDict(from_attributes=True)


class ReceptionQueueSpecializationResponse(BaseModel):
    id: int
    name: str

    model_config = ConfigDict(from_attributes=True)


class ReceptionQueueOverviewResponse(BaseModel):
    queue_id: int
    queue_date: date
    is_paused: bool
    is_active: bool
    smart_call_mode: SmartCallMode = SmartCallMode.MANUAL
    shift_status: ShiftStatus = ShiftStatus.OPEN
    started_at: datetime | None = None
    ended_at: datetime | None = None
    doctor: ReceptionQueueDoctorResponse
    specialization: ReceptionQueueSpecializationResponse
    waiting_count: int
    called_count: int
    serving_count: int
    completed_count: int = 0
    skipped_count: int = 0
    cancelled_count: int = 0

    model_config = ConfigDict(from_attributes=True)


class CheckInQRResponse(BaseModel):
    token: str
    expires_in_seconds: int


class PatientQRCheckInRequest(BaseModel):
    token: str = Field(..., min_length=1)
    ticket_id: int | None = Field(default=None, gt=0)



