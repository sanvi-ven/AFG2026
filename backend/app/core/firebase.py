from functools import lru_cache

import firebase_admin
from firebase_admin import credentials, firestore

from app.core.config import settings


@lru_cache
def get_firestore_client() -> firestore.Client:
    if not firebase_admin._apps:
        cred = credentials.Certificate(settings.google_service_account_path)
        firebase_admin.initialize_app(cred, {"projectId": settings.firebase_project_id})
    return firestore.client()
