"""
Isolated, fail-closed staging bootstrap script for Dental Queue cloud staging.

Safety guarantees:
- Separate from local seed.py (never touches local seed behavior).
- Defaults to dry-run; requires explicit `--execute` to commit changes.
- Requires both `--expected-host` and `--expected-db` and verifies they match DATABASE_URL.
- Refuses localhost, loopback addresses, dental_db, dental_app_test, and non-TLS URLs.
- Reads staff passwords exclusively from environment variables (STAGING_ADMIN_PASSWORD,
  STAGING_RECEPTION_PASSWORD) and rejects empty, short, or weak passwords.
- Never prints credentials, passwords, hashes, or raw connection URLs.
- Strictly idempotent: creates missing fictional clinic/staff/specializations/doctors only;
  never deletes or truncates existing records and creates no fake patient accounts.
"""
import argparse
from dataclasses import dataclass
import os
import sys
from urllib.parse import parse_qs, urlsplit

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from app.core.security import get_password_hash
from app.db.session import build_engine_kwargs
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.specialization import Specialization
from app.models.user import User, UserRole

_FORBIDDEN_HOSTS = {"localhost", "127.0.0.1", "::1", "0.0.0.0"}
_FORBIDDEN_DBS = {"dental_db", "dental_app_test", "postgres", "template0", "template1"}
_REQUIRED_SSLMODES = {"require", "verify-ca", "verify-full"}
_COMMON_WEAK_SUBSTRINGS = ("123456", "password", "qwerty", "admin123", "changeme", "dental")

STAGING_CLINIC_NAME = "Aurora Demo Dental Clinic"
STAGING_CLINIC_TIMEZONE = "Asia/Tashkent"

STAGING_SPECIALIZATIONS: tuple[tuple[str, str, str], ...] = (
    ("Terapiya", "Терапия", "General Dentistry"),
    ("Ortodontiya", "Ортодонтия", "Orthodontics"),
    ("Jarrohlik", "Хирургия", "Oral Surgery"),
)

STAGING_DOCTORS: tuple[tuple[str, str, str], ...] = (
    ("Dr. Azizbek Rakhimov", "Terapiya", "101"),
    ("Dr. Malika Tursunova", "Ortodontiya", "102"),
    ("Dr. Sardor Rustamov", "Jarrohlik", "103"),
)


@dataclass(frozen=True)
class BootstrapTarget:
    host: str
    port: int
    dbname: str
    sslmode: str


@dataclass(frozen=True)
class BootstrapSummary:
    execute: bool
    clinic_created: bool
    admin_created: bool
    receptionist_created: bool
    specializations_created: int
    doctors_created: int


def validate_staging_target(
    database_url: str,
    expected_host: str,
    expected_db: str,
) -> BootstrapTarget:
    """
    Validates DATABASE_URL against expected staging host and database name.
    Fails closed for local, test, ambiguous, non-PostgreSQL, or non-TLS targets.
    """
    if not database_url or not database_url.strip():
        raise ValueError("DATABASE_URL must be set for staging bootstrap")

    exp_host = (expected_host or "").strip().lower()
    exp_db = (expected_db or "").strip()
    if not exp_host or not exp_db:
        raise ValueError("Both --expected-host and --expected-db must be non-empty")

    if exp_host in _FORBIDDEN_HOSTS or exp_host.endswith(".local"):
        raise ValueError(f"Refusing forbidden local/ambiguous expected host: {exp_host}")
    if exp_db.lower() in _FORBIDDEN_DBS:
        raise ValueError(f"Refusing forbidden local/system database name: {exp_db}")

    parsed = urlsplit(database_url.strip())
    scheme = (parsed.scheme or "").split("+")[0].lower()
    if scheme not in ("postgresql", "postgres"):
        raise ValueError("DATABASE_URL must target a PostgreSQL database")

    host = (parsed.hostname or "").strip().lower()
    dbname = parsed.path.lstrip("/").strip()
    port = parsed.port or 5432

    if not host or not dbname or "/" in dbname:
        raise ValueError("DATABASE_URL host or database name is missing or ambiguous")
    if host in _FORBIDDEN_HOSTS or host.endswith(".local"):
        raise ValueError(f"Refusing local/ambiguous DATABASE_URL host: {host}")
    if dbname.lower() in _FORBIDDEN_DBS:
        raise ValueError(f"Refusing local/test/system DATABASE_URL database: {dbname}")

    if host != exp_host:
        raise ValueError(
            f"Target host mismatch: DATABASE_URL host '{host}' != expected '{exp_host}'"
        )
    if dbname != exp_db:
        raise ValueError(
            f"Target database mismatch: DATABASE_URL db '{dbname}' != expected '{exp_db}'"
        )

    query = parse_qs(parsed.query)
    sslmode_vals = [v.strip().lower() for v in query.get("sslmode", []) if v.strip()]
    if not sslmode_vals or sslmode_vals[0] not in _REQUIRED_SSLMODES:
        raise ValueError(
            "Staging DATABASE_URL must require TLS (sslmode=require, verify-ca, or verify-full)"
        )

    return BootstrapTarget(host=host, port=port, dbname=dbname, sslmode=sslmode_vals[0])


