from twilio.rest import Client

from app.core.config import settings


class SmsService:
    """sends sms via Twilio"""

    def send_sms(self, to: str, body: str) -> bool:
        if not (settings.twilio_account_sid and settings.twilio_auth_token and settings.twilio_from_number):
            raise RuntimeError("Twilio settings are not configured")

        client = Client(settings.twilio_account_sid, settings.twilio_auth_token)
        try:
            client.messages.create(to=to, from_=settings.twilio_from_number, body=body)
        except Exception as exc:
            # never surface the raw Twilio exception to a caller — it can
            # include account-identifying details. RuntimeError here is what
            # the /sms route already knows how to turn into a clean 503.
            raise RuntimeError("Failed to send SMS.") from exc
        return True
