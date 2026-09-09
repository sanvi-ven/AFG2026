from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field, model_validator

# The exact set of emails this API can send — subject/body live server-side
# in EmailService, never accepted from a caller. See email_service.py.
EmailTemplateName = Literal[
    "request-confirmation",
    "owner-new-lead",
    "appointment-reminder",
    "invoice-reminder",
]

# The SMS templates reachable pre-auth (the public "Request a Quote" form's
# own confirmation text, plus the new-lead alert it sends the owner) —
# content lives server-side in SmsService, never accepted from a caller,
# same reasoning as EmailTemplateName above. Every other SMS this app sends
# goes through the raw `body` path, which stays owner-authenticated only.
SmsTemplateName = Literal["request-received", "owner-new-lead"]


class EmailSendRequest(BaseModel):
    """request to send one of a fixed set of transactional emails. No raw
    subject/HTML is ever accepted — see email_service.py for why."""
    to: EmailStr
    template: EmailTemplateName
    params: dict[str, str] = Field(default_factory=dict, max_length=10)


class SmsSendRequest(BaseModel):
    """request to send a single sms message, either as a caller-composed
    `body` (owner-authenticated only — see comms.py's _require_owner) or a
    fixed `template` + `params` (the one pre-auth-reachable path, content
    owned server-side, same shape as EmailSendRequest). Exactly one of the
    two must be set. `to` must be E.164 (+country code, digits only) —
    Twilio itself would reject anything else, but validating here means a
    malformed number never reaches a billable Twilio API call at all."""
    to: str = Field(pattern=r"^\+[1-9]\d{1,14}$")
    body: Optional[str] = Field(default=None, min_length=1, max_length=1600)
    template: Optional[SmsTemplateName] = None
    params: dict[str, str] = Field(default_factory=dict, max_length=10)

    @model_validator(mode="after")
    def _require_exactly_one_content_source(self) -> "SmsSendRequest":
        if bool(self.body) == bool(self.template):
            raise ValueError("Provide exactly one of `body` or `template`.")
        return self


class SendResult(BaseModel):
    """generic delivery confirmation"""
    sent: bool
