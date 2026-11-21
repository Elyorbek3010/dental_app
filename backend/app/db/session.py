from typing import Any

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings


def build_engine_kwargs(database_url: str) -> dict[str, Any]:
    """
    Returns SQLAlchemy engine options compatible with both local PostgreSQL and
    Neon PgBouncer transaction pooling (-pooler).
    """
    kwargs: dict[str, Any] = {"pool_pre_ping": True}
    normalized = (database_url or "").strip().lower()
    if normalized.startswith("postgresql+psycopg"):
        kwargs.update(
            {
                "pool_recycle": 300,
                "pool_size": 5,
                "max_overflow": 5,
                # Disable automatic psycopg3 prepared statements so Neon PgBouncer
                # transaction-pooled connections do not collide across virtual sessions.
                "connect_args": {"prepare_threshold": None},
            }
        )
    elif normalized.startswith("postgresql"):
        kwargs.update({"pool_recycle": 300, "pool_size": 5, "max_overflow": 5})
    return kwargs


engine = create_engine(
    settings.DATABASE_URL,
    **build_engine_kwargs(settings.DATABASE_URL),
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
)