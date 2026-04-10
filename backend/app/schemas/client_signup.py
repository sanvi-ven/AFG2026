from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class ClientAddress(BaseModel):
    street: str = Field(min_length=1)
    country: str = Field(min_length=1)
    zip_code: str = Field(min_length=1)


class ClientSignupCreate(BaseModel):
    name: str = Field(min_length=1)
    email: EmailStr
    phone: str = Field(min_length=1)
    address: ClientAddress


class ClientSignupRead(ClientSignupCreate):
    id: str
    created_at: datetime


class ClientLoginRequest(BaseModel):
    email: EmailStr


class ClientLoginResponse(ClientSignupRead):
    pass