def validate_strong_password(password: str | None, env_var_name: str) -> str:
    """Validates password strength without ever echoing password content in errors."""
    if not password or not password.strip():
        raise ValueError(f"{env_var_name} environment variable must be set")

    value = password.strip()
    if len(value) < 12:
        raise ValueError(f"{env_var_name} must be at least 12 characters long")

    has_upper = any(ch.isupper() for ch in value)
    has_lower = any(ch.islower() for ch in value)
    has_digit = any(ch.isdigit() for ch in value)
    has_special = any(not ch.isalnum() for ch in value)
    if not (has_upper and has_lower and has_digit and has_special):
        raise ValueError(
            f"{env_var_name} must include uppercase, lowercase, digit, and special character"
        )

    lowered = value.lower()
    if any(weak in lowered for weak in _COMMON_WEAK_SUBSTRINGS):
        raise ValueError(f"{env_var_name} must not contain weak or predictable words/sequences")

    return value


def _validate_phone(raw_phone: str, label: str) -> str:
    cleaned = (raw_phone or "").strip()
    if not cleaned or len(cleaned) < 8 or len(cleaned) > 30:
        raise ValueError(f"{label} phone number is invalid")
    return cleaned


def apply_staging_bootstrap(
    db: Session,
    *,
    admin_password: str,
    reception_password: str,
    admin_phone: str = "+998901000001",
    reception_phone: str = "+998901000002",
    execute: bool = False,
) -> BootstrapSummary:
    """
    Idempotently creates fictional staging clinic, admin, receptionist, 3 dental
    specializations, and 3 doctors. When `execute=False` (default), calculates all actions
    in dry-run mode without writing or committing changes.
    """
    validate_strong_password(admin_password, "STAGING_ADMIN_PASSWORD")
    validate_strong_password(reception_password, "STAGING_RECEPTION_PASSWORD")
    valid_admin_phone = _validate_phone(admin_phone, "Admin")
    valid_reception_phone = _validate_phone(reception_phone, "Reception")
    if valid_admin_phone == valid_reception_phone:
        raise ValueError("Admin and receptionist phone numbers must be distinct")

    clinic = db.scalar(select(Clinic).where(Clinic.name == STAGING_CLINIC_NAME))
    clinic_created = clinic is None
    if clinic is None and execute:
        clinic = Clinic(
            name=STAGING_CLINIC_NAME,
            smart_call_timeout_seconds=120,
            timezone=STAGING_CLINIC_TIMEZONE,
        )
        db.add(clinic)
        db.flush()

    existing_admin = db.scalar(select(User).where(User.phone == valid_admin_phone))
    admin_created = existing_admin is None
    if existing_admin is None and execute:
        assert clinic is not None
        db.add(
            User(
                clinic_id=clinic.id,
                full_name="Samira Karimova (Demo Admin)",
                phone=valid_admin_phone,
                hashed_password=get_password_hash(admin_password),
                role=UserRole.ADMIN,
                is_active=True,
            )
        )

    existing_reception = db.scalar(select(User).where(User.phone == valid_reception_phone))
    receptionist_created = existing_reception is None
    if existing_reception is None and execute:
        assert clinic is not None
        db.add(
            User(
                clinic_id=clinic.id,
                full_name="Timur Alimov (Demo Reception)",
                phone=valid_reception_phone,
                hashed_password=get_password_hash(reception_password),
                role=UserRole.RECEPTIONIST,
                is_active=True,
            )
        )

    spec_by_uz: dict[str, Specialization] = {}
    if clinic is not None:
        existing_specs = db.scalars(
            select(Specialization).where(Specialization.clinic_id == clinic.id)
        ).all()
        spec_by_uz = {spec.name_uz: spec for spec in existing_specs}

    specs_created = 0
    for name_uz, name_ru, name_en in STAGING_SPECIALIZATIONS:
        if name_uz not in spec_by_uz:
            specs_created += 1
            if execute:
                assert clinic is not None
                spec = Specialization(
                    clinic_id=clinic.id,
                    name_uz=name_uz,
                    name_ru=name_ru,
                    name_en=name_en,
                    is_active=True,
                )
                db.add(spec)
                spec_by_uz[name_uz] = spec

    if execute:
        db.flush()

    existing_doctor_names: set[str] = set()
    if clinic is not None:
        existing_doctor_names = set(
            db.scalars(select(Doctor.full_name).where(Doctor.clinic_id == clinic.id)).all()
        )

    doctors_created = 0
    for full_name, spec_uz, room_number in STAGING_DOCTORS:
        if full_name not in existing_doctor_names:
            doctors_created += 1
            if execute:
                assert clinic is not None
                spec = spec_by_uz[spec_uz]
                db.add(
                    Doctor(
                        clinic_id=clinic.id,
                        specialization_id=spec.id,
                        full_name=full_name,
                        room_number=room_number,
                        is_active=True,
                    )
                )

    if execute:
        db.commit()

    return BootstrapSummary(
        execute=execute,
        clinic_created=clinic_created,
        admin_created=admin_created,
        receptionist_created=receptionist_created,
        specializations_created=specs_created,
        doctors_created=doctors_created,
    )


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Safely bootstrap fictional demo clinic data into an isolated staging DB.",
    )
    parser.add_argument(
        "--expected-host",
        required=True,
        help="Expected PostgreSQL hostname matching DATABASE_URL (e.g. ep-...pooler...neon.tech).",
    )
    parser.add_argument(
        "--expected-db",
        required=True,
        help="Expected PostgreSQL database name matching DATABASE_URL.",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        default=False,
        help="Apply changes to the verified staging target. Omit for safe dry-run mode.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    database_url = os.getenv("DATABASE_URL", "")
    target = validate_staging_target(
        database_url=database_url,
        expected_host=args.expected_host,
        expected_db=args.expected_db,
    )
    admin_password = os.getenv("STAGING_ADMIN_PASSWORD", "")
    reception_password = os.getenv("STAGING_RECEPTION_PASSWORD", "")
    admin_phone = os.getenv("STAGING_ADMIN_PHONE", "+998901000001")
    reception_phone = os.getenv("STAGING_RECEPTION_PHONE", "+998901000002")

    # Validate strong passwords up front even in dry-run mode
    validate_strong_password(admin_password, "STAGING_ADMIN_PASSWORD")
    validate_strong_password(reception_password, "STAGING_RECEPTION_PASSWORD")

    engine = create_engine(database_url, **build_engine_kwargs(database_url))
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        with session_factory() as db:
            summary = apply_staging_bootstrap(
                db,
                admin_password=admin_password,
                reception_password=reception_password,
                admin_phone=admin_phone,
                reception_phone=reception_phone,
                execute=args.execute,
            )
    finally:
        engine.dispose()

    mode = "EXECUTE" if summary.execute else "DRY-RUN"
    print(
        f"[{mode}] target host={target.host} db={target.dbname} sslmode={target.sslmode} | "
        f"clinic_created={summary.clinic_created}, admin_created={summary.admin_created}, "
        f"receptionist_created={summary.receptionist_created}, "
        f"specializations_created={summary.specializations_created}, "
        f"doctors_created={summary.doctors_created}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"Staging bootstrap aborted: {exc}", file=sys.stderr)
        raise SystemExit(2)
