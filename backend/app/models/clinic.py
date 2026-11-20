from sqlalchemy import CheckConstraint, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Clinic(Base):
    __tablename__ = "clinics"
    __table_args__ = (
        CheckConstraint(
            "smart_call_timeout_seconds >= 15 AND smart_call_timeout_seconds <= 1800",
            name="ck_clinic_smart_call_timeout_range",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    smart_call_timeout_seconds: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=120,
        server_default=text("120"),
    )