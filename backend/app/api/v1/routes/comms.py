from fastapi import APIRouter, HTTPException, Request, status

from app.core.rate_limit import limiter
from app.schemas.comms import EmailSendRequest, SendResult, SmsSendRequest
from app.services.email_service import EmailService
from app.services.sms_service import SmsService

router = APIRouter()
"""outbound email/sms dispatch, called fire-and-forget from the Flutter app
at the same trigger points that already create in-app notifications
(ReminderCheckService, request intake) — still no real per-caller auth (see
core/rate_limit.py), so these are IP rate-limited as a stopgap against
abuse of the Resend/Twilio accounts behind them"""
email_service = EmailService()
sms_service = SmsService()


@router.post("/email", response_model=SendResult)
@limiter.limit("5/minute")
def send_email(request: Request, payload: EmailSendRequest) -> SendResult:
    try:
        email_service.send_email(payload.to, payload.subject, payload.html_body)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return SendResult(sent=True)


@router.post("/sms", response_model=SendResult)
@limiter.limit("5/minute")
def send_sms(request: Request, payload: SmsSendRequest) -> SendResult:
    try:
        sms_service.send_sms(payload.to, payload.body)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return SendResult(sent=True)
