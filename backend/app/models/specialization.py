from typing import Any

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Specialization(Base):
    __tablename__ = "specializations"

    id: Mapped[int] = mapped_column(primary_key=True)

    clinic_id: Mapped[int] = mapped_column(
        ForeignKey("clinics.id"),
        nullable=False,
    )

    name_uz: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
    )

    name_ru: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
    )

    name_en: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
    )

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        if "name" in kwargs and "name_uz" not in kwargs:
            name_val = kwargs.pop("name")
            kwargs["name_uz"] = name_val
            if "name_ru" not in kwargs:
                kwargs["name_ru"] = name_val
            if "name_en" not in kwargs:
                kwargs["name_en"] = name_val
        super().__init__(*args, **kwargs)

    def get_localized_name(self, lang: str = "uz") -> str:
        """
        Returns the localized specialization name following fallback rules:
        1. Requested language (if translation exists and is non-empty)
        2. Uzbek (default/base language)
        3. Any available translation (ru -> en)
        4. Empty string fallback (never crashes)
        """
        normalized_lang = (lang or "uz").strip().lower()
        if normalized_lang == "ru" and self.name_ru:
            return self.name_ru
        if normalized_lang == "en" and self.name_en:
            return self.name_en
        if normalized_lang == "uz" and self.name_uz:
            return self.name_uz

        # Fallback order: Uzbek -> available name
        return self.name_uz or self.name_ru or self.name_en or ""

    @property
    def name(self) -> str:
        """Backward-compatible default name property."""
        return self.get_localized_name("uz")

    @name.setter
    def name(self, value: str) -> None:
        self.name_uz = value
        if not self.name_ru:
            self.name_ru = value
        if not self.name_en:
            self.name_en = value