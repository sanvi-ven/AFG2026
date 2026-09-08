import cloudinary
import cloudinary.uploader
import cloudinary.utils

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

    def upload_photo(
        self,
        file_bytes: bytes,
        folder: str,
        resource_type: str = "image",
        public_id: str | None = None,
    ) -> str:
        _ensure_configured()
        try:
            # for resource_type="raw" (PDFs), Cloudinary does NOT infer a
            # file extension from the actual content the way it does for
            # images (an image delivery URL gets .jpg/.png appended
            # automatically based on the detected format; a raw one doesn't,
            # unless the public_id itself carries the extension) - without
            # this, a PDF's delivery URL has no .pdf in it at all, and
            # browsers that can't sniff the content type render the raw
            # bytes as text instead of opening a PDF viewer. public_id is
            # only passed for raw uploads - image uploads keep their
            # existing Cloudinary-assigned ids unchanged.
            upload_kwargs = {"folder": folder, "resource_type": resource_type}
            if resource_type == "raw" and public_id:
                upload_kwargs["public_id"] = public_id
            result = cloudinary.uploader.upload(file_bytes, **upload_kwargs)
        except Exception as exc:
            # never surface the raw Cloudinary exception to a caller.
            # RuntimeError here is what /photos/upload already knows how to
            # turn into a clean 503.
            raise RuntimeError("Failed to upload photo.") from exc

        # NOTE on raw (PDF) delivery: the stored secure_url below is NOT
        # directly fetchable for resource_type="raw" on this account -
        # Cloudinary's "Restricted media types" account setting blocks
        # public delivery of raw files (confirmed live: 401, "x-cld-error:
        # deny or ACL failure"), and neither a signed CDN URL
        # (cloudinary.utils.cloudinary_url(..., sign_url=True)) nor HTTP
        # Basic Auth on that same CDN URL bypasses it - both tested live and
        # still 401. What DOES work is Cloudinary's separate Admin API
        # download endpoint (cloudinary.utils.private_download_url, served
        # from api.cloudinary.com rather than the res.cloudinary.com CDN) -
        # see get_contract_document_link() in routes/photos.py, which
        # generates a fresh one of those on demand. That endpoint's
        # signature is timestamp-bound, so it can't be generated once here
        # and cached in this URL - it must be requested fresh each time a
        # raw file is actually opened, which is exactly what that route
        # does using the public_id embedded in this stored URL.
        return result["secure_url"]

    def get_raw_download_link(self, public_id: str, format: str) -> str:
        """generates a fresh, signed Admin-API download link for a raw
        resource (served from api.cloudinary.com, not the restricted
        res.cloudinary.com CDN) — see upload_photo's doc comment for why
        this can't just be generated once and cached. The signature is
        timestamp-bound, so callers must request a new one each time the
        file is actually about to be opened, not reuse an old result."""
        _ensure_configured()
        return cloudinary.utils.private_download_url(
            public_id, format, resource_type="raw", type="upload"
        )
