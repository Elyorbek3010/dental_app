from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

from app.models.queue_ticket import TicketSource, TicketStatus


class WalkInPatientCreate(BaseModel):
    patient_name: str = Field(..., min_length=2, max_length=255)
    patient_phone: str | None = Field(default=None, max_length=30)


class QueueResponse(BaseModel):
    id: int
    doctor_id: int
    queue_date: date
    is_paused: bool
    is_active: bool

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

    model_config = ConfigDict(from_attributes=True)


class MyTicketDoctorResponse(BaseModel):
    id: int
    full_name: str
    room_number: str | None = None

    model_config = ConfigDict(from_attributes=True)


class MyTicketSpecializationResponse(BaseModel):
    id: int
    name: str

    model_config = ConfigDict(from_attributes=True)


class MyQueueTicketResponse(BaseModel):
    id: int
    queue_id: int
    ticket_number: int
    status: TicketStatus
    created_at: datetime
    people_ahead: int
    doctor: MyTicketDoctorResponse
    specialization: MyTicketSpecializationResponse

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
    doctor: ReceptionQueueDoctorResponse
    specialization: ReceptionQueueSpecializationResponse
    waiting_count: int
    called_count: int
    serving_count: int

    model_config = ConfigDict(from_attributes=True)

