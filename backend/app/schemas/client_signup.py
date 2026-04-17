from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class ClientSignupCreate(BaseModel):
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    email: EmailStr
    phone_number: str = Field(min_length=1)
    address: str = Field(min_length=1)


class ClientSignupRead(ClientSignupCreate):
    id: str
    created_at: datetime


class ClientLoginRequest(BaseModel):
    email: EmailStr


class ClientLoginResponse(ClientSignupRead):
    pass