from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """application settings and configuration from environment"""
    app_name: str = "Anchor API"
    api_v1_prefix: str = "/api/v1"
    firebase_project_id: str = "afg2026a"
    google_service_account_path: str = "service-account.json"
    use_mock_firestore: bool = False
    dev_auth_bypass: bool = False

    # CORS allowlist — comma-separated in the env var, e.g.
    # "https://anchor-orpin.vercel.app,https://your-custom-domain.com".
    # Local dev origins (localhost/127.0.0.1, any port) are always allowed
    # separately via allow_origin_regex in main.py, so they don't belong here.
    allowed_origins_raw: str = "https://anchor-orpin.vercel.app"

    # emails allowed to claim the "owner" role on signup — comma-separated.
    # nobody else can self-assign owner no matter what they send the API.
    owner_emails_raw: str = "immc17289@gmail.com"

    resend_api_key: str = ""
    resend_from_email: str = ""

    cloudinary_cloud_name: str = ""
    cloudinary_api_key: str = ""
    cloudinary_api_secret: str = ""

    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_from_number: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def allowed_origins(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins_raw.split(",") if origin.strip()]

    @property
    def owner_emails(self) -> list[str]:
        return [email.strip().lower() for email in self.owner_emails_raw.split(",") if email.strip()]

    @model_validator(mode="after")
    def _forbid_dev_bypass_against_real_firestore(self) -> "Settings":
        # dev_auth_bypass exists only so local dev can hit the API without a
        # real Firebase token when there's no real Firestore behind it either
        # (USE_MOCK_FIRESTORE=true). The two must never be enabled together —
        # that combination means fake auth tokens granting access to real
        # business data, which is exactly the gap this check exists to close.
        if self.dev_auth_bypass and not self.use_mock_firestore:
            raise RuntimeError(
                "DEV_AUTH_BYPASS=true is not allowed while USE_MOCK_FIRESTORE=false. "
                "Refusing to start: this combination would let anyone in with a "
                "fake 'dev-owner'/'dev-employee'/'dev-client' token against real data."
            )
        return self


settings = Settings()
