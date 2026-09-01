"""Sends the migration password-reset email to every account listed in
migration_report.json (produced by migrate_existing_accounts.py).

Deliberately a separate script from the migration itself — run this only
after the message below has been reviewed and approved; it sends real email
to real clients and employees.

Run from backend/:
    ../.venv/bin/python scripts/send_reset_emails.py
"""

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.email_service import EmailService  # noqa: E402

BUSINESS_NAME = "RP Landscaping"
SUBJECT = f"Action needed: reset your {BUSINESS_NAME} account password"


def _html_body(name: str, reset_link: str) -> str:
    return f"""
    <p>Hi {name},</p>
    <p>We upgraded the security of your {BUSINESS_NAME} online account today. As part of
    that change, you'll need to set a new password before you can log back in — your old
    password no longer works.</p>
    <p><a href="{reset_link}">Click here to set your new password</a></p>
    <p>If that link has expired by the time you click it, just use "Forgot password?" on the
    login page instead and we'll send a new one.</p>
    <p>Nothing else about your account or any of your existing invoices, estimates, or job
    history changed.</p>
    """


def main() -> None:
    report_path = Path(__file__).resolve().parent / "migration_report.json"
    report = json.loads(report_path.read_text())

    email_service = EmailService()
    for entry in report:
        email_service.send_email(entry["email"], SUBJECT, _html_body(entry["name"], entry["reset_link"]))
        print(f"  sent to {entry['email']} ({entry['role']})")
        time.sleep(0.5)

    print(f"\nSent {len(report)} reset emails.")


if __name__ == "__main__":
    main()
