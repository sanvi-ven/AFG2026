from typing import Optional

from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.message import MessageCreate, MessageRead


class MessagesService:
    def __init__(self) -> None:
        self.repository = FirestoreRepository("messages")

    def create_message(self, payload: MessageCreate) -> MessageRead:
        record = payload.model_dump()
        record["read"] = False
        saved = self.repository.create(record)
        return MessageRead.model_validate(saved)

    def list_messages(self, business_id: Optional[str] = None) -> list[MessageRead]:
        rows = self.repository.list("business_id", business_id) if business_id else self.repository.list()
        return [MessageRead.model_validate(row) for row in rows]
