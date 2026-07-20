from fastapi import APIRouter

from app.api.v1.routes import (
    appointments,
    auth,
    comms,
    google_calendar,
    invoices,
    messages,
    notifications,
    photos,
    public,
    users,
)

'''aggregates all v1 api route routers with prefixes and tags'''
api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(public.router, prefix="/public", tags=["public"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(google_calendar.router, prefix="/calendar", tags=["calendar"])
api_router.include_router(appointments.router, prefix="/appointments", tags=["appointments"])
api_router.include_router(invoices.router, prefix="/invoices", tags=["invoices"])
api_router.include_router(messages.router, prefix="/messages", tags=["messages"])
api_router.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
api_router.include_router(comms.router, prefix="/comms", tags=["comms"])
api_router.include_router(photos.router, prefix="/photos", tags=["photos"])
