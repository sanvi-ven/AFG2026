# Backend (FastAPI)

## Quick Start
1. Create virtual environment
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Configure environment:
   - Copy `.env.example` to `.env`
   - Add your Firebase project settings and service account path
4. Run API:
   ```bash
   uvicorn app.main:app --reload
   ```

### Demo mode defaults
- `USE_MOCK_FIRESTORE=true`
- `DEV_AUTH_BYPASS=true`

With these defaults, backend runs without Firebase credentials and supports demo tokens:
- `dev-owner`
- `dev-client`

API docs: `http://127.0.0.1:8000/docs`

## Authentication & Roles
- Send Firebase ID token as bearer token: `Authorization: Bearer <id_token>`
- `POST /api/v1/auth/google` verifies token and auto-provisions a `client` user if first login
- Owner-only endpoints use role guard (`owner`):
   - `POST /api/v1/notifications/single`
   - `POST /api/v1/notifications/broadcast`
   - `POST /api/v1/appointments/{appointment_id}/sync-calendar`
   - `POST /api/v1/invoices`
   - `PATCH /api/v1/invoices/{invoice_id}/status`
   - `GET/POST /api/v1/users`, `PATCH /api/v1/users/{user_id}/role`

## Structure
- `app/api/v1/routes`: REST endpoints
- `app/services`: business logic
- `app/repositories`: Firestore data access
- `app/schemas`: typed contracts
- `app/models`: enums/domain constants
