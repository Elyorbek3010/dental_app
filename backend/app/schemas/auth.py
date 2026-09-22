from pydantic import BaseModel, ConfigDict, Field

from app.models.user import UserRole


class UserRegister(BaseModel):
    full_name: str
    phone: str
    password: str = Field(min_length=8)


class UserLogin(BaseModel):
    phone: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class AccessTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    id: int
    clinic_id: int | None = None
    full_name: str
    phone: str
    role: UserRole
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
