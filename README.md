# AFG2026 (Anchor)

This project is a Flutter and FastAPI app for small-businesses (client auth later on, appointments, invoices, and estimates). Github repo: https://github.com/sanvi-ven/AFG2026

## IDE Used
- Visual Studio Code is what we're using

Recommended VS Code extensions:
- Dart
- Flutter
- Python
- Pylance

## What Needs to Be Installed

### 1) Git
- Install Git and confirm:
	- `git --version`

### 2) Python
- Python 3.9+ (recommended: 3.10 or 3.11)
- Confirm using:
	- `python3 --version`

### 3) Flutter SDK
- Install Flutter and ensure it is on PATH
- Confirm using:
	- `flutter --version`
	- `flutter doctor`

### 4) Chrome (for web run)
- Flutter web is typically run with Chrome:
	- `flutter devices`

## Project Structure
- `backend/` is the FastAPI server
- `frontend/` is the Flutter app

## Instructor Setup (From ZIP)

### 1) Unzip and open project
- Unzip the folder.
- Open the root folder in VS Code.

### 2) Backend environment file
In `backend/`, create a `.env` file by copying `.env.example`.

The `backend/.env`:

```env
APP_NAME=Anchor
API_V1_PREFIX=/api/v1
FIREBASE_PROJECT_ID=afg2026a
GOOGLE_SERVICE_ACCOUNT_PATH=service-account.json
GOOGLE_CALENDAR_SCOPES=https://www.googleapis.com/auth/calendar
USE_MOCK_FIRESTORE=false
DEV_AUTH_BYPASS=true
```

### 3) Service account file (required for Google Calendar / Firestore access)
The file's contents will be sent in an email. Please create the service-account.json under the backend folder:

- `backend/service-account.json`

The filename must match:
- `GOOGLE_SERVICE_ACCOUNT_PATH=service-account.json`

Don't commit this file to GitHub.

## Run the App

### Run Commands

Terminal 1 (Backend):

```bash
cd yourPATH/AFG2026/backend
python3 -m pip install -r requirements.txt
PYTHONPATH=. python3 -m uvicorn app.main:app --host 127.0.0.1 --port 8001
```

Terminal 2 (Frontend):

```bash
cd yourPATH/AFG2026/frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8001 or flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8001
cd frontend && flutter run -d chrome --web-port 5174 --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=DEMO_ROLE=client --dart-define=DEMO_AUTH_TOKEN=dev-client
cd frontend && flutter run -d chrome --web-port 5174 --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=DEMO_ROLE=owner --dart-define=DEMO_AUTH_TOKEN=dev-owner

```
