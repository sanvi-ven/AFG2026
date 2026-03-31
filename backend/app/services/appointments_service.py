from typing import Optional

from app.models.enums import AppointmentStatus
from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.appointment import AppointmentCreate, AppointmentRead, AppointmentUpdate


class AppointmentsService:
    def __init__(self) -> None:
        self.repository = FirestoreRepository("appointments")

    def create_appointment(self, payload: AppointmentCreate) -> AppointmentRead:
        record = payload.model_dump()
        record["status"] = AppointmentStatus.PENDING
        saved = self.repository.create(record)
        return AppointmentRead.model_validate(saved)

    def list_appointments(self, business_id: Optional[str] = None) -> list[AppointmentRead]:
        rows = self.repository.list("business_id", business_id) if business_id else self.repository.list()
        return [AppointmentRead.model_validate(row) for row in rows]

    def update_appointment(self, appointment_id: str, payload: AppointmentUpdate) -> AppointmentRead:
        updated = self.repository.update(appointment_id, payload.model_dump(exclude_none=True))
        return AppointmentRead.model_validate(updated)

    def sync_to_google_calendar(self, appointment_id: str) -> dict[str, str]:
        return {"appointment_id": appointment_id, "status": "queued_for_calendar_sync"}
