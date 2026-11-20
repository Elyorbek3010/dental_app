from datetime import date
from enum import Enum

from sqlalchemy import CheckConstraint, Date, Enum as SAEnum, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class SmartCallMode(str, Enum):
    MANUAL = "MANUAL"
    AUTOMATIC = "AUTOMATIC"


class Queue(Base):
    __tablename__ = "queues"
    __table_args__ = (
        UniqueConstraint("doctor_id", "queue_date", name="uq_queue_doctor_date"),
        CheckConstraint(
            "smart_call_mode IN ('MANUAL', 'AUTOMATIC')",
            name="ck_queue_smart_call_mode_valid",
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
