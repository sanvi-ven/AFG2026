from typing import Literal

from pydantic import BaseModel, EmailStr, Field

# The exact set of emails this API can send — subject/body live server-side
# in EmailService, never accepted from a caller. See email_service.py.
EmailTemplateName = Literal[
    "request-confirmation",
    "owner-new-lead",
    "appointment-reminder",
    "invoice-reminder",
]


class EmailSendRequest(BaseModel):
    """request to send one of a fixed set of transactional emails. No raw
    subject/HTML is ever accepted — see email_service.py for why."""
    to: EmailStr
    template: EmailTemplateName
    params: dict[str, str] = Field(default_factory=dict, max_length=10)


class SmsSendRequest(BaseModel):
    """request to send a single sms message. `to` must be E.164
    (+country code, digits only) — Twilio itself would reject anything
    else, but validating here means a malformed number never reaches a
    billable Twilio API call at all."""
    to: str = Field(pattern=r"^\+[1-9]\d{1,14}$")
    body: str = Field(min_length=1, max_length=1600)


class SendResult(BaseModel):
    """generic delivery confirmation"""
    sent: bool
