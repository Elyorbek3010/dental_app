from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class DeviceTokenRequest(BaseModel):
    fcm_token: str = Field(..., description="Firebase Cloud Messaging device token")

    @field_validator("fcm_token")
    @classmethod
    def validate_fcm_token(cls, v: str) -> str:
        token = v.strip()
        if not token:
            raise ValueError("fcm_token cannot be empty")
        if len(token) > 512:
            raise ValueError("fcm_token is too long (max 512 characters)")
        return token


class PushDeviceResponse(BaseModel):
    id: int
    user_id: int
    fcm_token: str
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
