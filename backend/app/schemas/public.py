from datetime import datetime, timezone

from pydantic import BaseModel, Field

from app.models.queue import ShiftStatus


class PublicDisplayClinic(BaseModel):
    id: int
    name: str


class PublicDisplayDoctor(BaseModel):
    id: int
    full_name: str
    room_number: str | None = None


class PublicDisplaySpecialization(BaseModel):
    id: int
    name: str


class PublicDisplayTicket(BaseModel):
    ticket_number: int
    called_at: datetime | None = None
    call_deadline_at: datetime | None = None
    paused_remaining_seconds: int | None = None


class PublicDisplayQueue(BaseModel):
    doctor: PublicDisplayDoctor
    specialization: PublicDisplaySpecialization
    is_paused: bool
    shift_status: ShiftStatus = ShiftStatus.OPEN
    called_ticket: PublicDisplayTicket | None = None
    waiting_tickets: list[PublicDisplayTicket] = Field(default_factory=list)


class PublicDisplayResponse(BaseModel):
    clinic: PublicDisplayClinic
    queues: list[PublicDisplayQueue] = Field(default_factory=list)
    server_time: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

