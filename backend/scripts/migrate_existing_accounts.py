"""One-off migration: give every existing client/employee account (and the
owner) a real Firebase Auth identity, replacing the old unsalted-SHA-256-in-
Firestore password check.

For every client_signups/employee_signups doc that has a password_hash
(i.e. a real account someone has actually signed up with — NOT an
owner-created "dummy" client waiting to be claimed, those are untouched and
stay claimable exactly as before via the app's claim-account flow):
  - create a Firebase Auth user for that email with a random password
    nobody will ever know (a one-time reset is how they get in afterward)
  - set the matching role custom claim
  - write the new uid back onto the Firestore doc
  - strip password_hash from the doc — Firebase Auth owns credentials now
  - generate (but do NOT send) a password-reset link

Also creates a fresh Firebase Auth account for the owner (there's no
existing Firestore doc for the owner to migrate from).

Idempotent — skips any doc that already has a uid, safe to re-run.

Writes a JSON report (email, name, reset link) and stops. Nothing is
emailed by this script; sending is a deliberate separate step so the
message can be reviewed first.

Run from backend/:
    ../.venv/bin/python scripts/migrate_existing_accounts.py
"""

import json
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from firebase_admin import auth, firestore  # noqa: E402

from app.core.firebase import get_firestore_client, initialize_firebase_app  # noqa: E402

OWNER_EMAIL = "immc17289@gmail.com"


def _random_password() -> str:
    return secrets.token_urlsafe(32)


def _migrate_collection(db, collection_name: str, role: str, report: list) -> None:
    for doc in db.collection(collection_name).stream():
        data = doc.to_dict() or {}
        if data.get("uid"):
            continue  # already migrated

        password_hash = data.get("password_hash")
        if not password_hash:
            continue  # dummy/unclaimed client — leave for the claim-account flow

        email = (data.get("email") or "").strip().lower()
        if not email:
            print(f"  SKIP {collection_name}/{doc.id}: no email on record")
            continue

        first_name = data.get("first_name", "") or ""
        last_name = data.get("last_name", "") or ""
        name = f"{first_name} {last_name}".strip() or email.split("@")[0]

        try:
            user_record = auth.create_user(email=email, password=_random_password())
        except auth.EmailAlreadyExistsError:
            user_record = auth.get_user_by_email(email)

        auth.set_custom_user_claims(user_record.uid, {"role": role})
        reset_link = auth.generate_password_reset_link(email)

        db.collection(collection_name).document(doc.id).set(
            {"uid": user_record.uid, "password_hash": firestore.DELETE_FIELD},
            merge=True,
        )

        report.append({
            "collection": collection_name,
            "doc_id": doc.id,
            "role": role,
            "email": email,
            "name": name,
            "reset_link": reset_link,
        })
        print(f"  migrated {collection_name}/{doc.id} ({email}) -> uid {user_record.uid}")


def _migrate_owner(report: list) -> None:
    try:
        user_record = auth.get_user_by_email(OWNER_EMAIL)
        print(f"  owner account already exists (uid {user_record.uid})")
    except auth.UserNotFoundError:
        user_record = auth.create_user(email=OWNER_EMAIL, password=_random_password())
        print(f"  created owner account uid {user_record.uid}")

    auth.set_custom_user_claims(user_record.uid, {"role": "owner"})
    reset_link = auth.generate_password_reset_link(OWNER_EMAIL)

    report.append({
        "collection": "(owner)",
        "doc_id": user_record.uid,
        "role": "owner",
        "email": OWNER_EMAIL,
        "name": "Owner",
        "reset_link": reset_link,
    })


def main() -> None:
    initialize_firebase_app()
    db = get_firestore_client()

    report: list = []

    print("Migrating client_signups...")
    _migrate_collection(db, "client_signups", "client", report)

    print("Migrating employee_signups...")
    _migrate_collection(db, "employee_signups", "employee", report)

    print("Creating owner account...")
    _migrate_owner(report)

    report_path = Path(__file__).resolve().parent / "migration_report.json"
    report_path.write_text(json.dumps(report, indent=2))

    print(f"\nMigrated {len(report)} accounts. Report written to {report_path}.")
    print("Nothing was emailed. Review the report, then run send_reset_emails.py separately.")


if __name__ == "__main__":
    main()
