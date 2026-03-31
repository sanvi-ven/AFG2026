from pydantic import BaseModel

from app.schemas.common import TimestampedModel


class MessageBase(BaseModel):
    business_id: str
    sender_id: str
    recipient_id: str
    text: str


class MessageCreate(MessageBase):
    pass


class MessageRead(MessageBase, TimestampedModel):
    id: str
    read: bool = False
