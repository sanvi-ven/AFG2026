import base64
import json
import logging
import os
from functools import lru_cache

import firebase_admin
from fastapi import HTTPException, status
from firebase_admin import credentials, firestore

from app.core.config import settings

logger = logging.getLogger(__name__)


def initialize_firebase_app() -> None:
    """initialize firebase admin sdk with credentials from a service account
    file (local dev) or a base64-encoded env var (Cloud Run, which has no
    persistent filesystem to check a service-account.json into)"""
    if firebase_admin._apps:
        return

    encoded = os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON_BASE64")
    if encoded:
        info = json.loads(base64.b64decode(encoded))
        cred = credentials.Certificate(info)
    else:
        cred = credentials.Certificate(settings.google_service_account_path)

    firebase_admin.initialize_app(cred, {"projectId": settings.firebase_project_id})


def require_firebase_app() -> None:
    """initialize_firebase_app(), turning any failure into a safe, generic
    HTTPException. The real error (e.g. a missing/misconfigured local
    service-account.json) is logged server-side only — every route that
    used to inline this try/except returned the specific local filename
    convention straight to the caller, which is a small but pointless
    disclosure for something that's never actually the caller's problem."""
    try:
        initialize_firebase_app()
    except Exception:
        logger.exception("Firebase admin failed to initialize")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server configuration error.",
        )


@lru_cache
def get_firestore_client() -> firestore.Client:
    """get cached firestore client instance for initializing firebase"""
    initialize_firebase_app()
    return firestore.client()
