"""One-off (but safe to re-run): seed/reset the app's three legal documents
(privacy policy, terms of service, employee data notice) in Firestore from
the source-of-truth text files in docs/legal/.

These documents are editable by the owner from the app itself (Owner
Settings -> Manage Legal Documents) once seeded — this script is only for
initial setup or resetting a document back to the checked-in draft text if
it's ever edited into a bad state. Re-running always overwrites the current
Firestore content with whatever is in docs/legal/ right now, so don't run
this after the owner has made real edits they want to keep unless you mean
to discard those edits.

Run from backend/:
    ../.venv/bin/python scripts/seed_legal_documents.py
"""

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.firebase import get_firestore_client, initialize_firebase_app  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LEGAL_DIR = REPO_ROOT / "docs" / "legal"

DOCUMENTS = [
    ("privacy_policy", "Privacy Policy", "privacy-policy.txt"),
    ("terms_of_service", "Terms of Service", "terms-of-service.txt"),
    ("employee_data_notice", "Employee Data Privacy Notice", "employee-data-notice.txt"),
]


def main() -> None:
    initialize_firebase_app()
    db = get_firestore_client()
    collection = db.collection("legal_documents")

    for doc_id, title, filename in DOCUMENTS:
        path = LEGAL_DIR / filename
        content = path.read_text(encoding="utf-8").strip()
        collection.document(doc_id).set(
            {
                "id": doc_id,
                "title": title,
                "content": content,
                "updatedAt": datetime.now(timezone.utc),
            },
            merge=True,
        )
        print(f"Seeded legal_documents/{doc_id} ({len(content)} chars) from {filename}")

    print("\nDone. These are now editable from Owner Settings -> Manage Legal Documents.")


if __name__ == "__main__":
    main()
