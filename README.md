# Small Biz Manager (MVP Scaffold)

Monorepo structure for a Flutter + FastAPI + Firebase full-stack app.

## Structure
- `frontend/` Flutter app scaffold (role-aware UI pages + responsive navigation)
- `backend/` FastAPI app scaffold (modular routes/services/repositories)
- `docs/` architecture and endpoint overview

## MVP Modules Included
- Authentication (Google Sign-In entry + role handling)
- Scheduling (appointments + availability)
- Financial (estimates/invoices data model)
- Messaging
- Notifications (single and broadcast)

## Run Order
1. Start backend from `backend/`
2. Initialize frontend from `frontend/`
3. Connect Firebase Auth and Firestore credentials

## Run Now (Demo Mode)
Demo mode is enabled by default so you can run and explore without Firebase setup.

### 1) Start backend
```bash
cd backend
../.venv/bin/python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

### 2) Start frontend (web)
```bash
cd frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### 3) Sign in
- Use **Demo Sign In as Business Owner** or **Demo Sign In as Client** on the login page.
- App will call `POST /api/v1/auth/google` with dev tokens (`dev-owner` / `dev-client`).

### Optional: Run on Android emulator
```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

See:
- `backend/README.md`
- `frontend/README.md`
- `docs/ARCHITECTURE.md`
