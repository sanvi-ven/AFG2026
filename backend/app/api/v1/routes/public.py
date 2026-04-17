from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, status

from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.client_signup import (
    ClientLoginRequest,
    ClientLoginResponse,
    ClientSignupCreate,
    ClientSignupRead,
)

router = APIRouter()
repository = FirestoreRepository("client_signups")


def _normalize_email(value: str) -> str:
    return value.strip().lower()


def _find_client_by_email(email: str) -> Optional[dict]:
    normalized_email = _normalize_email(email)
    for client in repository.list():
        client_email = client.get("email")
        if isinstance(client_email, str) and _normalize_email(client_email) == normalized_email:
            return client
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
def create_client_signup(payload: ClientSignupCreate) -> ClientSignupRead:
    record = payload.model_dump()
    record["email"] = _normalize_email(record["email"])
    record["created_at"] = datetime.now(timezone.utc)
    client_id = _next_client_id()
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
    return ClientLoginResponse.model_validate(client)