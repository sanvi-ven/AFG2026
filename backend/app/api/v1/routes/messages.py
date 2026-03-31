from fastapi import APIRouter, Depends, Query
from typing import Optional

from app.api.deps.auth import get_current_user
from app.schemas.message import MessageCreate, MessageRead
from app.schemas.user import UserRead
from app.services.messages_service import MessagesService

router = APIRouter()
service = MessagesService()


@router.get("", response_model=list[MessageRead])
def list_messages(
    business_id: Optional[str] = Query(default=None),
    _: UserRead = Depends(get_current_user),
) -> list[MessageRead]:
    return service.list_messages(business_id=business_id)


@router.post("", response_model=MessageRead)
def create_message(payload: MessageCreate, _: UserRead = Depends(get_current_user)) -> MessageRead:
    return service.create_message(payload)
