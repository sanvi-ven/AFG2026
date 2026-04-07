from pydantic import BaseModel
from typing import Optional

from app.models.enums import NotificationTarget
from app.schemas.common import TimestampedModel


class NotificationBase(BaseModel):
    business_id: str
    title: str
    body: str


class SingleNotificationCreate(NotificationBase):
    recipient_id: str


class BroadcastNotificationCreate(NotificationBase):
    target: NotificationTarget = NotificationTarget.ALL_CLIENTS


class NotificationRead(NotificationBase, TimestampedModel):
    id: str
    target: NotificationTarget
    recipient_id: Optional[str] = None
