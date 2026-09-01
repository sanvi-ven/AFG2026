from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Request, status
from firebase_admin import auth

from app.core.firebase import initialize_firebase_app
from app.core.rate_limit import limiter
from app.schemas.comms import EmailSendRequest, SendResult, SmsSendRequest
from app.services.email_service import EmailService
from app.services.sms_service import SmsService

router = APIRouter()
"""outbound email/sms dispatch. Two email templates (request-confirmation,
owner-new-lead) are reachable pre-auth — they're what the public "Request a
Quote" form fires before anyone has an account — everything else (the other
two email templates, and all of /sms, which has no pre-auth caller at all)
requires a real owner session. See email_service.py for why content is
template-only rather than caller-supplied free text/HTML."""
email_service = EmailService()
sms_service = SmsService()

_OWNER_ONLY_EMAIL_TEMPLATES = {"appointment-reminder", "invoice-reminder"}
# One static limit covers both the pre-auth and owner-authenticated
# templates on this route (slowapi's decorator runs before the request body
# is parsed, so it can't branch on `payload.template`) — content is now
# template-only regardless of auth state (see email_service.py), so the
# residual risk from a generous-looking limit is spam/cost, not phishing;
# 20/hour is loose enough for an owner's reminder-scan batch, tight enough
# to bound anonymous abuse of the two public templates.
_EMAIL_LIMIT = "20/hour"
_SMS_LIMIT = "30/minute"


def _require_owner(authorization: Optional[str]) -> None:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()

    try:
        initialize_firebase_app()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Firebase admin is not configured. Check service-account.json and FIREBASE_PROJECT_ID.",
        ) from exc

    try:
        claims = auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token",
        ) from exc

    if claims.get("role") != "owner":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Owner role required")


@router.post("/email", response_model=SendResult)
@limiter.limit(_EMAIL_LIMIT)
def send_email(
    request: Request,
    payload: EmailSendRequest,
    authorization: Optional[str] = Header(default=None),
) -> SendResult:
    if payload.template in _OWNER_ONLY_EMAIL_TEMPLATES:
        _require_owner(authorization)

    try:
        email_service.send_templated_email(payload.to, payload.template, payload.params)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return SendResult(sent=True)


@router.post("/sms", response_model=SendResult)
@limiter.limit(_SMS_LIMIT)
def send_sms(
    request: Request,
    payload: SmsSendRequest,
    authorization: Optional[str] = Header(default=None),
) -> SendResult:
    _require_owner(authorization)
    try:
        sms_service.send_sms(payload.to, payload.body)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return SendResult(sent=True)
