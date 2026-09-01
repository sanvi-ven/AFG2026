# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Anchor" (repo/GitHub name `AFG2026`) is a small-business field-service CRM: appointments, estimates, invoices, jobs/scheduling, equipment tracking, client/employee messaging. It's currently being run for the user's landscaping business, but nothing in the code is landscaping-specific — business branding (company name, address, logo, PDF filename templates) is configurable per-tenant via Owner Settings.

Stack: Flutter frontend (`frontend/`) + FastAPI backend (`backend/`), both backed by a single Firebase project (Firestore + Firebase Auth), deployed via Vercel (frontend, `vercel.json` + `build.sh`) and presumably Cloud Run/Docker (backend, `backend/Dockerfile`).

**Read this whole file before making auth/security changes** — the auth model is not what it looks like from the folder structure (see "Auth model" below).

## Commands

### Frontend (Flutter, from `frontend/`)
```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000   # run against local backend
flutter analyze                                                          # lint (flutter_lints)
flutter test                                                             # runs frontend/test/widget_test.dart (only test in the repo)
flutter test test/widget_test.dart                                      # single test file
flutter build web --release --dart-define=API_BASE_URL=<url>            # production web build (what build.sh does)
```
Useful `--dart-define` flags read by `frontend/lib/core/config/app_config.dart`:
- `API_BASE_URL` — FastAPI base URL (default `http://127.0.0.1:8000`)
- `DEMO_ROLE` — `owner`/`client`/`employee`; when set, `AnchorApp` skips login entirely and opens `DashboardPage` directly with a fake `dev-*` token
- `DEMO_AUTH_TOKEN` — override the fake token sent alongside `DEMO_ROLE`

### Backend (FastAPI, from `backend/`)
```bash
python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
cp .env.example .env               # then fill in as needed; USE_MOCK_FIRESTORE=true + DEV_AUTH_BYPASS=true works with no Firebase creds at all
uvicorn app.main:app --reload --port 8000
```
There are no backend tests in the repo. `.env` and `service-account.json` are gitignored — never commit or print their contents.

### Deploy
- Frontend: pushing to `main` triggers Vercel, which runs `bash build.sh` (root or `frontend/vercel.json`) and serves `frontend/build/web`.
- Firestore rules: `firebase deploy --only firestore:rules` (or paste `firestore.rules` into the Firebase console — see `docs/VERCEL_DEPLOYMENT.md` for the history of why this mattered).
- Backend: containerized via `backend/Dockerfile` (`uvicorn app.main:app`, reads `$PORT`); on a filesystem-less host it expects `GOOGLE_SERVICE_ACCOUNT_JSON_BASE64` instead of a checked-in `service-account.json`.

## Architecture

### Two parallel data-access paths — know which one a feature actually uses
This is the single most important thing to understand before touching a feature. There are two completely separate ways the frontend reaches data, and most features use only one:

1. **Direct Flutter ↔ Firestore** (`package:cloud_firestore`), via `*_service.dart` files in `frontend/lib/core/services/` (e.g. `client_profile_service.dart`, `invoice_service.dart`, `estimate_service.dart`, `scheduled_work_service.dart`, `equipment_service.dart`, `team_service.dart`, `time_entry_service.dart`, `message_service.dart`, `notification_service.dart`, `owner_settings_service.dart`, etc.). This is how essentially **all** real feature pages read/write data today — clients, jobs, invoices, estimates, equipment, employees, teams, time tracking, expenses, notifications, in-app messages, requests, service catalog, checklists.
2. **FastAPI backend via `ApiClient`** (`frontend/lib/core/services/api_client.dart`, plain `http` calls to `$API_BASE_URL/api/v1/...`). In the current frontend this is only actually wired up for: `CommsService` (transactional email/SMS via `/comms`, which holds Resend/Twilio keys server-side) and Google Calendar/OAuth-adjacent flows. `AuthGate` + `AuthRepository` (`/auth/google`) also use it but `AuthGate` is **not** referenced from `app.dart`/the router — it's dead code, not the app's actual entry point.

