from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Request, status
from firebase_admin import auth, firestore

from app.core.config import settings
from app.core.firebase import require_firebase_app
from app.core.rate_limit import limiter
from app.models.enums import UserRole
from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.signup import ClaimAccountRequest, CompleteSignupRequest, SignupProfileResponse
from app.schemas.user import UserCreate
from app.services.users_service import UsersService

router = APIRouter()
"""account onboarding routes. complete-signup grants a role (a custom claim,
validated server-side) to an already-created Firebase Auth user and creates
their profile record; claim-account turns an owner-created dummy client into
a real login. Together these are the only place a role is ever assigned —
the client-side app never gets to just assert a role."""

users_service = UsersService()
client_repo = FirestoreRepository("client_signups")
employee_repo = FirestoreRepository("employee_signups")
invite_code_repo = FirestoreRepository("invite_codes")


def _verify_token(authorization: Optional[str]) -> dict:
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


@router.post("/complete-signup", response_model=SignupProfileResponse)
@limiter.limit("10/minute")
def complete_signup(
    request: Request,
    payload: CompleteSignupRequest,
    authorization: Optional[str] = Header(default=None),
) -> SignupProfileResponse:
    claims = _verify_token(authorization)
    uid = claims.get("uid")
    email = claims.get("email")
    if not uid or not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token is missing required claims",
        )
    email = str(email).strip().lower()

    if users_service.get_by_firebase_uid(uid):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This account has already completed signup.",
        )

    if payload.role == "owner":
        if email not in settings.owner_emails:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This email is not authorized for the owner role.",
            )
    elif payload.role == "employee":
        code = (payload.invite_code or "").strip().upper()
        if not code or not invite_code_repo.get_by_id(code):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="That invite code is invalid or no longer active.",
            )

    first_name = payload.first_name.strip()
    last_name = payload.last_name.strip()
    phone_number = payload.phone_number.strip()
    address = payload.address.strip()
    display_name = f"{first_name} {last_name}".strip() or email.split("@")[0]

    users_service.create_user(
        UserCreate(firebase_uid=uid, email=email, display_name=display_name, role=UserRole(payload.role))
    )

    if payload.role == "client":
        record = client_repo.create({
            "uid": uid,
            "email": email,
            "first_name": first_name,
            "last_name": last_name,
            "phone_number": phone_number,
            "address": address,
        })
    elif payload.role == "employee":
        record = employee_repo.create({
            "uid": uid,
            "email": email,
            "first_name": first_name,
            "last_name": last_name,
            "phone_number": phone_number,
            "teamId": None,
            "active": True,
        })
    else:
        # owner has no separate profile collection — the users record above
        # (email, display name, role) is the whole of their identity
        record = {"id": uid}

    # only this route can grant a role — the client sends what it wants but
    # every branch above either checks it against something server-side owns
    # (the owner allowlist, a real invite code) or is the open "client" case.
    # client/employee also get `profile_id`, the client_signups/employee_signups
    # doc id just created — Firestore rules use it to scope a session to its
    # own records, since those collections are keyed by client id, not uid.
    claims = {"role": payload.role}
    if payload.role in ("client", "employee"):
        claims["profile_id"] = record["id"]
    auth.set_custom_user_claims(uid, claims)

    return SignupProfileResponse(
        id=record["id"],
        uid=uid,
        role=payload.role,
        email=email,
        first_name=first_name,
        last_name=last_name,
        phone_number=phone_number,
        address=address,
    )


@router.post("/claim-account", response_model=SignupProfileResponse)
@limiter.limit("5/minute")
def claim_account(request: Request, payload: ClaimAccountRequest) -> SignupProfileResponse:
    require_firebase_app()

    code = payload.code.strip().upper()
    profile = client_repo.get_one_by_field("claim_code", code)
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="That claim code is invalid or has already been used.",
        )

    email = payload.email.strip().lower()
    existing_by_email = client_repo.get_one_by_field("email", email)
    if existing_by_email and existing_by_email.get("id") != profile.get("id"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with that email address already exists.",
        )

    try:
        user_record = auth.create_user(email=email, password=payload.password)
    except auth.EmailAlreadyExistsError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with that email address already exists.",
        ) from exc

    auth.set_custom_user_claims(user_record.uid, {"role": "client", "profile_id": profile["id"]})

    updated = client_repo.update(profile["id"], {
        "uid": user_record.uid,
        "email": email,
        "claim_code": firestore.DELETE_FIELD,
        "claim_code_created_at": firestore.DELETE_FIELD,
    })

    first_name = updated.get("first_name", "") or ""
    last_name = updated.get("last_name", "") or ""
    display_name = f"{first_name} {last_name}".strip() or email.split("@")[0]

    users_service.create_user(
        UserCreate(firebase_uid=user_record.uid, email=email, display_name=display_name, role=UserRole.CLIENT)
    )

    return SignupProfileResponse(
        id=updated["id"],
        uid=user_record.uid,
        role="client",
        email=email,
        first_name=first_name,
        last_name=last_name,
        phone_number=updated.get("phone_number", "") or "",
        address=updated.get("address", "") or "",
    )
