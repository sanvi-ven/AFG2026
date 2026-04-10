from datetime import date, datetime, time, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from google.oauth2 import service_account
from googleapiclient.discovery import build

from app.core.config import settings


class GoogleCalendarService:
    def __init__(self) -> None:
        self.scopes = [scope.strip() for scope in settings.google_calendar_scopes.split(",") if scope.strip()]

    def _build_client(self):
        credentials = service_account.Credentials.from_service_account_file(
            settings.google_service_account_path,
            scopes=self.scopes,
        )
        return build("calendar", "v3", credentials=credentials, cache_discovery=False)

    def get_available_slots(
        self,
        *,
        calendar_id: str,
        target_date: date,
        start_hour: int,
        end_hour: int,
        slot_minutes: int,
        time_zone: str,
    ) -> list[dict[str, str]]:
        try:
            tz = ZoneInfo(time_zone)
        except Exception:
            tz = timezone.utc

        day_start = datetime.combine(target_date, time(hour=start_hour, minute=0), tzinfo=tz)
        day_end = datetime.combine(target_date, time(hour=end_hour, minute=0), tzinfo=tz)

        service = self._build_client()

        events_result = (
            service.events()
            .list(
                calendarId=calendar_id,
                timeMin=day_start.isoformat(),
                timeMax=day_end.isoformat(),
                singleEvents=True,
                orderBy="startTime",
                maxResults=250,
            )
            .execute()
        )

        events = events_result.get("items", [])
        busy_intervals: list[tuple[datetime, datetime]] = []

        for item in events:
            start_value = item.get("start", {}).get("dateTime")
            end_value = item.get("end", {}).get("dateTime")
            if not start_value or not end_value:
                continue

            start_dt = datetime.fromisoformat(start_value.replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(end_value.replace("Z", "+00:00"))
            busy_intervals.append((start_dt, end_dt))

        slots: list[dict[str, str]] = []
        cursor = day_start
        delta = timedelta(minutes=slot_minutes)
        while cursor + delta <= day_end:
            slot_end = cursor + delta
            overlaps_busy = any(cursor < busy_end and slot_end > busy_start for busy_start, busy_end in busy_intervals)
            if not overlaps_busy:
                slots.append(
                    {
                        "start_time": cursor.astimezone(tz).strftime("%H:%M"),
                        "end_time": slot_end.astimezone(tz).strftime("%H:%M"),
                    }
                )
            cursor = slot_end

        return slots

    def create_event(
        self,
        *,
        calendar_id: str,
        summary: str,
        target_date: date,
        start_time: str,
        end_time: str,
        time_zone: str,
        description: Optional[str] = None,
        services: Optional[list[str]] = None,
        attendee_email: Optional[str] = None,
    ) -> dict:
        service = self._build_client()

        try:
            tz = ZoneInfo(time_zone)
        except Exception:
            tz = timezone.utc

        start_dt = datetime.strptime(f"{target_date.isoformat()} {start_time}", "%Y-%m-%d %H:%M").replace(tzinfo=tz)
        end_dt = datetime.strptime(f"{target_date.isoformat()} {end_time}", "%Y-%m-%d %H:%M").replace(tzinfo=tz)

        description_lines = [description.strip()] if description and description.strip() else []
        if services:
            cleaned_services = [service_name.strip() for service_name in services if service_name and service_name.strip()]
            if cleaned_services:
                description_lines.append(f"Services: {', '.join(cleaned_services)}")

        formatted_description = "\n".join(description_lines)

        body: dict = {
            "summary": summary,
            "description": formatted_description,
            "start": {"dateTime": start_dt.isoformat(), "timeZone": time_zone},
            "end": {"dateTime": end_dt.isoformat(), "timeZone": time_zone},
        }
        if attendee_email:
            body["attendees"] = [{"email": attendee_email}]

        return service.events().insert(calendarId=calendar_id, body=body).execute()