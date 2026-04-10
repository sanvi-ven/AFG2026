from pydantic import BaseModel, Field
from typing import List, Optional


class AvailableSlot(BaseModel):
    start_time: str
    end_time: str


class AvailabilitySlotsResponse(BaseModel):
    date: str
    calendar_id: str
    time_zone: str
    slot_minutes: int
    slots: list[AvailableSlot]


class BookCalendarEventRequest(BaseModel):
    summary: str = Field(min_length=1)
    date: str = Field(description="YYYY-MM-DD")
    start_time: str = Field(description="HH:MM (24-hour)")
    end_time: str = Field(description="HH:MM (24-hour)")
    description: Optional[str] = None
    services: Optional[List[str]] = None
    attendee_email: Optional[str] = None


class BookCalendarEventResponse(BaseModel):
    event_id: str
    html_link: Optional[str] = None
    status: str