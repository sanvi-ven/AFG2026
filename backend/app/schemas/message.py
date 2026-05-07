from pydantic import BaseModel

from app.schemas.common import TimestampedModel


class MessageBase(BaseModel):
    """base message schema with business, sender, recipient, and text"""
    business_id: str
    sender_id: str
    recipient_id: str
    text: str


class MessageCreate(MessageBase):
    """create message payload"""
    pass


class MessageRead(MessageBase, TimestampedModel):
    """complete message response with id and read status"""
    id: str
    read: bool = False
