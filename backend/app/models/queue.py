from datetime import date, datetime
from enum import Enum

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    Enum as SAEnum,
    ForeignKey,
    Index,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class SmartCallMode(str, Enum):
    MANUAL = "MANUAL"
    AUTOMATIC = "AUTOMATIC"


class ShiftStatus(str, Enum):
    OPEN = "OPEN"
    CLOSING = "CLOSING"
    FINISHED = "FINISHED"


class Queue(Base):
    __tablename__ = "queues"
    __table_args__ = (
        Index(
            "uq_queue_one_active_shift_per_doctor",
            "doctor_id",
            unique=True,
            postgresql_where=text("shift_status IN ('OPEN', 'CLOSING')"),
        ),
        Index("ix_queues_doctor_started", "doctor_id", "started_at"),
        Index("ix_queues_queue_date", "queue_date"),
        CheckConstraint(
            "smart_call_mode IN ('MANUAL', 'AUTOMATIC')",
            name="ck_queue_smart_call_mode_valid",
        ),
        CheckConstraint(
            "shift_status IN ('OPEN', 'CLOSING', 'FINISHED')",
            name="ck_queue_shift_status_valid",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)

    doctor_id: Mapped[int] = mapped_column(
        ForeignKey("doctors.id"),
        nullable=False,
    )

    queue_date: Mapped[date] = mapped_column(
        Date,
        nullable=False,
    )

    is_paused: Mapped[bool] = mapped_column(
        default=False,
        nullable=False,
    )

    is_active: Mapped[bool] = mapped_column(
        default=True,
        nullable=False,
    )

    smart_call_mode: Mapped[SmartCallMode] = mapped_column(
        SAEnum(
            SmartCallMode,
            name="smartcallmode",
            native_enum=False,
            length=16,
            values_callable=lambda enum_cls: [member.value for member in enum_cls],
        ),
        default=SmartCallMode.MANUAL,
        server_default="MANUAL",
        nullable=False,
    )

    shift_status: Mapped[ShiftStatus] = mapped_column(
        SAEnum(
            ShiftStatus,
            name="shiftstatus",
            native_enum=False,
            length=16,
            values_callable=lambda enum_cls: [member.value for member in enum_cls],
        ),
        default=ShiftStatus.OPEN,
        server_default="OPEN",
        nullable=False,
    )

    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        server_default=func.now(),
    )

    ended_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        default=None,
    )
