from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class ClientSignupCreate(BaseModel):
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    email: EmailStr
    phone_number: str = Field(min_length=1)
    address: str = Field(min_length=1)


class ClientSignupCreateRequest(ClientSignupCreate):
    password: str = Field(min_length=8, max_length=128)


class ClientSignupRead(ClientSignupCreate):
    id: str
    created_at: datetime


class ClientLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1)


class ClientLoginResponse(ClientSignupRead):
    pass


class ClientPasswordChangeRequest(BaseModel):
    email: EmailStr
    old_password: str = Field(min_length=1)
    new_password: str = Field(min_length=8, max_length=128)
