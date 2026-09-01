import cloudinary
import cloudinary.uploader

from app.core.config import settings

_configured = False


def _ensure_configured() -> None:
    global _configured
    if _configured:
        return
    if not (settings.cloudinary_cloud_name and settings.cloudinary_api_key and settings.cloudinary_api_secret):
        raise RuntimeError("Cloudinary settings are not configured")
    cloudinary.config(
        cloud_name=settings.cloudinary_cloud_name,
        api_key=settings.cloudinary_api_key,
        api_secret=settings.cloudinary_api_secret,
        secure=True,
    )
    _configured = True


class PhotoService:
    """uploads photos to cloudinary, mirroring the folder-per-entity
    convention previously used for Firebase Storage paths (job_photos/{workId}/{phase},
    request_photos/{requestId})"""

    def upload_photo(self, file_bytes: bytes, folder: str) -> str:
        _ensure_configured()
        try:
            result = cloudinary.uploader.upload(file_bytes, folder=folder, resource_type="image")
        except Exception as exc:
            # never surface the raw Cloudinary exception to a caller.
            # RuntimeError here is what /photos/upload already knows how to
            # turn into a clean 503.
            raise RuntimeError("Failed to upload photo.") from exc
        return result["secure_url"]
