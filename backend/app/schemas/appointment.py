from datetime import datetime
from typing import Optional

from pydantic import BaseModel

from app.models.enums import AppointmentStatus
from app.schemas.common import TimestampedModel


class AppointmentBase(BaseModel):
    """base appointment schema with business, client, and time window"""
    business_id: str
    client_id: str
    start_time: datetime
    end_time: datetime


class AppointmentCreate(AppointmentBase):
    """create appointment payload with optional notes"""
    notes: Optional[str] = None


class AppointmentUpdate(BaseModel):
    """update appointment payload with optional status and times"""
    status: Optional[AppointmentStatus] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None


class AppointmentRead(AppointmentBase, TimestampedModel):
    """complete appointment response with calendar integration info"""
    id: str
    status: AppointmentStatus
    notes: Optional[str] = None
    calendar_event_id: Optional[str] = None
