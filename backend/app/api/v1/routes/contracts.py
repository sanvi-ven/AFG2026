import secrets
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Request, status
from firebase_admin import auth

from app.core.config import settings as app_settings
from app.core.firebase import require_firebase_app
from app.core.rate_limit import limiter
from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.contracts import GuardianContractView, GuardianSignRequest, SendGuardianLinkResult
from app.services.email_service import EmailService

router = APIRouter()
"""guardian co-sign flow for a minor employee's employment contract. The
guardian never has a Firebase Auth account and never logs in, so this is the
one place in the backend — alongside /auth/claim-account's shape — where a
caller with no session at all is allowed to read and write one specific
Firestore record, gated by a mailed one-time token rather than a bearer
token. Everything else here (issuing the token, sending the email) requires
a real session: the owner, or the contract's own employee."""

email_service = EmailService()
contracts_repo = FirestoreRepository("employment_contracts")
amendments_repo = FirestoreRepository("contract_amendments")
employees_repo = FirestoreRepository("employee_signups")
owner_settings_repo = FirestoreRepository("owner_settings")

_TOKEN_TTL_DAYS = 14
_GUARDIAN_LINK_LIMIT = "20/hour"
_GUARDIAN_VIEW_LIMIT = "30/minute"
_GUARDIAN_SIGN_LIMIT = "10/minute"


def _verify_claims(authorization: Optional[str]) -> dict:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    require_firebase_app()
    try:
        return auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token",
        ) from exc


def _require_owner_or_own_employee(authorization: Optional[str], employee_id: str) -> None:
    claims = _verify_claims(authorization)
    role = claims.get("role")
    if role == "owner":
        return
    if role == "employee" and claims.get("profile_id") == employee_id:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized for this contract")


def _company_name() -> str:
    settings_doc = owner_settings_repo.get_by_id("default") or {}
    return (settings_doc.get("company_name") or "our company").strip()


def _employee_name(employee_id: str) -> str:
    employee = employees_repo.get_by_id(employee_id) or {}
    name = f"{employee.get('first_name', '')} {employee.get('last_name', '')}".strip()
    return name or employee.get("email", "This employee")


def _find_by_token(token: str) -> tuple[str, dict, FirestoreRepository]:
    """returns (kind, record, repo) where kind is 'contract' or 'amendment'"""
    contract = contracts_repo.get_one_by_field("guardianSignToken", token)
    if contract is not None:
        return "contract", contract, contracts_repo
    amendment = amendments_repo.get_one_by_field("guardianInitialToken", token)
    if amendment is not None:
        return "amendment", amendment, amendments_repo
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="This link is not valid.")


def _check_not_expired(record: dict, kind: str) -> None:
    expires_field = "guardianSignTokenExpiresAt" if kind == "contract" else "guardianInitialTokenExpiresAt"
    expires_at = record.get(expires_field)
    if expires_at is None:
        return
    # firestore admin sdk returns timezone-aware datetimes; strip tzinfo to
    # compare against the naive utcnow() this route writes everywhere else
    expires_naive = expires_at.replace(tzinfo=None) if expires_at.tzinfo else expires_at
    if datetime.utcnow() > expires_naive:
        raise HTTPException(status_code=status.HTTP_410_GONE, detail="This link has expired.")


@router.get("/guardian-view", response_model=GuardianContractView)
@limiter.limit(_GUARDIAN_VIEW_LIMIT)
def guardian_view(request: Request, token: str) -> GuardianContractView:
    kind, record, _ = _find_by_token(token)
    _check_not_expired(record, kind)

    employee_name = _employee_name(record["employeeId"])
    if kind == "contract":
        already_signed = record.get("guardianSignature") is not None
        return GuardianContractView(
            employee_name=employee_name,
            company_name=_company_name(),
            content=record.get("content", ""),
            already_signed=already_signed,
        )

    already_signed = record.get("guardianInitials") is not None
    return GuardianContractView(
        employee_name=employee_name,
        company_name=_company_name(),
        content=record.get("fullContentSnapshot", ""),
        changed_sections=record.get("changedSections", []),
        already_signed=already_signed,
    )


