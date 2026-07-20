from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """application settings and configuration from environment"""
    app_name: str = "Anchor API"
    api_v1_prefix: str = "/api/v1"
    firebase_project_id: str = "afg2026a"
    google_service_account_path: str = "service-account.json"
    google_calendar_scopes: str = "https://www.googleapis.com/auth/calendar"
    google_booking_calendar_id: str = "immc17289@gmail.com"
    use_mock_firestore: bool = False
    dev_auth_bypass: bool = False

    resend_api_key: str = ""
    resend_from_email: str = ""

    cloudinary_cloud_name: str = ""
    cloudinary_api_key: str = ""
    cloudinary_api_secret: str = ""

    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_from_number: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
