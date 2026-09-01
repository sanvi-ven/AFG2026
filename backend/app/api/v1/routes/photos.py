from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile, status

from app.core.rate_limit import limiter
from app.services.photo_service import PhotoService

router = APIRouter()
"""photo upload proxy to Cloudinary — the client can't hold the Cloudinary
API secret directly, so uploads route through here instead of straight from
Flutter the way Firebase Storage uploads used to. Still no real per-caller
auth (see core/rate_limit.py), so this is IP rate-limited and content-checked
as a stopgap against dumping arbitrary/oversized files into the Cloudinary
account."""
photo_service = PhotoService()

_MAX_UPLOAD_BYTES = 10 * 1024 * 1024


@router.post("/upload")
@limiter.limit("10/minute")
async def upload_photo(request: Request, file: UploadFile = File(...), folder: str = Form(...)) -> dict[str, str]:
    if not (file.content_type or "").startswith("image/"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only image uploads are allowed.")

    file_bytes = await file.read()
    if len(file_bytes) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Image is too large (10MB max).")

    try:
        url = photo_service.upload_photo(file_bytes, folder)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return {"url": url}
