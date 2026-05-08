from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class ClientSignupCreate(BaseModel):
    """base client signup with name, email, phone, and address"""
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    email: EmailStr
    phone_number: str = Field(min_length=1)
    address: str = Field(min_length=1)


class ClientSignupCreateRequest(ClientSignupCreate):
    """create client signup with password"""
    password: str = Field(min_length=8, max_length=128)


class ClientSignupRead(ClientSignupCreate):
    """complete client signup response with id and timestamp"""
    id: str
    created_at: datetime


class ClientLoginRequest(BaseModel):
    """client login request with email and password"""
    email: EmailStr
    password: str = Field(min_length=1)


class ClientLoginResponse(ClientSignupRead):
    """client login response with profile info"""
    pass


class ClientPasswordChangeRequest(BaseModel):
    """request to change client password with old and new passwords"""
    email: EmailStr
    old_password: str = Field(min_length=1)
    new_password: str = Field(min_length=8, max_length=128)
