from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_roles
from app.models.push_device import PushDevice
from app.models.user import User, UserRole
from app.schemas.notification import DeviceTokenRequest, PushDeviceResponse

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


@router.post("/devices", response_model=PushDeviceResponse, status_code=status.HTTP_200_OK)
def register_device(
    request: DeviceTokenRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> PushDevice:
    token = request.fcm_token
    device = db.scalar(select(PushDevice).where(PushDevice.fcm_token == token))

    if device is None:
        device = PushDevice(
            user_id=current_user.id,
            fcm_token=token,
            is_active=True,
        )
        db.add(device)
    else:
        # Reassign ownership if token belonged to another user,
        # and ensure registration is active (idempotent)
        device.user_id = current_user.id
        device.is_active = True

    db.commit()
    db.refresh(device)
    return device


@router.delete("/devices", response_model=PushDeviceResponse, status_code=status.HTTP_200_OK)
def deactivate_device(
    request: DeviceTokenRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(UserRole.PATIENT)),
) -> PushDevice:
    token = request.fcm_token
    device = db.scalar(select(PushDevice).where(PushDevice.fcm_token == token))

    if device is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device token not found",
        )

    # Only affect a token owned by the authenticated patient
    if device.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to deactivate this device token",
        )

    device.is_active = False
    db.commit()
    db.refresh(device)
    return device
