"""
Centralized Test Database Safety Guard.
Enforces hard database isolation before any test setup or mutation occurs.
"""
import os
import urllib.parse
from app.core.config import settings


def normalize_db_target(url_str: str) -> tuple[str, str, int, str]:
    """
    Extracts normalized (scheme, hostname, port, dbname) from a database URL.
    Normalizes '127.0.0.1' and 'localhost' to 'localhost'.
    Does NOT return credentials (username or password).
    """
    if not url_str or not url_str.strip():
        return "", "", 0, ""

    parsed = urllib.parse.urlparse(url_str)
    scheme = parsed.scheme.split("+")[0] if parsed.scheme else ""
    host = parsed.hostname or "localhost"
    if host in ("127.0.0.1", "localhost"):
        host = "localhost"
    port = parsed.port or 5432
    dbname = parsed.path.strip("/")
    return scheme, host, port, dbname


def verify_test_db_isolation(
    dev_url: str | None = None,
    test_url: str | None = None,
    is_testing_env: bool | None = None,
) -> tuple[str, str, int, str]:
    """
    Verifies that TEST_DATABASE_URL is set, valid, and strictly isolated from DATABASE_URL.
    Raises RuntimeError if isolation cannot be conclusively proven.
    Never exposes passwords or sensitive credentials.
    """
    if dev_url is None:
        dev_url = os.getenv("DATABASE_URL") or settings.DATABASE_URL
    if test_url is None:
        test_url = os.getenv("TEST_DATABASE_URL") or settings.TEST_DATABASE_URL

    if not test_url or not test_url.strip():
        raise RuntimeError(
            "CRITICAL SAFETY GUARD VIOLATION: TEST_DATABASE_URL is not set or empty. "
            "Automated tests are refusing to run to prevent writing test data into the development database."
        )

    if not dev_url or not dev_url.strip():
        raise RuntimeError(
            "CRITICAL SAFETY GUARD VIOLATION: DATABASE_URL is not configured. "
            "Cannot verify test database isolation."
        )

    dev_scheme, dev_host, dev_port, dev_dbname = normalize_db_target(dev_url)
    test_scheme, test_host, test_port, test_dbname = normalize_db_target(test_url)

    if not test_dbname:
        raise RuntimeError(
            "CRITICAL SAFETY GUARD VIOLATION: TEST_DATABASE_URL does not specify a valid database name."
        )

    # Hard Check 1: Target identity check (host, port, dbname)
    if (test_host == dev_host) and (test_port == dev_port) and (test_dbname == dev_dbname):
        raise RuntimeError(
            f"CRITICAL SAFETY GUARD VIOLATION: TEST_DATABASE_URL resolves to the EXACT same database "
            f"target as DATABASE_URL (host: {test_host}, port: {test_port}, db: {test_dbname}). "
            f"Automated tests are refusing to execute to protect the development database."
        )

    # Hard Check 2: Database name collision check
    if test_dbname == dev_dbname:
        raise RuntimeError(
            f"CRITICAL SAFETY GUARD VIOLATION: TEST_DATABASE_URL database name '{test_dbname}' "
            f"matches development database name '{dev_dbname}'. Tests are aborted."
        )

    # Hard Check 3: Explicit test environment verification
    if is_testing_env is None:
        is_testing_env = (
            os.getenv("TESTING") == "1"
            or os.getenv("ENVIRONMENT") == "test"
            or os.getenv("APP_ENV") == "test"
            or bool(settings.TEST_DATABASE_URL)
        )

    if not is_testing_env:
        raise RuntimeError(
            "CRITICAL SAFETY GUARD VIOLATION: Testing environment is not explicitly enabled. "
            "Tests are aborted."
        )

    return test_scheme, test_host, test_port, test_dbname
