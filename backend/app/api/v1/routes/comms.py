from fastapi import APIRouter, HTTPException, status

from app.schemas.comms import EmailSendRequest, SendResult, SmsSendRequest
from app.services.email_service import EmailService
from app.services.sms_service import SmsService

router = APIRouter()
"""outbound email/sms dispatch, called fire-and-forget from the Flutter app
at the same trigger points that already create in-app notifications
(ReminderCheckService, request intake) — no auth required, matching the
rest of this app's permissive trust model (open Firestore/Storage rules)"""
email_service = EmailService()
sms_service = SmsService()


@router.post("/email", response_model=SendResult)
def send_email(payload: EmailSendRequest) -> SendResult:
    try:
        email_service.send_email(payload.to, payload.subject, payload.html_body)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return SendResult(sent=True)


@router.post("/sms", response_model=SendResult)
def send_sms(payload: SmsSendRequest) -> SendResult:
    try:
        sms_service.send_sms(payload.to, payload.body)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return SendResult(sent=True)
