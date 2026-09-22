from datetime import date

from sqlalchemy import Date, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Queue(Base):
    __tablename__ = "queues"
    __table_args__ = (
        UniqueConstraint("doctor_id", "queue_date", name="uq_queue_doctor_date"),
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
