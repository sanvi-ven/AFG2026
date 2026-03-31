from fastapi import APIRouter, Depends

from app.api.deps.auth import get_current_user, require_owner
from app.schemas.user import UserCreate, UserRead, UserUpdateRole
from app.services.users_service import UsersService

router = APIRouter()
service = UsersService()


@router.get("", response_model=list[UserRead])
def list_users(_: UserRead = Depends(require_owner)) -> list[UserRead]:
    return service.list_users()


@router.post("", response_model=UserRead)
def create_user(payload: UserCreate, _: UserRead = Depends(require_owner)) -> UserRead:
    return service.create_user(payload)


@router.patch("/{user_id}/role", response_model=UserRead)
def update_user_role(
    user_id: str,
    payload: UserUpdateRole,
    _: UserRead = Depends(require_owner),
) -> UserRead:
    return service.update_role(user_id, payload)
