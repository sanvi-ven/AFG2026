from typing import Optional

from app.repositories.firestore_repository import FirestoreRepository
from app.schemas.user import UserCreate, UserRead, UserUpdateRole


class UsersService:
    def __init__(self) -> None:
        self.repository = FirestoreRepository("users")

    def create_user(self, payload: UserCreate) -> UserRead:
        record = self.repository.create(payload.model_dump())
        return UserRead.model_validate(record)

    def list_users(self) -> list[UserRead]:
        return [UserRead.model_validate(row) for row in self.repository.list()]

    def update_role(self, user_id: str, payload: UserUpdateRole) -> UserRead:
        record = self.repository.update(user_id, payload.model_dump())
        return UserRead.model_validate(record)

    def get_by_firebase_uid(self, firebase_uid: str) -> Optional[UserRead]:
        record = self.repository.get_one_by_field("firebase_uid", firebase_uid)
        if not record:
            return None
        return UserRead.model_validate(record)
