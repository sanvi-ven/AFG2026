from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from app.core.config import settings
from app.core.firebase import initialize_firebase_app
from app.models.enums import UserRole
from app.schemas.user import UserCreate, UserRead
from app.services.users_service import UsersService

security = HTTPBearer(auto_error=True)
users_service = UsersService()


def _parse_display_name(claims: dict) -> str:
    display_name = claims.get("name")
    if display_name and isinstance(display_name, str):
        return display_name

    email = claims.get("email")
    if email and isinstance(email, str):
        return email.split("@")[0]

    return "User"


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> UserRead:
    token = credentials.credentials

    try:
        initialize_firebase_app()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Firebase admin is not configured. Check service-account.json and FIREBASE_PROJECT_ID.",
        ) from exc

    if settings.dev_auth_bypass and token.startswith("dev-"):
        role = UserRole.OWNER if token == "dev-owner" else UserRole.CLIENT
        existing_dev_user = users_service.get_by_firebase_uid(token)
        if existing_dev_user:
            return existing_dev_user
        return users_service.create_user(
            UserCreate(
                firebase_uid=token,
                email=f"{token}@example.com",
                display_name="Demo User",
                role=role,
            )
        )

    try:
        claims = auth.verify_id_token(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token",
        ) from exc

    firebase_uid = claims.get("uid")
    email = claims.get("email")
    if not firebase_uid or not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token is missing required claims",
        )

    user = users_service.get_by_firebase_uid(firebase_uid)
    if user:
        return user

    payload = UserCreate(
        firebase_uid=firebase_uid,
        email=email,
        display_name=_parse_display_name(claims),
        role=UserRole.CLIENT,
    )
    return users_service.create_user(payload)


def require_owner(current_user: UserRead = Depends(get_current_user)) -> UserRead:
    if current_user.role != UserRole.OWNER:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Owner role required",
        )
    return current_user
