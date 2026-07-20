import base64
import json
import os
from functools import lru_cache

import firebase_admin
from firebase_admin import credentials, firestore

from app.core.config import settings


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


@lru_cache
def get_firestore_client() -> firestore.Client:
    """get cached firestore client instance for initializing firebase"""
    initialize_firebase_app()
    return firestore.client()
