from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(subject: str | int, expires_delta: timedelta | None = None) -> str:
    if expires_delta is not None:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(
            minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
        )

    to_encode = {
        "sub": str(subject),
        "type": "access",
        "exp": expire,
    }
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(subject: str | int) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        days=settings.REFRESH_TOKEN_EXPIRE_DAYS
    )
    to_encode = {
        "sub": str(subject),
        "type": "refresh",
        "exp": expire,
    }
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_refresh_token(token: str) -> int:
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    if payload.get("type") != "refresh":
        raise JWTError("Invalid token type: expected refresh token")
    sub = payload.get("sub")
    if sub is None:
        raise JWTError("Token missing subject")
    try:
        return int(sub)
    except (ValueError, TypeError):
        raise JWTError("Invalid subject format in refresh token")


def create_check_in_qr_token(clinic_id: int) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.CHECK_IN_QR_EXPIRE_MINUTES
    )
    to_encode = {
        "type": "check_in_qr",
        "clinic_id": clinic_id,
        "exp": expire,
    }
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_check_in_qr_token(token: str) -> int:
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    if payload.get("type") != "check_in_qr":
        raise JWTError("Invalid token type: expected check_in_qr token")
    clinic_id = payload.get("clinic_id")
    if clinic_id is None:
        raise JWTError("Token missing clinic_id")
    if isinstance(clinic_id, bool):
        raise JWTError("Invalid clinic_id type in check_in_qr token")
    try:
        return int(clinic_id)
    except (ValueError, TypeError):
        raise JWTError("Invalid clinic_id format in check_in_qr token")

