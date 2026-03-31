from fastapi import APIRouter, Depends, Query
from typing import Optional

from app.api.deps.auth import get_current_user, require_owner
from app.schemas.appointment import AppointmentCreate, AppointmentRead, AppointmentUpdate
from app.schemas.user import UserRead
from app.services.appointments_service import AppointmentsService

router = APIRouter()
service = AppointmentsService()


@router.get("", response_model=list[AppointmentRead])
def list_appointments(
    business_id: Optional[str] = Query(default=None),
    _: UserRead = Depends(get_current_user),
) -> list[AppointmentRead]:
    return service.list_appointments(business_id=business_id)


@router.post("", response_model=AppointmentRead)
def create_appointment(
    payload: AppointmentCreate,
    _: UserRead = Depends(get_current_user),
) -> AppointmentRead:
    return service.create_appointment(payload)


@router.patch("/{appointment_id}", response_model=AppointmentRead)
def update_appointment(
    appointment_id: str,
    payload: AppointmentUpdate,
    _: UserRead = Depends(get_current_user),
) -> AppointmentRead:
    return service.update_appointment(appointment_id, payload)


@router.post("/{appointment_id}/sync-calendar")
def sync_calendar(
    appointment_id: str,
    _: UserRead = Depends(require_owner),
) -> dict[str, str]:
    return service.sync_to_google_calendar(appointment_id)
