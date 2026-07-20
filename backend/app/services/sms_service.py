from twilio.rest import Client

from app.core.config import settings


class SmsService:
    """sends sms via Twilio"""

    def send_sms(self, to: str, body: str) -> bool:
        if not (settings.twilio_account_sid and settings.twilio_auth_token and settings.twilio_from_number):
            raise RuntimeError("Twilio settings are not configured")

        client = Client(settings.twilio_account_sid, settings.twilio_auth_token)
        client.messages.create(to=to, from_=settings.twilio_from_number, body=body)
        return True
