from fastapi import APIRouter

from app.api.v1.routes import (
    auth,
    comms,
    contracts,
    photos,
)

'''aggregates all v1 api route routers with prefixes and tags'''
api_router = APIRouter()
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(comms.router, prefix="/comms", tags=["comms"])
api_router.include_router(contracts.router, prefix="/contracts", tags=["contracts"])
api_router.include_router(photos.router, prefix="/photos", tags=["photos"])
