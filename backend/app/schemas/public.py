from pydantic import BaseModel, Field


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


class PublicDisplayQueue(BaseModel):
    doctor: PublicDisplayDoctor
    specialization: PublicDisplaySpecialization
    is_paused: bool
    called_ticket: PublicDisplayTicket | None = None
    waiting_tickets: list[PublicDisplayTicket] = Field(default_factory=list)


class PublicDisplayResponse(BaseModel):
    clinic: PublicDisplayClinic
    queues: list[PublicDisplayQueue] = Field(default_factory=list)

