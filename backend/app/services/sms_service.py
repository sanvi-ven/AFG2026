from twilio.rest import Client

from app.core.config import settings

# Fixed templates for the pre-auth-reachable subset of /comms/sms — mirrors
# email_service.py's _TEMPLATES exactly: a pre-auth caller (the public
# "Request a Quote" form) can only select one of these and fill in named
# params, never compose free-text content. Every other SMS this app sends
# goes through send_sms with a caller-composed body from an
# owner-authenticated route, so it isn't listed here.
_TEMPLATES: dict[str, dict] = {
    "request-received": {
        "body": "{business_name}: Thanks for your request! We received it and will follow up soon. "
        "Reply STOP to opt out.",
        "params": {"business_name"},
    },
    # sent to the owner's own number (OwnerSettingsService.phone, resolved
    # client-side — never a caller-supplied `to`) whenever the public
    # request form is submitted, mirroring the existing owner-new-lead
    # EMAIL template but with the fields an owner needs to triage from a
    # phone: who, how they'd like to be reached, and a link back into the
    # app to see any attached photos.
    "owner-new-lead": {
        "body": "New request: {name} ({preferred_contact}). Phone: {phone}. Email: {email}. "
        "Address: {address}. \"{description}\" View: {link}",
        "params": {"name", "preferred_contact", "phone", "email", "address", "description", "link"},
    },
}


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

    def send_templated_sms(self, to: str, template: str, params: dict[str, str]) -> bool:
        spec = _TEMPLATES.get(template)
        if spec is None:
            raise ValueError(f"Unknown SMS template: {template}")

        missing = spec["params"] - params.keys()
        if missing:
            raise ValueError(f"Missing params for template '{template}': {sorted(missing)}")

        safe_params = {key: str(params.get(key, "")) for key in spec["params"]}
        body = spec["body"].format(**safe_params)
        return self.send_sms(to, body)
