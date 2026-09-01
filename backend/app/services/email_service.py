import html

import resend

from app.core.config import settings

# Fixed templates for everything the public /comms/email route can send —
# subject/body live here, server-side, never accepted from a caller. This is
# what actually closes the "arbitrary HTML to arbitrary recipient" hole: a
# pre-auth caller can only select one of these four templates and fill in
# named params (which get HTML-escaped below), never compose real content.
_TEMPLATES: dict[str, dict] = {
    "request-confirmation": {
        "subject": "We received your request",
        "body": (
            "<p>Hi {name},</p>"
            "<p>Thanks for reaching out — we received your request and will "
            "follow up with a quote soon.</p>"
        ),
        "params": {"name"},
    },
    "owner-new-lead": {
        "subject": "New work request from {name}",
        "body": "<p>New request from {name} ({client_email}).</p><p>{description}</p>",
        "params": {"name", "client_email", "description"},
    },
    "appointment-reminder": {
        "subject": "Upcoming appointment reminder",
        "body": (
            "<p>Hi {client_name},</p>"
            "<p>This is a reminder that your appointment for Estimate "
            "#{estimate_number} is coming up soon.</p>"
        ),
        "params": {"client_name", "estimate_number"},
    },
    "invoice-reminder": {
        "subject": "Invoice {invoice_number} — payment reminder",
        "body": (
            "<p>Hi {client_name},</p>"
            "<p>This is a reminder that invoice {invoice_number} for "
            "${total} is still outstanding.</p>"
        ),
        "params": {"client_name", "invoice_number", "total"},
    },
}


class EmailService:
    """sends transactional email via Resend."""

    def send_email(self, to: str, subject: str, html_body: str) -> bool:
        """low-level send with caller-supplied subject/body. Only ever call
        this from trusted server-side code (one-off scripts run directly by
        the developer/owner) — the public API never exposes this shape,
        since arbitrary HTML content is exactly what made /comms/email
        abusable before this file added templates. Use
        send_templated_email for anything reachable from a route."""
        if not settings.resend_api_key:
            raise RuntimeError("RESEND_API_KEY is not configured")

        resend.api_key = settings.resend_api_key
        try:
            resend.Emails.send({
                "from": settings.resend_from_email or "onboarding@resend.dev",
                "to": [to],
                "subject": subject,
                "html": html_body,
            })
        except Exception as exc:
            # never surface the raw Resend exception to a caller. RuntimeError
            # here is what the /email route already knows how to turn into a
            # clean 503 — without this, anything Resend raises that isn't a
            # RuntimeError (e.g. its own ResendError) falls through as an
            # uncaught 500 instead.
            raise RuntimeError("Failed to send email.") from exc
        return True

    def send_templated_email(self, to: str, template: str, params: dict[str, str]) -> bool:
        spec = _TEMPLATES.get(template)
        if spec is None:
            raise ValueError(f"Unknown email template: {template}")

        missing = spec["params"] - params.keys()
        if missing:
            raise ValueError(f"Missing params for template '{template}': {sorted(missing)}")

        # escape every param — the template scaffold itself is trusted HTML,
        # anything a caller supplied is not
        safe_params = {key: html.escape(str(params.get(key, ""))) for key in spec["params"]}
        subject = spec["subject"].format(**safe_params)
        html_body = spec["body"].format(**safe_params)
        return self.send_email(to, subject, html_body)
