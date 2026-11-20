from datetime import datetime
from enum import Enum

from sqlalchemy import CheckConstraint, DateTime, Enum as SAEnum, ForeignKey, Index, Integer, String, UniqueConstraint, func, text
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


class CheckInMethod(str, Enum):
    QR = "QR"
    RECEPTION = "RECEPTION"
    WALK_IN = "WALK_IN"


class QueueTicket(Base):
    __tablename__ = "queue_tickets"
    __table_args__ = (
        UniqueConstraint("queue_id", "ticket_number", name="uq_queue_ticket_number"),
        UniqueConstraint("queue_id", "queue_position", name="uq_queue_ticket_position"),
        CheckConstraint("missed_turns >= 0", name="ck_queue_ticket_missed_turns_non_negative"),
        CheckConstraint(
            "paused_remaining_seconds IS NULL OR paused_remaining_seconds >= 0",
            name="ck_queue_ticket_paused_remaining_non_negative",
        ),
        Index("ix_queue_tickets_status_deadline", "status", "call_deadline_at"),
        Index("ix_queue_tickets_completed_at", "completed_at"),
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

    checked_in_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        default=None,
    )

    check_in_method: Mapped[CheckInMethod | None] = mapped_column(
        SAEnum(CheckInMethod),
        nullable=True,
        default=None,
    )

    missed_turns: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )

    approaching_notified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        default=None,
    )

    called_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        default=None,
    )

    call_deadline_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        default=None,
    )

    paused_remaining_seconds: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        default=None,
    )

    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        default=None,
    )
