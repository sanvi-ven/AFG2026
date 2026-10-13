from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

# What the business website (rplandscaping.org) sends when it forwards a
# form submission. The website validates everything first too; these limits
# are the server's own floor, never trusting the sender to have done so.


def _clean_list(values: list[str]) -> list[str]:
    seen: list[str] = []
    for value in values:
        cleaned = value.strip()
        if cleaned and cleaned not in seen:
            seen.append(cleaned)
    return seen


class WebsiteRequestIn(BaseModel):
    """a quote request submitted on the website's quote form"""
    source_id: int = Field(ge=1)
    name: str = Field(min_length=1, max_length=100)
    email: str = Field(default="", max_length=254)
    phone: str = Field(default="", max_length=30)
    address: str = Field(default="", max_length=200)
    services: list[str] = Field(default_factory=list, max_length=12)
    preferred_contact: Literal["call", "text", "email"] = "email"
    sms_opt_in: bool = False
    notes: str = Field(default="", max_length=5000)
    submitted_at: Optional[datetime] = None

    @field_validator("services")
    @classmethod
    def _short_service_names(cls, values: list[str]) -> list[str]:
        if any(len(v) > 60 for v in values):
            raise ValueError("Service names must be 60 characters or fewer.")
        return _clean_list(values)


class WebsiteApplicationIn(BaseModel):
    """a job application submitted on the website's careers page"""
    source_id: int = Field(ge=1)
    name: str = Field(min_length=1, max_length=100)
    email: str = Field(default="", max_length=254)
    phone: str = Field(default="", max_length=30)
    address: str = Field(default="", max_length=200)
    drivers_license: str = Field(default="", max_length=3)
    vehicle_info: str = Field(default="", max_length=300)
    experience: str = Field(default="", max_length=3)
    experience_details: str = Field(default="", max_length=5000)
    availability: str = Field(default="", max_length=300)
    physical_capability: str = Field(default="", max_length=3)
    # link back to the website's own password-protected admin page — the
    # resume file itself never leaves the website server
    resume_url: str = Field(default="", max_length=300, pattern=r"^(https://[^\s]+)?$")
    submitted_at: Optional[datetime] = None


class IntegrationResult(BaseModel):
    ok: bool
    id: str
    # false when this exact submission was already received (a website
    # retry) — nothing was re-saved or re-sent in that case
    created: bool
