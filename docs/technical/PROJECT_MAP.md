# Project Map

This document explains what each major folder/file is for after cleanup.

## Root
- `README.md`: main setup and run instructions.
- `backend/`: FastAPI backend code and config.
- `frontend/`: Flutter frontend app.
- `docs/`: requirements and technical docs.
- `scripts/`: helper scripts for demo startup.
- `.vscode/`: editor workspace settings.

## Backend
- `backend/README.md`: backend-specific setup and endpoints.
- `backend/requirements.txt`: Python dependencies.
- `backend/.env.example`: environment variable template.
- `backend/app/main.py`: FastAPI entrypoint.
- `backend/app/api/`: route wiring and dependencies.
- `backend/app/core/`: app config and Firebase/mock setup.
- `backend/app/models/`: enums/constants.
- `backend/app/schemas/`: request/response data models.
- `backend/app/services/`: business logic layer.
- `backend/app/repositories/`: Firestore data access layer.

## Frontend
- `frontend/README.md`: frontend run notes and dart-defines.
- `frontend/pubspec.yaml`: Flutter project config and packages.
- `frontend/lib/main.dart`: app startup.
- `frontend/lib/app.dart`: app shell and role-aware startup flow.
- `frontend/lib/core/`: app-level config, routing, services, theme.
- `frontend/lib/features/`: feature pages (dashboard, appointments, availability, clients, invoices, messages, notifications, auth).
- `frontend/lib/models/`: shared data models used by features.
- `frontend/lib/shared/`: reusable widgets/components.
- `frontend/android/`, `frontend/ios/`, `frontend/macos/`, `frontend/web/`: platform-specific Flutter targets.
- `frontend/test/`: widget tests.

## Docs
- `docs/requirements/`: source requirement artifacts (proposal/design PDFs and extracted text).
- `docs/technical/ARCHITECTURE.md`: architecture summary.
- `docs/technical/PROJECT_MAP.md`: this file.

## Scripts
- `scripts/run_backend_demo.sh`: starts FastAPI backend in reload mode.
- `scripts/run_frontend_demo.sh`: runs Flutter web app against local backend.

## Removed During Cleanup
- Generated or duplicate build artifacts were removed (`frontend/build`, `frontend/.dart_tool`, duplicate nested `frontend/flutter_application_1`, and OS/junk files) to keep the repo lightweight.