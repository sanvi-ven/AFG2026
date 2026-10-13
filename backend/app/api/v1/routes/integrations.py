import hashlib
import hmac
import logging
import re
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import ValidationError

from app.core.config import settings
from app.core.rate_limit import limiter
from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.integrations import IntegrationResult, WebsiteApplicationIn, WebsiteRequestIn
from app.services.email_service import EmailService
from app.services.sms_service import SmsService

router = APIRouter()
"""server-to-server intake from the business website (rplandscaping.org).

The website's own backend forwards each quote request / job application it
receives. Every call must be signed with WEBSITE_INTEGRATION_SECRET:

    X-Website-Timestamp: <unix seconds>
    X-Website-Signature: sha256=<hex HMAC-SHA256 of "<timestamp>.<raw body>">

Calls older than 5 minutes are rejected (no replaying a captured request),
the comparison is constant-time, and no browser ever holds the secret, so
these routes have no CORS exposure at all. Writes go through the Admin SDK
(bypassing firestore.rules, like every other backend write), into the same
`requests` collection the in-app "Request a Quote" form uses — plus a new
owner-only `applicants` collection for job applications.

Document ids are `website-<website entry id>`, created with create-if-absent
semantics, so a website retry of the same submission can never duplicate a
request or re-send its notifications."""

logger = logging.getLogger(__name__)
email_service = EmailService()
sms_service = SmsService()

_MAX_CLOCK_SKEW_SECONDS = 300
_LIMIT = "60/minute"
# Submissions older than this are saved without sending any notifications —
# e.g. the owner backfilling months-old website entries shouldn't email those
# customers "we received your request" now. The website's own retry schedule
# gives up after ~28 hours, so genuinely new submissions always fall inside.
_NOTIFY_WINDOW = timedelta(hours=48)


# ---------- request signing ----------

async def _verified_body(request: Request) -> bytes:
    secret = settings.website_integration_secret
    if not secret:
        # not configured on this deployment: refuse everything rather than
        # accept unsigned calls
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Integration not configured.")

    timestamp = request.headers.get("x-website-timestamp", "")
    signature = request.headers.get("x-website-signature", "")
    if not timestamp.isdigit() or not signature.startswith("sha256="):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or malformed signature.")
    if abs(time.time() - int(timestamp)) > _MAX_CLOCK_SKEW_SECONDS:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Signature expired.")

    body = await request.body()
    expected = hmac.new(secret.encode(), timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, signature.removeprefix("sha256=")):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid signature.")
    return body


def _parse(model, body: bytes):
    try:
        return model.model_validate_json(body)
    except ValidationError as exc:
        # field-level reasons only, never echo the submitted values back
        reasons = "; ".join(f"{'.'.join(str(p) for p in e['loc'])}: {e['msg']}" for e in exc.errors())
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=reasons) from exc


# ---------- storage ----------

def _create_once(collection: str, doc_id: str, record: dict) -> bool:
    """create the document only if it doesn't already exist; returns whether
    it was created. Firestore's create() is atomic, so two overlapping
    retries of the same submission still produce exactly one document."""
    repo = FirestoreRepository(collection)
    if repo.db is None:  # USE_MOCK_FIRESTORE=true (local dev)
        if repo.get_by_id(doc_id) is not None:
            return False
        repo.create_with_id(doc_id, record)
        return True

    from google.api_core.exceptions import AlreadyExists, Conflict

    try:
        repo.db.collection(collection).document(doc_id).create(record)
    except (AlreadyExists, Conflict):
        return False
    return True


def _created_at(submitted_at: Optional[datetime]) -> datetime:
    if submitted_at is None:
        return datetime.now(timezone.utc)
    return submitted_at if submitted_at.tzinfo else submitted_at.replace(tzinfo=timezone.utc)


# ---------- notifications (best-effort, after the record is safely saved) ----------

def _owner_settings() -> dict:
    return FirestoreRepository("owner_settings").get_by_id("default") or {}


def _to_e164(phone: str) -> Optional[str]:
    """stored/submitted phone numbers are free text ("774-559-9448"); Twilio
    needs E.164. US numbers only, same assumption as CommsService._toE164."""
    raw = (phone or "").strip()
    digits = re.sub(r"\D", "", raw)
    if raw.startswith("+") and 8 <= len(digits) <= 15:
        return f"+{digits}"
    if len(digits) == 10:
        return f"+1{digits}"
    if len(digits) == 11 and digits.startswith("1"):
        return f"+{digits}"
    return None


def _try(label: str, send) -> None:
    try:
        send()
    except Exception as exc:  # never fail the intake because a notification failed
        logger.warning("Website integration: %s not sent (%s)", label, type(exc).__name__)


def _is_recent(created_at: datetime) -> bool:
    return datetime.now(timezone.utc) - created_at <= _NOTIFY_WINDOW


def _truncate(text: str, limit: int) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


# ---------- routes ----------

