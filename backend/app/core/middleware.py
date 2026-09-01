from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

# JSON routes (comms) have small, now-bounded payloads (see schemas/comms.py)
# — this is just a floor against something much larger than any legitimate
# request could ever be. photos/upload gets its own higher ceiling since it
# carries the actual image bytes (already capped at 10MB in photos.py; this
# just adds a little headroom for multipart overhead).
_DEFAULT_MAX_BYTES = 256 * 1024
_UPLOAD_MAX_BYTES = 11 * 1024 * 1024
_UPLOAD_PATH_SUFFIX = "/photos/upload"


class MaxBodySizeMiddleware(BaseHTTPMiddleware):
    """rejects a request upfront based on its declared Content-Length,
    before any route handler (or Pydantic validation) runs. Checks the
    header only — doesn't buffer/inspect the body itself, so it can't be
    fooled by an oversized body sent without a matching Content-Length, but
    that's an unusual enough client to not be worth the complexity of
    streaming enforcement for this app's actual traffic."""

    async def dispatch(self, request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length is not None:
            try:
                length = int(content_length)
            except ValueError:
                length = None
            if length is not None:
                limit = _UPLOAD_MAX_BYTES if request.url.path.endswith(_UPLOAD_PATH_SUFFIX) else _DEFAULT_MAX_BYTES
                if length > limit:
                    return JSONResponse(
                        status_code=413,
                        content={"detail": "Request body too large."},
                    )
        return await call_next(request)
