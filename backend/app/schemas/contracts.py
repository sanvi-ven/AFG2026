from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator


class GuardianContractView(BaseModel):
    """what a guardian sees on the pre-auth sign page, before signing"""
    employee_name: str
    company_name: str
    content: str
    changed_sections: Optional[list[dict]] = None  # present only for an amendment view
    already_signed: bool


class GuardianSignRequest(BaseModel):
    token: str = Field(max_length=128)
    method: Literal["typed", "drawn"]
    typed_name: str = Field(default="", max_length=200)
    # base64-encoded PNG of a drawn signature — generous cap, a compressed
    # signature-pad PNG is a few KB to a few tens of KB
    drawing_base64: str = Field(default="", max_length=2_000_000)
    consent_checked: bool
    consent_text: str = Field(max_length=1000)

    @model_validator(mode="after")
    def _validate_method_payload(self) -> "GuardianSignRequest":
        if not self.consent_checked:
            raise ValueError("Consent must be checked before signing.")
        if self.method == "typed" and not self.typed_name.strip():
            raise ValueError("typed_name is required for the typed method.")
        if self.method == "drawn" and not self.drawing_base64.strip():
            raise ValueError("drawing_base64 is required for the drawn method.")
        return self


class SendGuardianLinkResult(BaseModel):
    sent: bool
