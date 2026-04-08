from functools import lru_cache

import firebase_admin
from firebase_admin import credentials, firestore

from app.core.config import settings


def initialize_firebase_app() -> None:
    if firebase_admin._apps:
        return

    cred = credentials.Certificate(settings.google_service_account_path)
    firebase_admin.initialize_app(cred, {"projectId": settings.firebase_project_id})


@lru_cache
def get_firestore_client() -> firestore.Client:
    initialize_firebase_app()
    return firestore.client()
