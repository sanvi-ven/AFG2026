from datetime import datetime, timezone

from fastapi import APIRouter

from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.client_signup import ClientSignupCreate, ClientSignupRead

router = APIRouter()
repository = FirestoreRepository("client_signups")


@router.post("/client-signups", response_model=ClientSignupRead)
def create_client_signup(payload: ClientSignupCreate) -> ClientSignupRead:
    record = payload.model_dump()
    record["created_at"] = datetime.now(timezone.utc)
    saved = repository.create(record)
    return ClientSignupRead.model_validate(saved)