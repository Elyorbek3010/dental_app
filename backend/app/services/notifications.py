from dataclasses import dataclass
import json
import logging
from pathlib import Path
from typing import Any

import firebase_admin
from firebase_admin import credentials
from firebase_admin import exceptions as fb_exceptions
from firebase_admin import messaging

from app.core.config import settings

logger = logging.getLogger("app.services.notifications")


@dataclass
class PushNotificationResult:
    """Result of attempting to send a push notification."""
    success: bool
    message_id: str | None = None
    error_code: str | None = None
    error_message: str | None = None
    is_unregistered: bool = False


def mask_token(token: str) -> str:
    """
    Safely masks an FCM token for logging purposes to preserve privacy.
    Example: 'dK9x...8z1Q'
    """
    if not token or len(token) <= 10:
        return "***"
    return f"{token[:4]}...{token[-4:]}"


def get_firebase_credentials_path(raw_path_override: str | None = None) -> Path | None:
    """
    Resolves the Firebase service-account JSON path from settings (or override).
    Supports Render Secret Files (e.g. /etc/secrets/firebase-service-account.json),
    paths relative to CWD, and paths relative to the backend project root.
    """
    raw_path = raw_path_override if raw_path_override is not None else settings.FIREBASE_CREDENTIALS_PATH
    if not raw_path or not raw_path.strip():
        return None

    candidate = Path(raw_path.strip())
    if candidate.is_absolute():
        if candidate.is_file():
            return candidate
        # Also check with .json appended if missing
        if candidate.with_suffix(".json").is_file():
            return candidate.with_suffix(".json")
        return None

    # Check relative to current working directory
    cwd_candidate = Path.cwd() / candidate
    if cwd_candidate.is_file():
        return cwd_candidate
    if cwd_candidate.with_suffix(".json").is_file():
        return cwd_candidate.with_suffix(".json")

    # Check relative to backend root directory (where app/ is located)
    backend_dir = Path(__file__).resolve().parent.parent.parent
    backend_candidate = backend_dir / candidate
    if backend_candidate.is_file():
        return backend_candidate
    if backend_candidate.with_suffix(".json").is_file():
        return backend_candidate.with_suffix(".json")

    return None


def initialize_firebase() -> bool:
    """
    Initializes the Firebase Admin SDK if not already initialized.
    Avoids duplicate initialization.
    Returns True if initialized successfully, False otherwise.
    Never raises an uncaught exception that would crash application startup.
    """
    # Check if Firebase is already initialized
    try:
        firebase_admin.get_app()
        return True
    except ValueError:
        pass  # App not yet initialized

    cred_path = get_firebase_credentials_path()
    if not cred_path:
        logger.warning(
            "Firebase credentials file not found at '%s'. Push notifications will be disabled.",
            settings.FIREBASE_CREDENTIALS_PATH,
        )
        return False

    try:
        cred = credentials.Certificate(str(cred_path))
        firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin SDK successfully initialized.")
        return True
    except Exception as exc:
        logger.error("Failed to initialize Firebase Admin SDK: %s", type(exc).__name__)
        return False


def check_firebase_credentials_status(raw_path_override: str | None = None) -> dict[str, Any]:
    """
    Checks whether a Firebase service-account JSON file exists and is structurally valid
    without returning private keys, client emails, or file contents.
    """
    cred_path = get_firebase_credentials_path(raw_path_override=raw_path_override)
    if not cred_path:
        return {"configured": False, "valid": False, "reason": "missing_file"}

    try:
        payload = json.loads(cred_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {"configured": True, "valid": False, "reason": "invalid_json"}

    if not isinstance(payload, dict) or payload.get("type") != "service_account" or not payload.get("project_id"):
        return {"configured": True, "valid": False, "reason": "invalid_service_account_schema"}

    return {"configured": True, "valid": True, "reason": "ok"}


def build_fcm_message(
    token: str,
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> messaging.Message:
    """
    Constructs a Firebase messaging.Message with notification title, body,
    optional string data payload, and target token.
    """
    string_data: dict[str, str] | None = None
    if data:
        string_data = {str(k): str(v) for k, v in data.items()}

    return messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data=string_data,
        token=token,
    )


def send_push_notification(
    token: str,
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> PushNotificationResult:
    """
    Sends one push notification to one FCM token via Firebase Admin SDK.
    
    Guarantees:
    - Never crashes FastAPI or caller on failure.
    - Catches and categorizes Firebase errors.
    - Safely logs failures with masked tokens.
    - Flags invalid / unregistered tokens (is_unregistered=True) so callers
      can deactivate stale PushDevice records if needed.
    """
    if not initialize_firebase():
        logger.warning(
            "Cannot send push notification to %s: Firebase is not initialized",
            mask_token(token),
        )
        return PushNotificationResult(
            success=False,
            error_code="FIREBASE_NOT_INITIALIZED",
            error_message="Firebase Admin SDK is not initialized",
        )

    message = build_fcm_message(token=token, title=title, body=body, data=data)

    try:
        message_id = messaging.send(message)
        logger.info(
            "Successfully sent push notification to %s (message_id=%s)",
            mask_token(token),
            message_id,
        )
        return PushNotificationResult(
            success=True,
            message_id=message_id,
        )
    except messaging.UnregisteredError as exc:
        logger.warning(
            "FCM token %s is unregistered or expired: %s",
            mask_token(token),
            exc,
        )
        return PushNotificationResult(
            success=False,
            error_code="UNREGISTERED",
            error_message=str(exc),
            is_unregistered=True,
        )
    except messaging.SenderIdMismatchError as exc:
        logger.warning(
            "FCM token %s has sender ID mismatch: %s",
            mask_token(token),
            exc,
        )
        return PushNotificationResult(
            success=False,
            error_code="SENDER_ID_MISMATCH",
            error_message=str(exc),
            is_unregistered=True,
        )
    except fb_exceptions.InvalidArgumentError as exc:
        logger.warning(
            "FCM token %s or message payload is invalid: %s",
            mask_token(token),
            exc,
        )
        is_token_err = "token" in str(exc).lower() or "registration-token-not-registered" in str(exc).lower()
        return PushNotificationResult(
            success=False,
            error_code="INVALID_ARGUMENT",
            error_message=str(exc),
            is_unregistered=is_token_err,
        )
    except fb_exceptions.FirebaseError as exc:
        logger.error(
            "Firebase error sending push notification to %s: %s",
            mask_token(token),
            exc,
        )
        error_code = getattr(exc, "code", "FIREBASE_ERROR") or "FIREBASE_ERROR"
        return PushNotificationResult(
            success=False,
            error_code=str(error_code),
            error_message=str(exc),
            is_unregistered=False,
        )
    except Exception as exc:
        logger.error(
            "Unexpected error sending push notification to %s: %s",
            mask_token(token),
            exc,
        )
        return PushNotificationResult(
            success=False,
            error_code="UNEXPECTED_ERROR",
            error_message=str(exc),
            is_unregistered=False,
        )
