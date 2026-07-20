from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status

from app.services.photo_service import PhotoService

router = APIRouter()
"""photo upload proxy to Cloudinary — the client can't hold the Cloudinary
API secret directly, so uploads route through here instead of straight from
Flutter the way Firebase Storage uploads used to"""
photo_service = PhotoService()


@router.post("/upload")
async def upload_photo(file: UploadFile = File(...), folder: str = Form(...)) -> dict[str, str]:
    file_bytes = await file.read()
    try:
        url = photo_service.upload_photo(file_bytes, folder)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return {"url": url}
