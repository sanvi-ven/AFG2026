from datetime import date
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, status

from app.core.config import settings
from app.schemas.google_calendar import (
    AvailabilitySlotsResponse,
    AvailableSlot,
    BookCalendarEventRequest,
    BookCalendarEventResponse,
)
from app.services.google_calendar_service import GoogleCalendarService

router = APIRouter()
service = GoogleCalendarService()


@router.get("/availability/slots", response_model=AvailabilitySlotsResponse)
def get_availability_slots(
    date_value: date = Query(alias="date"),
    start_hour: int = Query(default=8, ge=0, le=23),
    end_hour: int = Query(default=21, ge=1, le=24),
    slot_minutes: int = Query(default=30, ge=5, le=180),
    time_zone: str = Query(default="UTC"),
    calendar_id: Optional[str] = Query(default=None),
) -> AvailabilitySlotsResponse:
    if end_hour <= start_hour:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="end_hour must be greater than start_hour",
        )

    resolved_calendar_id = calendar_id or settings.google_booking_calendar_id
    if not resolved_calendar_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing calendar_id. Set GOOGLE_BOOKING_CALENDAR_ID or pass calendar_id query.",
        )

    try:
        slots = service.get_available_slots(
            calendar_id=resolved_calendar_id,
            target_date=date_value,
            start_hour=start_hour,
            end_hour=end_hour,
            slot_minutes=slot_minutes,
            time_zone=time_zone,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Google Calendar availability failed: {exc}",
        ) from exc

    return AvailabilitySlotsResponse(
        date=date_value.isoformat(),
        calendar_id=resolved_calendar_id,
        time_zone=time_zone,
        slot_minutes=slot_minutes,
        slots=[AvailableSlot.model_validate(item) for item in slots],
    )


@router.post("/book", response_model=BookCalendarEventResponse)
def book_calendar_event(
    payload: BookCalendarEventRequest,
    time_zone: str = Query(default="UTC"),
    calendar_id: Optional[str] = Query(default=None),
) -> BookCalendarEventResponse:
    resolved_calendar_id = calendar_id or settings.google_booking_calendar_id
    if not resolved_calendar_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing calendar_id. Set GOOGLE_BOOKING_CALENDAR_ID or pass calendar_id query.",
        )

    try:
        event = service.create_event(
            calendar_id=resolved_calendar_id,
            summary=payload.summary,
            target_date=date.fromisoformat(payload.date),
            start_time=payload.start_time,
            end_time=payload.end_time,
            time_zone=time_zone,
            description=payload.description,
            attendee_email=payload.attendee_email,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Google Calendar booking failed: {exc}",
        ) from exc

    return BookCalendarEventResponse(
        event_id=event.get("id", ""),
        html_link=event.get("htmlLink"),
        status=event.get("status", "unknown"),
    )