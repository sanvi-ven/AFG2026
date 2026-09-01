"""One-off: add a `profile_id` custom claim (the client_signups/employee_signups
doc id) alongside the existing `role` claim for every account that doesn't
already have one from a fresh /auth/complete-signup or /auth/claim-account
call.

Why: those two collections are the only ones with a real Firebase `uid`
field. Every other collection (estimates, invoices, time_entries, etc.)
identifies "whose record is this" by the old client_signups/employee_signups
doc id, not uid. The Firestore rules landing alongside this script compare
`resource.data.clientId`/`employeeId` against `request.auth.token.profile_id`
to scope a session to its own records — so every existing user needs that
claim set before the new rules go live, or their own reads/writes will fail
until they happen to re-signup (never) or this backfill runs (now).

Safe to re-run — always recomputes and re-sets the same {role, profile_id}
pair for a given doc, so a repeat run is a no-op in effect.

Run from backend/:
    ../.venv/bin/python scripts/backfill_profile_id_claims.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from firebase_admin import auth  # noqa: E402

from app.core.firebase import get_firestore_client, initialize_firebase_app  # noqa: E402


def _backfill_collection(db, collection_name: str, role: str) -> int:
    count = 0
    for doc in db.collection(collection_name).stream():
        data = doc.to_dict() or {}
        uid = data.get("uid")
        if not uid:
            continue  # never migrated / still an unclaimed dummy client — nothing to claim yet

        auth.set_custom_user_claims(uid, {"role": role, "profile_id": doc.id})
        count += 1
        print(f"  {collection_name}/{doc.id} -> uid {uid}: role={role} profile_id={doc.id}")
    return count


def main() -> None:
    initialize_firebase_app()
    db = get_firestore_client()

    print("Backfilling client_signups...")
    client_count = _backfill_collection(db, "client_signups", "client")

    print("Backfilling employee_signups...")
    employee_count = _backfill_collection(db, "employee_signups", "employee")

    print(f"\nSet profile_id on {client_count} client + {employee_count} employee accounts.")
    print("Owner account(s) untouched — owner-only rules check role, not profile_id.")


if __name__ == "__main__":
    main()
