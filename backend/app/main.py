from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.middleware import MaxBodySizeMiddleware
from app.core.rate_limit import limiter


def create_application() -> FastAPI:
    """create the fastapi app with cors middleware and routes"""
    # no interactive docs in production — this API has exactly one real
    # frontend, and a live Swagger "try it out" UI just hands anyone a
    # point-and-click way to probe /comms and /photos.
    app = FastAPI(title=settings.app_name, docs_url=None, redoc_url=None, openapi_url=None)
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_middleware(SlowAPIMiddleware)
    app.add_middleware(MaxBodySizeMiddleware)
    app.add_middleware(
        CORSMiddleware,
        # explicit origins only — "*" combined with credentials used to let any
        # site make credentialed calls to this API; this app authenticates via
        # a Bearer header, not cookies, so credentials were never needed anyway
        allow_origins=list(settings.allowed_origins),
        # only set when ALLOW_LOCALHOST_CORS=true (local dev) — Cloud Run
        # never sets it, so production never allows a localhost origin
        allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?" if settings.allow_localhost_cors else None,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(api_router, prefix=settings.api_v1_prefix)

    @app.get("/health", tags=["health"])
    def health_check() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_application()
