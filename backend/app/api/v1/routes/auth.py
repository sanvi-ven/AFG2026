from fastapi import APIRouter, HTTPException, status
from firebase_admin import auth
from pydantic import BaseModel

from app.core.config import settings
from app.core.firebase import initialize_firebase_app
from app.models.enums import UserRole
from app.schemas.user import UserCreate, UserRead
from app.services.users_service import UsersService

router = APIRouter()
users_service = UsersService()


class GoogleAuthRequest(BaseModel):
    id_token: str


@router.post("/google", response_model=UserRead)
def google_sign_in(payload: GoogleAuthRequest) -> UserRead:
    try:
        initialize_firebase_app()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Firebase admin is not configured. Check service-account.json and FIREBASE_PROJECT_ID.",
        ) from exc

    if settings.dev_auth_bypass and payload.id_token.startswith("dev-"):
        role = UserRole.OWNER if payload.id_token == "dev-owner" else UserRole.CLIENT
        firebase_uid = payload.id_token
        email = f"{firebase_uid}@example.com"
        existing_dev_user = users_service.get_by_firebase_uid(firebase_uid)
        if existing_dev_user:
            return existing_dev_user

        return users_service.create_user(
            UserCreate(
                firebase_uid=firebase_uid,
                email=email,
                display_name="Demo User",
                role=role,
            )
        )

    try:
        claims = auth.verify_id_token(payload.id_token)
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

    existing_user = users_service.get_by_firebase_uid(firebase_uid)
    if existing_user:
        return existing_user

    display_name = claims.get("name") or str(email).split("@")[0]
    new_user = UserCreate(
        firebase_uid=firebase_uid,
        email=email,
        display_name=display_name,
        role=UserRole.CLIENT,
    )
    return users_service.create_user(new_user)
