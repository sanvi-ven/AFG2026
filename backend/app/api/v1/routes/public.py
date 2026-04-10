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


@router.post("/client-signups", response_model=ClientSignupRead)
def create_client_signup(payload: ClientSignupCreate) -> ClientSignupRead:
    record = payload.model_dump()
    record["email"] = _normalize_email(record["email"])
    record["created_at"] = datetime.now(timezone.utc)
    saved = repository.create(record)
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