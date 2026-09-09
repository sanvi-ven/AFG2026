"""One-off: set sms_opt_in=True on every existing employee_signups doc.

Why: the sms_opt_in field on EmployeeProfile is new (added alongside the
employee-signup checkbox and the employee-facing SMS features — shift
reminders, job-assignment texts, contract-signature reminders). Every
employee account created before this field existed would otherwise default
to sms_opt_in=false, even though the owner already asked each of them
directly and they all verbally agreed to receive these texts. New employees
signing up after this change get a real, unchecked-by-default checkbox of
their own (see employee_signup_page.dart) — this script is only for the
already-existing roster, run once.

Only touches docs where sms_opt_in is not already set, so it's safe to
re-run (a no-op on a second pass) and won't stomp a preference an employee
has since changed themselves via Employee Settings.

Run from backend/:
    ../.venv/bin/python scripts/backfill_employee_sms_optin.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.firebase import get_firestore_client, initialize_firebase_app  # noqa: E402


def main() -> None:
    initialize_firebase_app()
    db = get_firestore_client()

    updated = 0
    skipped = 0
    for doc in db.collection("employee_signups").stream():
        data = doc.to_dict() or {}
        if "sms_opt_in" in data:
            skipped += 1
            continue
        doc.reference.set({"sms_opt_in": True}, merge=True)
        updated += 1
        print(f"  employee_signups/{doc.id} ({data.get('email', '?')}): sms_opt_in -> True")

    print(f"\nOpted in {updated} existing employee account(s); {skipped} already had a preference set.")


if __name__ == "__main__":
    main()
