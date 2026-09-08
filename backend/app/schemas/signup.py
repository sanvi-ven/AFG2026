from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field


class CompleteSignupRequest(BaseModel):
    """request to finish onboarding a freshly-created Firebase Auth user:
    grants the requested role (validated server-side) and creates the
    matching profile record"""
    role: Literal["owner", "employee", "client"]
    first_name: str = Field(max_length=200)
    last_name: str = Field(max_length=200)
    phone_number: str = Field(default="", max_length=40)
    address: str = Field(default="", max_length=500)
    invite_code: Optional[str] = Field(default=None, max_length=64)
    # employee-only, optional — date of birth (ISO date string) and, if the
    # employee is a minor, parent/guardian contact for the employment
    # contract co-sign flow. Never trusted for authorization purposes (that
    # still comes from custom claims) — purely onboarding data.
    date_of_birth: Optional[str] = Field(default=None, max_length=10)
    guardian_name: str = Field(default="", max_length=200)
    guardian_email: str = Field(default="", max_length=320)
    guardian_phone: str = Field(default="", max_length=40)


class SignupProfileResponse(BaseModel):
    """the linked profile record after a signup/claim completes"""
    id: str
    uid: str
    role: str
    email: str
    first_name: str
    last_name: str
    phone_number: str
    address: str = ""


class ClaimAccountRequest(BaseModel):
    """turn an owner-created dummy client into a real login: validates the
    one-time claim code, then creates the Firebase Auth account for it"""
    code: str = Field(max_length=64)
    email: EmailStr
    password: str = Field(min_length=8, max_length=200)
