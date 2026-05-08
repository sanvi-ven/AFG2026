from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, status

from app.core.security import hash_password, verify_password
from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.client_signup import (
    ClientLoginRequest,
    ClientLoginResponse,
    ClientPasswordChangeRequest,
    ClientSignupCreateRequest,
    ClientSignupRead,
)

router = APIRouter()
repository = FirestoreRepository("client_signups")
credentials_repository = FirestoreRepository("client_credentials")


def _normalize_email(value: str) -> str:
    return value.strip().lower()


def _find_client_by_email(email: str) -> Optional[dict]:
    normalized_email = _normalize_email(email)
    for client in repository.list():
        client_email = client.get("email")
        if isinstance(client_email, str) and _normalize_email(client_email) == normalized_email:
            return client
    return None


def _find_credentials_by_email(email: str) -> Optional[dict]:
    normalized_email = _normalize_email(email)
    for credentials in credentials_repository.list():
        credentials_email = credentials.get("email")
        if isinstance(credentials_email, str) and _normalize_email(credentials_email) == normalized_email:
            return credentials
    return None


def _next_client_id() -> str:
    max_seen = 0
    for client in repository.list():
        raw_id = client.get("id")
        if not isinstance(raw_id, str):
            continue
        candidate = raw_id.strip()
        if len(candidate) != 5 or not candidate.isdigit():
            continue
        max_seen = max(max_seen, int(candidate))

    next_value = max_seen + 1
    if next_value > 99999:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Client signup capacity reached (99999).",
        )
    return f"{next_value:05d}"


@router.post("/client-signups", response_model=ClientSignupRead)
def create_client_signup(payload: ClientSignupCreateRequest) -> ClientSignupRead:
    if _find_client_by_email(payload.email):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with that email address already exists.",
        )

    normalized_email = _normalize_email(payload.email)
    now = datetime.now(timezone.utc)
    client_id = _next_client_id()
    credentials_repository.create_with_id(
        client_id,
        {
            "email": normalized_email,
            "password_hash": hash_password(payload.password),
            "created_at": now,
            "updated_at": now,
        },
    )

    record = payload.model_dump(exclude={"password"})
    record["email"] = normalized_email
    record["created_at"] = now
    saved = repository.create_with_id(client_id, record)
    return ClientSignupRead.model_validate(saved)


@router.post("/client-login", response_model=ClientLoginResponse)
def client_login(payload: ClientLoginRequest) -> ClientLoginResponse:
    client = _find_client_by_email(payload.email)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No client account found for that email.",
        )

    credentials = _find_credentials_by_email(payload.email)
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No password set for this account.",
        )

    password_hash = credentials.get("password_hash")
    if not isinstance(password_hash, str) or not verify_password(payload.password, password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect password.",
        )

    return ClientLoginResponse.model_validate(client)


@router.patch("/client-password")
def change_client_password(payload: ClientPasswordChangeRequest) -> dict[str, str]:
    credentials = _find_credentials_by_email(payload.email)
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No client account found for that email.",
        )

    existing_hash = credentials.get("password_hash")
    if not isinstance(existing_hash, str) or not verify_password(payload.old_password, existing_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect.",
        )

    if payload.old_password == payload.new_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be different from current password.",
        )

    credentials_id = credentials.get("id")
    if not isinstance(credentials_id, str) or not credentials_id.strip():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Client credentials are misconfigured.",
        )

    credentials_repository.update(
        credentials_id.strip(),
        {
            "password_hash": hash_password(payload.new_password),
            "updated_at": datetime.now(timezone.utc),
        },
    )

    return {"message": "Password updated."}
