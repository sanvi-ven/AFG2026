import io
from typing import Optional

from fastapi import APIRouter, File, Form, Header, HTTPException, Request, UploadFile, status
from firebase_admin import auth
from PIL import Image, UnidentifiedImageError

from app.core.firebase import require_firebase_app
from app.core.rate_limit import limiter
from app.services.photo_service import PhotoService

router = APIRouter()
"""photo upload proxy to Cloudinary — the client can't hold the Cloudinary
API secret directly, so uploads route through here instead of straight from
Flutter the way Firebase Storage uploads used to. The public "Request a
Quote" form uploads pre-auth (a brand-new lead attaching photos before any
account exists), so this can't require auth outright — instead, a pre-auth
call is only allowed to write into the `requests/` folder prefix; anything
else requires a real signed-in session."""
photo_service = PhotoService()

_MAX_UPLOAD_BYTES = 10 * 1024 * 1024
_PUBLIC_FOLDER_PREFIX = "request_photos/"


def _require_signed_in(authorization: Optional[str]) -> None:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()

    require_firebase_app()

    try:
        auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token",
        ) from exc


def _validate_real_image(file_bytes: bytes) -> None:
    """content-type headers are caller-supplied and trivially spoofed —
    actually decode the bytes as an image instead of trusting the label."""
    try:
        with Image.open(io.BytesIO(file_bytes)) as image:
            image.verify()
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File is not a valid image.",
        ) from exc


@router.post("/upload")
@limiter.limit("10/minute")
async def upload_photo(
    request: Request,
    file: UploadFile = File(...),
    folder: str = Form(...),
    authorization: Optional[str] = Header(default=None),
) -> dict[str, str]:
    if not folder.startswith(_PUBLIC_FOLDER_PREFIX):
        _require_signed_in(authorization)

    file_bytes = await file.read()
    if len(file_bytes) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Image is too large (10MB max).")

    _validate_real_image(file_bytes)

    try:
        url = photo_service.upload_photo(file_bytes, folder)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    return {"url": url}
