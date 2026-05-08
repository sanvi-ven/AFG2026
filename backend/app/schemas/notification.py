from pydantic import BaseModel
from typing import Optional

from app.models.enums import NotificationTarget
from app.schemas.common import TimestampedModel


class NotificationBase(BaseModel):
    """base notification schema with business, title, and body"""
    business_id: str
    title: str
    body: str


class SingleNotificationCreate(NotificationBase):
    """create single notification for specific recipient"""
    recipient_id: str


class BroadcastNotificationCreate(NotificationBase):
    """create broadcast notification for all clients"""
    target: NotificationTarget = NotificationTarget.ALL_CLIENTS


class NotificationRead(NotificationBase, TimestampedModel):
    """complete notification response with target and optional recipient"""
    id: str
    target: NotificationTarget
    recipient_id: Optional[str] = None
