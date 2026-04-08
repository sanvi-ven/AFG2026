from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Small Biz Manager API"
    api_v1_prefix: str = "/api/v1"
    firebase_project_id: str = "afg2026a"
    google_service_account_path: str = "service-account.json"
    google_calendar_scopes: str = "https://www.googleapis.com/auth/calendar"
    google_booking_calendar_id: str = "91d01c09dd4283d77beb10f68e45025941f605469166cfef41609db2a78932bd@group.calendar.google.com"
    use_mock_firestore: bool = True
    dev_auth_bypass: bool = True

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
