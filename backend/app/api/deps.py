from typing import Callable, Generator

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.user import User, UserRole

security = HTTPBearer()

SUPPORTED_LANGUAGES = {"uz", "ru", "en"}
DEFAULT_LANGUAGE = "uz"


def get_language(
    accept_language: str | None = Header(default=None, alias="Accept-Language")
) -> str:
    """
    Parses and extracts the preferred language from the Accept-Language header.
    Supported values: 'uz', 'ru', 'en'.
    Fallback order: requested language -> Uzbek ('uz').
    Accepts standard header values like 'ru', 'ru-RU', 'uz-UZ,uz;q=0.9', 'en-US,en;q=0.8'.
    """
    if not accept_language:
        return DEFAULT_LANGUAGE

    for part in accept_language.split(","):
        tag = part.split(";")[0].strip().lower()
        primary = tag.split("-")[0].strip()
        if primary in SUPPORTED_LANGUAGES:
            return primary

    return DEFAULT_LANGUAGE


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
        )
        if payload.get("type") != "access":
            raise credentials_exception

        sub = payload.get("sub")
        if sub is None:
            raise credentials_exception

        user_id = int(sub)
    except (JWTError, ValueError, TypeError):
        raise credentials_exception

    user = db.scalar(select(User).where(User.id == user_id))
    if user is None:
        raise credentials_exception

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Inactive user",
        )

    return user


def require_roles(*allowed_roles: UserRole) -> Callable[[User], User]:
    def role_checker(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return current_user

    return role_checker
