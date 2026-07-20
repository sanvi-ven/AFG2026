import resend

from app.core.config import settings


class EmailService:
    """sends transactional email via Resend"""

    def send_email(self, to: str, subject: str, html_body: str) -> bool:
        if not settings.resend_api_key:
            raise RuntimeError("RESEND_API_KEY is not configured")

        resend.api_key = settings.resend_api_key
        resend.Emails.send({
            "from": settings.resend_from_email or "onboarding@resend.dev",
            "to": [to],
            "subject": subject,
            "html": html_body,
        })
        return True