The backend (`backend/app/api/v1/routes/{appointments,invoices,messages,notifications,users}.py` + matching services/repositories) implements a full REST+Firestore-repository CRUD layer for appointments, invoices, messages, notifications, and users — but the frontend doesn't call most of it; it talks to differently-named Firestore collections directly instead (e.g. jobs live in the `scheduled_work` collection via `scheduled_work_service.dart`, not the backend's `appointments`). Treat `docs/ARCHITECTURE.md` and `docs/technical/PROJECT_MAP.md` as describing an earlier, more backend-centric design that the frontend has since diverged from — don't trust them as current without checking the actual imports in the page you're editing. When asked to change how a feature reads/writes data, `grep` that feature's `presentation/*.dart` file's imports first to see which of the two paths it's actually on.

### Auth model — there is no server-verified identity for most of the app
Firebase Auth + Google Sign-In exists in the codebase (`frontend/lib/core/services/firebase_service.dart`, backend `POST /auth/google`, `get_current_user`/`require_owner` deps in `backend/app/api/deps/auth.py`), but it is **not** how users actually sign in today:
- **Owner** sign-in (`owner_signin_page.dart`) checks the entered password against a hardcoded string literal in the Dart source. No Firebase, no backend call.
- **Client** sign-in (`ClientAuthService`) is custom: SHA-256-hashed password stored as a plain field on the client's `client_signups` Firestore document, hashed and compared entirely client-side in Dart. The backend's `passlib`/bcrypt `core/security.py` is unrelated/unused by this flow.
- **Employee** sign-in follows the same Firestore-document pattern as client.
- The app's real entry point is `_SessionGate` in `frontend/lib/app.dart`, which restores a role (`owner`/`client`/`employee`) from local device storage (`SessionPersistenceService`) and threads it through routes as a plain string, alongside a synthetic `dev-owner`/`dev-employee`/`dev-client` token — the same fake tokens the backend's `dev_auth_bypass` setting is designed to accept. There is no cryptographic proof of role anywhere in this path.

Because of this, `firestore.rules` is intentionally wide open (`allow read, write: if true`) for nearly every collection — there's no server-verified session for security rules to check roles against, and the in-file comments say so explicitly. **If asked to "restrict X to owners only" or "add a security check," the honest options are: gate it in the UI only (matches the app's current trust model), or point out that doing it properly requires wiring the collection through real Firebase Auth + rules first — don't silently add a client-side-only check and imply it's secure.**

### Backend layering (for the parts of the backend that are actually used)
Standard layered FastAPI structure: `api/v1/routes/*.py` (request/response) → `services/*.py` (business logic) → `repositories/firestore_repository.py` (generic Firestore CRUD, with an in-memory dict fallback when `USE_MOCK_FIRESTORE=true`) → `schemas/*.py` (pydantic models). `core/config.py` (`Settings`, env-driven) and `core/firebase.py` (lazy Firebase Admin init, supports both a checked-in `service-account.json` and a base64 env var for Cloud Run) are shared across all routes.

### Frontend layering
`lib/features/<feature>/presentation/*.dart` (pages/widgets) → `lib/core/services/*.dart` (data access — Firestore directly or `ApiClient`, per feature) → `lib/models/*.dart` (plain Dart model classes with `fromMap`/`toMap`/`fromJson`). Routing is a single `switch` in `lib/core/router/app_router.dart` (`AppRouter.onGenerateRoute`); role and `authToken` are passed as route arguments (a `Map<String, dynamic>`), not read from any global auth state, so a page's access to "current role" is whatever the caller happened to pass in. Global mutable session state (`ClientSession`, `EmployeeSession`, `OwnerSession` in `lib/core/state/`) is `ValueNotifier`-based and used for cross-cutting concerns like the notification listeners in `app.dart`, separate from the per-route role/token arguments.

Platform-conditional code (CSV/PDF download, Google Calendar embedding) is split into `_io.dart`/`_web.dart`/`_stub.dart` variants per service (e.g. `csv_download_service_web.dart` vs `_io.dart`) selected via conditional imports from the non-suffixed file — follow that pattern for anything else that needs to behave differently on web vs. native.
