# AFG2026 (Anchor)

This project is a Flutter and FastAPI app for small-businesses (client auth later on, appointments, invoices, and estimates). Github repo: https://github.com/sanvi-ven/AFG2026

Vercel: anchor-orpin.vercel.app

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

## Run the App

### Run Commands

Terminal 1 (Frontend):

```bash
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### To Test the Accounts:
Ryan's Account: prendergastryanj@gmail.com	12345678
Business Account Password: 12345