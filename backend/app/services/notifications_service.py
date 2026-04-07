from app.models.enums import NotificationTarget
from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.notification import (
    BroadcastNotificationCreate,
    NotificationRead,
    SingleNotificationCreate,
)


class NotificationsService:
    def __init__(self) -> None:
        self.repository = FirestoreRepository("notifications")

    def send_single(self, payload: SingleNotificationCreate) -> NotificationRead:
        record = payload.model_dump()
        record["target"] = NotificationTarget.SINGLE
        saved = self.repository.create(record)
        return NotificationRead.model_validate(saved)

    def send_broadcast(self, payload: BroadcastNotificationCreate) -> NotificationRead:
        record = payload.model_dump()
        record["target"] = NotificationTarget.ALL_CLIENTS
        saved = self.repository.create(record)
        return NotificationRead.model_validate(saved)
