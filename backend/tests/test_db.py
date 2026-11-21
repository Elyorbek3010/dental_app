"""
Centralized Test Database Engine, Session, and Dependency Overrides.
Guarantees all test queries and API client calls operate exclusively on the isolated test database.
"""
import os
from collections.abc import Generator
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from app.api.deps import get_db
from app.core.config import settings
from app.core.rate_limit import rate_limiter
from app.main import app as fastapi_app
from app.db import session as db_session
from tests.safety_guard import verify_test_db_isolation

# 1. Enforce strict isolation check immediately
os.environ["TESTING"] = "1"
verify_test_db_isolation()

# 2. Initialize isolated test engine and sessionmaker
test_url = os.getenv("TEST_DATABASE_URL") or settings.TEST_DATABASE_URL
test_engine = create_engine(test_url, pool_pre_ping=True)
TestSessionLocal = sessionmaker(
    bind=test_engine,
    autoflush=False,
    autocommit=False,
)


def get_test_db() -> Generator[Session, None, None]:
    """Dependency override for FastAPI get_db during tests."""
    db = TestSessionLocal()
    try:
        yield db
    finally:
        db.close()


# 3. Global overrides for test execution
fastapi_app.dependency_overrides[get_db] = get_test_db

# Defense-in-depth: redirect legacy app.db.session handles to test DB
db_session.SessionLocal = TestSessionLocal
db_session.engine = test_engine


def clean_test_database() -> None:
    """
    Safely truncates test tables in dental_app_test between test runs.
    Re-verifies isolation before running TRUNCATE.
    """
    verify_test_db_isolation()
    rate_limiter.reset()
    with test_engine.connect() as conn:
        conn.execute(
            text(
                "TRUNCATE TABLE queue_tickets, queues, doctors, specializations, users, clinics, push_devices "
                "RESTART IDENTITY CASCADE;"
            )
        )
        conn.commit()
