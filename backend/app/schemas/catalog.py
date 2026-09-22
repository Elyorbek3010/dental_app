from pydantic import BaseModel, ConfigDict


class SpecializationResponse(BaseModel):
    id: int
    clinic_id: int
    name: str

    model_config = ConfigDict(from_attributes=True)


class DoctorResponse(BaseModel):
    id: int
    clinic_id: int
    specialization_id: int
    full_name: str
    room_number: str | None = None
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
