# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Anchor" (repo/GitHub name `AFG2026`) is a small-business field-service CRM: appointments, estimates, invoices, jobs/scheduling, equipment tracking, client/employee messaging. It's currently being run for the user's landscaping business, but nothing in the code is landscaping-specific — business branding (company name, address, logo, PDF filename templates) is configurable per-tenant via Owner Settings.

Stack: Flutter frontend (`frontend/`) + FastAPI backend (`backend/`). The frontend is backed directly by the `afg2026a` Firebase project (Firestore + Firebase Auth), deployed via Vercel (`vercel.json` + `build.sh`) at `anchor-orpin.vercel.app`. The backend is a **separate GCP project** (`project-d977b7e6-dcb5-4209-aa0`, "My First Project") running Cloud Run service `anchor-backend` in `us-central1` — see "Deployment & secrets" below, this split matters for anyone trying to find/deploy the backend.

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
- Frontend: pushing to `main` triggers Vercel, which runs `bash build.sh` (root or `frontend/vercel.json`) and serves `frontend/build/web` at `anchor-orpin.vercel.app`.
- Firestore rules: `firebase deploy --only firestore:rules --project afg2026a`. Storage rules (`storage.rules`) are registered in `firebase.json` too, but **Firebase Storage is not actually provisioned on this project** (zero buckets exist, confirmed via `gcloud storage buckets list --project afg2026a`) — `firebase deploy --only storage` will fail until/unless Storage is set up via the Firebase console. The rules file is kept up to date anyway in case that ever changes; don't assume it's live.
- Backend: **not on Vercel** — it's Cloud Run service `anchor-backend` in GCP project `project-d977b7e6-dcb5-4209-aa0`, region `us-central1`, deployed from the `backend/Dockerfile`. Deploy with:
  ```bash
  gcloud run deploy anchor-backend --source backend --region us-central1 --project project-d977b7e6-dcb5-4209-aa0
  ```
  `immc17289@gmail.com` has `roles/owner` on that GCP project (and is also the Firebase project's owner, and the account behind the `firebase-tools`/`gcloud` CLI logins noted in memory) — that's the account to deploy as. Live URL: `https://anchor-backend-1001439279043.us-central1.run.app`. **Cold starts are slow** (the dependency chain — firebase-admin/grpc — takes a while to import; this was true before any recent changes and isn't a bug in new code) — a `curl` right after deploy may need 30–60s before the first request returns, `/health` is the quickest way to check it's actually up.

### Secrets (backend, on Cloud Run)
As of 2026-09-01, the credential-shaped env vars (`RESEND_API_KEY`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `GOOGLE_SERVICE_ACCOUNT_JSON_BASE64`) live in **Google Secret Manager** on the backend's GCP project (`project-d977b7e6-dcb5-4209-aa0`), not as plaintext Cloud Run env vars — secret names match the env var name in kebab-case (e.g. `RESEND_API_KEY` → secret `resend-api-key`). The Cloud Run runtime service account (`1001439279043-compute@developer.gserviceaccount.com`) has `roles/secretmanager.secretAccessor` on each. Non-secret config (`FIREBASE_PROJECT_ID`, `USE_MOCK_FIRESTORE`, `DEV_AUTH_BYPASS`, `RESEND_FROM_EMAIL`, `CLOUDINARY_CLOUD_NAME`, `TWILIO_FROM_NUMBER`, `ALLOWED_ORIGINS_RAW`) stays as plain env vars. A redeploy that changes code but not config should pass `--update-secrets`/`--set-env-vars` again (or copy them from the current revision) — `gcloud run deploy --source ...` without those flags will **not** carry them forward automatically on a source-only deploy in all cases; verify with:
```bash
gcloud run services describe anchor-backend --region us-central1 --project project-d977b7e6-dcb5-4209-aa0 --format="value(spec.template.spec.containers[0].env.list())"
```
This should show `valueFrom.secretKeyRef` for the six credential vars, never a raw value — if it ever shows a plaintext value for one of those six, that's a regression of the 2026-09-01 Secret Manager migration.

## Architecture

### Two parallel data-access paths — know which one a feature actually uses
This is the single most important thing to understand before touching a feature. There are two completely separate ways the frontend reaches data, and most features use only one:

1. **Direct Flutter ↔ Firestore** (`package:cloud_firestore`), via `*_service.dart` files in `frontend/lib/core/services/` (e.g. `client_profile_service.dart`, `invoice_service.dart`, `estimate_service.dart`, `scheduled_work_service.dart`, `equipment_service.dart`, `team_service.dart`, `time_entry_service.dart`, `message_service.dart`, `notification_service.dart`, `owner_settings_service.dart`, etc.). This is how essentially **all** real feature pages read/write data today — clients, jobs, invoices, estimates, equipment, employees, teams, time tracking, expenses, notifications, in-app messages, requests, service catalog, checklists.
2. **FastAPI backend via `ApiClient`** (`frontend/lib/core/services/api_client.dart`, plain `http` calls to `$API_BASE_URL/api/v1/...`). In the current frontend this is only actually wired up for `CommsService` (transactional email/SMS via `/comms`, which holds Resend/Twilio keys server-side) and photo upload (`job_photo_upload_service.dart` → `/photos/upload`, which holds the Cloudinary secret server-side).

As of 2026-09-01, the backend **only implements what's actually reachable**: `auth` (`/auth/google`, unused by the live frontend today but kept — see Auth model below), `comms` (`/comms/email`, `/comms/sms`), and `photos` (`/photos/upload`). A large REST+Firestore-repository CRUD layer for appointments/invoices/messages/notifications/users, a Google Calendar booking API, and a second (bcrypt-based, `core/security.py`) client-auth implementation used to exist here — all confirmed unreachable from the shipped frontend (it talks to differently-named Firestore collections directly instead, e.g. jobs live in `scheduled_work` via `scheduled_work_service.dart`, not the old `appointments` route) — and were deleted rather than secured, since securing dead code has no payoff. `docs/ARCHITECTURE.md` and `docs/technical/PROJECT_MAP.md` describe that earlier, more backend-centric design and are now doubly stale — don't trust them as current. When asked to change how a feature reads/writes data, `grep` that feature's `presentation/*.dart` file's imports first to see which of the two paths it's actually on.

### Auth model — there is still no server-verified identity for most of the app
**This is the single biggest thing to understand before touching auth, Firestore rules, or any backend route.** A security hardening pass landed 2026-09-01 (see below), but it was deliberately scoped to config/infra fixes and dead-code removal — it did **not** touch the actual login flows, and the root problem is unchanged:
- **Owner** sign-in (`owner_signin_page.dart`) checks the entered password against a hardcoded string literal in the Dart source. No Firebase, no backend call.
- **Client** sign-in (`ClientAuthService`) is custom: SHA-256-hashed password stored as a plain field on the client's `client_signups` Firestore document, hashed and compared entirely client-side in Dart.
- **Employee** sign-in follows the same Firestore-document pattern as client.
- The app's real entry point is `_SessionGate` in `frontend/lib/app.dart`, which restores a role (`owner`/`client`/`employee`) from local device storage (`SessionPersistenceService`) and threads it through routes as a plain string, alongside a synthetic `dev-owner`/`dev-employee`/`dev-client` token. There is no cryptographic proof of role anywhere in this path.

Because of this, `firestore.rules` is still intentionally wide open (`allow read, write: if true`) for nearly every collection — there's no server-verified session for security rules to check roles against, and the in-file comments say so explicitly. **If asked to "restrict X to owners only" or "add a security check," the honest options are: gate it in the UI only (matches the app's current trust model), or point out that doing it properly requires wiring the collection through real Firebase Auth + rules first — don't silently add a client-side-only check and imply it's secure.** The real fix (Firebase Auth for all three roles + a rules rewrite keyed on it) is a planned but not-yet-started follow-up phase — ask before assuming it's safe to build on top of a "logged in" state as if it were verified.

**What the 2026-09-01 pass did fix**, so as not to re-litigate: CORS (`backend/app/main.py` now allows only `settings.allowed_origins` + a localhost regex, `allow_credentials=False`, instead of `"*"` + credentials); `DEV_AUTH_BYPASS` now has a startup guard in `core/config.py` (`Settings._forbid_dev_bypass_against_real_firestore`) that refuses to boot if it's `true` alongside `USE_MOCK_FIRESTORE=false` — and it's confirmed `false` in the live Cloud Run env regardless; `/comms/*` and `/photos/upload` are IP rate-limited (`core/rate_limit.py`, `slowapi`) and photo upload now rejects non-image/oversized files — these are stopgaps against unauthenticated abuse, not real auth, since neither route has ever received a caller identity to check. `get_current_user`/`require_owner` in `backend/app/api/deps/auth.py` still exist and still work (real Firebase ID token verification, plus the `dev-*` bypass) but nothing calls them today — they're there for whenever the real auth migration wires a route through them.

### Backend layering
Standard layered FastAPI structure: `api/v1/routes/*.py` (request/response, now just `auth.py`/`comms.py`/`photos.py`) → `services/*.py` (business logic) → `repositories/firestore_repository.py` (generic Firestore CRUD, with an in-memory dict fallback when `USE_MOCK_FIRESTORE=true`, used only by `users_service.py` today) → `schemas/*.py` (pydantic models). `core/config.py` (`Settings`, env-driven, see Auth model above for the dev-bypass guard), `core/firebase.py` (lazy Firebase Admin init, supports both a checked-in `service-account.json` and a base64 env var for Cloud Run), and `core/rate_limit.py` (the shared `slowapi` `Limiter` instance) are shared across routes.

### Frontend layering
`lib/features/<feature>/presentation/*.dart` (pages/widgets) → `lib/core/services/*.dart` (data access — Firestore directly or `ApiClient`, per feature) → `lib/models/*.dart` (plain Dart model classes with `fromMap`/`toMap`/`fromJson`). Routing is a single `switch` in `lib/core/router/app_router.dart` (`AppRouter.onGenerateRoute`); role and `authToken` are passed as route arguments (a `Map<String, dynamic>`), not read from any global auth state, so a page's access to "current role" is whatever the caller happened to pass in. Global mutable session state (`ClientSession`, `EmployeeSession`, `OwnerSession` in `lib/core/state/`) is `ValueNotifier`-based and used for cross-cutting concerns like the notification listeners in `app.dart`, separate from the per-route role/token arguments.

Platform-conditional code (CSV/PDF download, Google Calendar embedding) is split into `_io.dart`/`_web.dart`/`_stub.dart` variants per service (e.g. `csv_download_service_web.dart` vs `_io.dart`) selected via conditional imports from the non-suffixed file — follow that pattern for anything else that needs to behave differently on web vs. native.
