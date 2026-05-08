from pydantic import BaseModel, EmailStr

from app.models.enums import UserRole
from app.schemas.common import TimestampedModel


class UserBase(BaseModel):
    """base user schema with email, display name, and role"""
    email: EmailStr
    display_name: str
    role: UserRole


class UserCreate(UserBase):
    """create user payload with firebase uid"""
    firebase_uid: str


class UserUpdateRole(BaseModel):
    """update user role payload"""
    role: UserRole


class UserRead(UserBase, TimestampedModel):
    """complete user response with id, firebase uid, and timestamps"""
    id: str
    firebase_uid: str
