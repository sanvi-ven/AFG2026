from fastapi import APIRouter, Depends

from app.api.deps.auth import require_owner
from app.schemas.notification import (
    BroadcastNotificationCreate,
    NotificationRead,
    SingleNotificationCreate,
)
from app.schemas.user import UserRead
from app.services.notifications_service import NotificationsService

router = APIRouter()
service = NotificationsService()


@router.post("/single", response_model=NotificationRead)
def send_single(payload: SingleNotificationCreate, _: UserRead = Depends(require_owner)) -> NotificationRead:
    return service.send_single(payload)


@router.post("/broadcast", response_model=NotificationRead)
def send_broadcast(
    payload: BroadcastNotificationCreate,
    _: UserRead = Depends(require_owner),
) -> NotificationRead:
    return service.send_broadcast(payload)