@router.post("/guardian-sign", response_model=SendGuardianLinkResult)
@limiter.limit(_GUARDIAN_SIGN_LIMIT)
def guardian_sign(request: Request, payload: GuardianSignRequest) -> SendGuardianLinkResult:
    kind, record, repo = _find_by_token(payload.token)
    _check_not_expired(record, kind)

    signature_field = "guardianSignature" if kind == "contract" else "guardianInitials"
    employee_field = "employeeSignature" if kind == "contract" else "employeeInitials"
    fully_status = "fully_signed" if kind == "contract" else "fully_initialed"
    pending_employee_status = (
        "pending_employee_signature" if kind == "contract" else "pending_employee_initial"
    )
    # the employee can sign/initial before or after the guardian - there's
    # nothing that forces the guardian's emailed link to be opened second -
    # so the status after the guardian acts must reflect whether the
    # employee side is already done too, not just "guardian required".
    employee_already_done = record.get(employee_field) is not None
    new_status = fully_status if employee_already_done else pending_employee_status

    # idempotent on repeat submits — a guardian re-clicking an old email tab
    # after already signing should see success again, not an error. Also
    # opportunistically fixes status here if an older bug ever left it out
    # of sync (previously: signing order guardian-then-employee could leave
    # status stuck on "pending guardian" forever even once both had signed).
    if record.get(signature_field) is not None:
        if record.get("status") != new_status:
            repo.update(record["id"], {"status": new_status})
        return SendGuardianLinkResult(sent=True)

    signature_payload = {
        "method": payload.method,
        "typedName": payload.typed_name.strip(),
        "drawingBase64": payload.drawing_base64.strip(),
        "consentText": payload.consent_text.strip(),
        "signedAt": datetime.utcnow(),
    }
    repo.update(record["id"], {signature_field: signature_payload, "status": new_status})
    return SendGuardianLinkResult(sent=True)


@router.post("/{record_id}/send-guardian-link", response_model=SendGuardianLinkResult)
@limiter.limit(_GUARDIAN_LINK_LIMIT)
def send_guardian_link(
    request: Request,
    record_id: str,
    authorization: Optional[str] = Header(default=None),
) -> SendGuardianLinkResult:
    # record_id may be an employment_contracts doc id or a contract_amendments
    # doc id — the amendment flow reuses this same endpoint (see CLAUDE.md/
    # the approved plan: "the same token/route mechanism generalizes")
    contract = contracts_repo.get_by_id(record_id)
    if contract is not None:
        kind, record, repo = "contract", contract, contracts_repo
    else:
        amendment = amendments_repo.get_by_id(record_id)
        if amendment is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contract not found.")
        kind, record, repo = "amendment", amendment, amendments_repo

    _require_owner_or_own_employee(authorization, record["employeeId"])

    guardian_email = (record.get("guardianEmail") or "").strip()
    if not guardian_email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No guardian email on file for this employee.",
        )

    token = secrets.token_urlsafe(32)
    expires_at = datetime.utcnow() + timedelta(days=_TOKEN_TTL_DAYS)
    token_field = "guardianSignToken" if kind == "contract" else "guardianInitialToken"
    expires_field = "guardianSignTokenExpiresAt" if kind == "contract" else "guardianInitialTokenExpiresAt"
    sent_field = "guardianSignTokenSentAt" if kind == "contract" else "guardianInitialTokenSentAt"
    reminder_count = int(record.get("guardianReminderCount", 0)) + 1

    repo.update(record_id, {
        token_field: token,
        expires_field: expires_at,
        sent_field: datetime.utcnow(),
        "guardianReminderCount": reminder_count,
    })

    sign_url = f"{app_settings.frontend_base_url}/contracts/guardian-sign?token={token}"
    try:
        email_service.send_templated_email(
            guardian_email,
            "guardian-contract-signature",
            {
                "employee_name": _employee_name(record["employeeId"]),
                "company_name": _company_name(),
                "sign_url": sign_url,
                "expires_date": expires_at.strftime("%B %-d, %Y"),
            },
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    return SendGuardianLinkResult(sent=True)
