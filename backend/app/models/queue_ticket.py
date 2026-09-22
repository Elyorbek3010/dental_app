from datetime import datetime
from enum import Enum

from sqlalchemy import DateTime, Enum as SAEnum, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class TicketStatus(str, Enum):
    WAITING = "WAITING"
    CALLED = "CALLED"
    SERVING = "SERVING"
    COMPLETED = "COMPLETED"
    SKIPPED = "SKIPPED"
    CANCELLED = "CANCELLED"


class TicketSource(str, Enum):
    ONLINE = "ONLINE"
    WALK_IN = "WALK_IN"


class QueueTicket(Base):
    __tablename__ = "queue_tickets"
    __table_args__ = (
        UniqueConstraint("queue_id", "ticket_number", name="uq_queue_ticket_number"),
        UniqueConstraint("queue_id", "queue_position", name="uq_queue_ticket_position"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    queue_id: Mapped[int] = mapped_column(
        ForeignKey("queues.id"),
        nullable=False,
        index=True,
    )

    patient_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id"),
        nullable=True,
        index=True,
    )

    ticket_number: Mapped[int] = mapped_column(
        nullable=False,
    )

    queue_position: Mapped[int] = mapped_column(
        nullable=False,
    )

    patient_name: Mapped[str] = mapped_column(
        String(255),
        nullable=False,
    )

    patient_phone: Mapped[str | None] = mapped_column(
        String(30),
        nullable=True,
    )

    source: Mapped[TicketSource] = mapped_column(
        SAEnum(TicketSource),
        nullable=False,
    )

    status: Mapped[TicketStatus] = mapped_column(
        SAEnum(TicketStatus),
        nullable=False,
        default=TicketStatus.WAITING,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
