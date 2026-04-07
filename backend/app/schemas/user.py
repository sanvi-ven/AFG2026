from pydantic import BaseModel, EmailStr

from app.models.enums import UserRole
from app.schemas.common import TimestampedModel


class UserBase(BaseModel):
    email: EmailStr
    display_name: str
    role: UserRole


class UserCreate(UserBase):
    firebase_uid: str


class UserUpdateRole(BaseModel):
    role: UserRole


class UserRead(UserBase, TimestampedModel):
    id: str
    firebase_uid: str
