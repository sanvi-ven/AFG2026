# Frontend (Flutter)

## Quick Start
1. Initialize Flutter platform files if needed:
   ```bash
   flutter create .
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run app:
   ```bash
   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
   ```

## Notes
- The scaffold includes role-aware pages and responsive navigation (mobile + web).
- Hook up Firebase config (`google-services.json`, `GoogleService-Info.plist`, web config) before production auth flows.
- Connect widgets to backend endpoints in `lib/core/services/api_client.dart` and feature repositories.
- Use demo login buttons in the app to authenticate against backend demo tokens (`dev-owner`, `dev-client`).