@router.post("/website/requests", response_model=IntegrationResult)
@limiter.limit(_LIMIT)
async def receive_website_request(request: Request) -> IntegrationResult:
    payload: WebsiteRequestIn = _parse(WebsiteRequestIn, await _verified_body(request))
    doc_id = f"website-{payload.source_id}"

    record = {
        # same shape as the Flutter Request model (models/request.dart)
        "id": doc_id,
        "clientId": None,
        "name": payload.name.strip(),
        "email": payload.email.strip(),
        "phone": payload.phone.strip(),
        "address": payload.address.strip(),
        "description": payload.notes.strip(),
        "services": payload.services,
        "photoUrls": [],
        "status": "new",
        "createdAt": _created_at(payload.submitted_at),
        "convertedEstimateId": None,
        "declineReason": "",
        "smsOptIn": payload.sms_opt_in,
        "preferredContact": payload.preferred_contact,
        "source": "website",
        "sourceId": payload.source_id,
    }
    if not _create_once("requests", doc_id, record):
        return IntegrationResult(ok=True, id=doc_id, created=False)
    if not _is_recent(record["createdAt"]):
        logger.info("Website integration: saved older request %s without notifications", doc_id)
        return IntegrationResult(ok=True, id=doc_id, created=True)

    owner = _owner_settings()
    business_name = (owner.get("company_name") or "").strip() or "Your service provider"
    summary = (f"Services: {', '.join(payload.services)}. " if payload.services else "") + payload.notes

    owner_phone = _to_e164(owner.get("phone", ""))
    if owner_phone:
        _try("owner new-lead SMS", lambda: sms_service.send_templated_sms(owner_phone, "owner-new-lead", {
            "name": record["name"],
            "preferred_contact": {"call": "Call", "text": "Text"}.get(payload.preferred_contact, "Email"),
            "phone": record["phone"] or "none",
            "email": record["email"] or "none",
            "address": record["address"] or "none",
            "description": _truncate(summary, 160),
            "link": settings.frontend_base_url,
        }))
    owner_email = (owner.get("email") or "").strip()
    if owner_email:
        _try("owner new-lead email", lambda: email_service.send_templated_email(owner_email, "owner-new-lead", {
            "name": record["name"],
            "client_email": record["email"] or "no email given",
            "description": summary,
        }))

    # The requester's confirmation follows their preferred contact method:
    # Email → confirmation email only; Text/Call → confirmation text only,
    # and only with the explicit opt-in from the website form's
    # unchecked-by-default consent checkbox ("preferred contact: text" alone
    # is not consent). So someone who chose Text/Call but didn't opt in gets
    # no automatic confirmation at all. The owner alerts above are unaffected.
    wants_email = payload.preferred_contact == "email"
    if record["email"] and wants_email:
        _try("request confirmation email", lambda: email_service.send_templated_email(
            record["email"], "request-confirmation", {"name": record["name"]}))
    requester_phone = _to_e164(record["phone"]) if payload.sms_opt_in and not wants_email else None
    if requester_phone:
        _try("request-received SMS", lambda: sms_service.send_templated_sms(
            requester_phone, "request-received", {"business_name": business_name}))

    logger.info("Website integration: saved request %s", doc_id)
    return IntegrationResult(ok=True, id=doc_id, created=True)


@router.post("/website/applications", response_model=IntegrationResult)
@limiter.limit(_LIMIT)
async def receive_website_application(request: Request) -> IntegrationResult:
    payload: WebsiteApplicationIn = _parse(WebsiteApplicationIn, await _verified_body(request))
    doc_id = f"website-{payload.source_id}"

    record = {
        # same shape as the Flutter Applicant model (models/applicant.dart)
        "id": doc_id,
        "name": payload.name.strip(),
        "email": payload.email.strip(),
        "phone": payload.phone.strip(),
        "address": payload.address.strip(),
        "driversLicense": payload.drivers_license.strip(),
        "vehicleInfo": payload.vehicle_info.strip(),
        "experience": payload.experience.strip(),
        "experienceDetails": payload.experience_details.strip(),
        "availability": payload.availability.strip(),
        "physicalCapability": payload.physical_capability.strip(),
        "resumeUrl": payload.resume_url.strip(),
        "status": "new",
        "ownerNotes": "",
        "createdAt": _created_at(payload.submitted_at),
        "source": "website",
        "sourceId": payload.source_id,
    }
    if not _create_once("applicants", doc_id, record):
        return IntegrationResult(ok=True, id=doc_id, created=False)
    if not _is_recent(record["createdAt"]):
        logger.info("Website integration: saved older applicant %s without notifications", doc_id)
        return IntegrationResult(ok=True, id=doc_id, created=True)

    owner = _owner_settings()
    company_name = (owner.get("company_name") or "").strip() or "our team"

    owner_phone = _to_e164(owner.get("phone", ""))
    if owner_phone:
        _try("owner new-applicant SMS", lambda: sms_service.send_templated_sms(owner_phone, "owner-new-applicant", {
            "name": record["name"],
            "phone": record["phone"] or "none",
            "email": record["email"] or "none",
            "availability": _truncate(record["availability"] or "not given", 80),
            "link": settings.frontend_base_url,
        }))
    owner_email = (owner.get("email") or "").strip()
    if owner_email:
        _try("owner new-applicant email", lambda: email_service.send_templated_email(
            owner_email, "owner-new-applicant", {
                "name": record["name"],
                "applicant_email": record["email"] or "no email given",
                "phone": record["phone"] or "no phone given",
                "availability": record["availability"] or "not given",
            }))
    if record["email"]:
        _try("application confirmation email", lambda: email_service.send_templated_email(
            record["email"], "application-received", {"name": record["name"], "company_name": company_name}))

    logger.info("Website integration: saved applicant %s", doc_id)
    return IntegrationResult(ok=True, id=doc_id, created=True)
