from urllib.parse import urlsplit

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEFAULT_DEV_CORS_ORIGINS = "http://localhost:5173,http://127.0.0.1:5173"
_PRODUCTION_ENVIRONMENTS = {"staging", "production", "prod"}
_LOCAL_HTTP_HOSTS = {"localhost", "127.0.0.1"}


def parse_cors_origins(raw_origins: str, environment: str = "development") -> list[str]:
    """
    Parses and validates a comma-separated list of exact CORS origins.
    - Rejects wildcard '*' entries (incompatible with allow_credentials=True).
    - Rejects paths, trailing slashes, query strings, fragments, and embedded credentials.
    - Permits http:// only for localhost/127.0.0.1 in non-production/non-staging environments.
    """
    if not raw_origins or not raw_origins.strip():
        raise ValueError("CORS_ORIGINS must define at least one exact origin")

    env_name = (environment or "development").strip().lower()
    strict_https = env_name in _PRODUCTION_ENVIRONMENTS

    origins: list[str] = []
    seen: set[str] = set()

    for raw_item in raw_origins.split(","):
        candidate = raw_item.strip()
        if not candidate:
            raise ValueError("CORS_ORIGINS must not contain empty entries")
        if "*" in candidate:
            raise ValueError("CORS_ORIGINS must not contain wildcard '*'")

        parsed = urlsplit(candidate)
        if parsed.username or parsed.password:
            raise ValueError(f"CORS origin must not include credentials: {candidate}")
        if parsed.path or parsed.query or parsed.fragment:
            raise ValueError(
                f"CORS origin must be an exact origin without path, trailing slash, query, or fragment: {candidate}"
            )

        scheme = (parsed.scheme or "").lower()
        hostname = (parsed.hostname or "").lower()
        if not scheme or not hostname:
            raise ValueError(f"Malformed CORS origin: {candidate}")

        try:
            port = parsed.port
        except ValueError as exc:
            raise ValueError(f"Invalid port in CORS origin '{candidate}': {exc}") from exc

        if scheme == "https":
            pass
        elif scheme == "http":
            if strict_https:
                raise ValueError(
                    f"CORS origin must use HTTPS in '{env_name}' environment: {candidate}"
                )
            if hostname not in _LOCAL_HTTP_HOSTS:
                raise ValueError(
                    f"Non-local HTTP CORS origin is not allowed (use HTTPS): {candidate}"
                )
        else:
            raise ValueError(f"Unsupported CORS origin scheme '{scheme}': {candidate}")

        normalized_host = f"[{hostname}]" if ":" in hostname else hostname
        normalized = f"{scheme}://{normalized_host}"
        if port is not None:
            normalized = f"{normalized}:{port}"

        if normalized not in seen:
            seen.add(normalized)
            origins.append(normalized)

    if not origins:
        raise ValueError("CORS_ORIGINS must define at least one valid origin")

    return origins


class Settings(BaseSettings):
    ENVIRONMENT: str = "development"
    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    CHECK_IN_QR_EXPIRE_MINUTES: int = 180  # 3 hours
    FIREBASE_CREDENTIALS_PATH: str | None = "secrets/firebase-service-account.json"
    TEST_DATABASE_URL: str | None = None
    CORS_ORIGINS: str = DEFAULT_DEV_CORS_ORIGINS
    RATE_LIMIT_ENABLED: bool = True
    TRUSTED_PROXY_HOPS: int = 0

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
    )

    @property
    def cors_origins_list(self) -> list[str]:
        return parse_cors_origins(self.CORS_ORIGINS, self.ENVIRONMENT)

    @model_validator(mode="after")
    def validate_security_configuration(self) -> "Settings":
        # Validate CORS configuration eagerly on startup
        parse_cors_origins(self.CORS_ORIGINS, self.ENVIRONMENT)
        if self.TRUSTED_PROXY_HOPS < 0 or self.TRUSTED_PROXY_HOPS > 10:
            raise ValueError("TRUSTED_PROXY_HOPS must be between 0 and 10")
        env_name = (self.ENVIRONMENT or "development").strip().lower()
        if env_name in _PRODUCTION_ENVIRONMENTS:
            key = (self.SECRET_KEY or "").strip()
            if len(key) < 32 or "replace" in key.lower() or "change-me" in key.lower():
                raise ValueError(
                    "SECRET_KEY must be at least 32 characters and non-placeholder in staging/production"
                )
        return self


settings = Settings()