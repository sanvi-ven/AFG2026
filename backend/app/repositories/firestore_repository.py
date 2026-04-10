from uuid import uuid4
from typing import Optional

from google.cloud.firestore_v1.base_query import FieldFilter

from app.core.config import settings
from app.core.firebase import get_firestore_client


class FirestoreRepository:
    _memory_store: dict[str, dict[str, dict]] = {}

    def __init__(self, collection_name: str) -> None:
        self.collection_name = collection_name
        self.db = None
        if not settings.use_mock_firestore:
            try:
                self.db = get_firestore_client()
            except Exception as exc:
                raise RuntimeError(
                    "Firestore initialization failed while USE_MOCK_FIRESTORE=false. "
                    "Check FIREBASE_PROJECT_ID and GOOGLE_SERVICE_ACCOUNT_PATH."
                ) from exc

        if self.db is None and self.collection_name not in self._memory_store:
            self._memory_store[self.collection_name] = {}

    def create(self, payload: dict) -> dict:
        doc_id = str(uuid4())
        record = payload | {"id": doc_id}
        if self.db is None:
            self._memory_store[self.collection_name][doc_id] = record
            return record

        self.db.collection(self.collection_name).document(doc_id).set(record)
        return record

    def list(self, field_name: Optional[str] = None, equals: Optional[str] = None) -> list[dict]:
        if self.db is None:
            rows = list(self._memory_store[self.collection_name].values())
            if field_name and equals:
                return [row for row in rows if row.get(field_name) == equals]
            return rows

        collection = self.db.collection(self.collection_name)
        if field_name and equals:
            docs = collection.where(filter=FieldFilter(field_name, "==", equals)).stream()
        else:
            docs = collection.stream()
        return [doc.to_dict() for doc in docs]

    def update(self, doc_id: str, payload: dict) -> dict:
        if self.db is None:
            current = self._memory_store[self.collection_name].get(doc_id, {"id": doc_id})
            updated = current | payload | {"id": doc_id}
            self._memory_store[self.collection_name][doc_id] = updated
            return updated

        self.db.collection(self.collection_name).document(doc_id).set(payload, merge=True)
        doc = self.db.collection(self.collection_name).document(doc_id).get()
        return doc.to_dict() | {"id": doc_id}

    def get_one_by_field(self, field_name: str, equals: str) -> Optional[dict]:
        if self.db is None:
            for row in self._memory_store[self.collection_name].values():
                if row.get(field_name) == equals:
                    return row
            return None

        docs = (
            self.db.collection(self.collection_name)
            .where(filter=FieldFilter(field_name, "==", equals))
            .limit(1)
            .stream()
        )
        for doc in docs:
            return doc.to_dict()
        return None
