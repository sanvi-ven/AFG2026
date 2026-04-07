# Small Biz Manager - MVP Architecture

## Stack
- Frontend: Flutter (Dart)
- Backend: FastAPI (Python)
- Database/Auth: Firebase Firestore + Firebase Auth (Google Sign-In)

## Roles
- `owner` (business owner)
- `client`

## Auth Flow
- Frontend signs in with Google via Firebase Auth
- Frontend sends Firebase ID token to backend (`Authorization: Bearer <token>`)
- Backend verifies token using Firebase Admin
- Backend maps token `uid` to `users.firebase_uid` and auto-creates a `client` user on first login
- Owner-only operations are enforced with route dependencies

## Firestore Collections
- `users`
- `clients`
- `appointments`
- `invoices`
- `messages`
- `notifications`

## Backend Layers
- **Routes**: request/response mapping
- **Services**: business logic
- **Repositories**: Firestore access
- **Schemas**: request/response models

## API Endpoints (MVP)
- `POST /api/v1/auth/google`
- `GET/POST /api/v1/users`
- `PATCH /api/v1/users/{user_id}/role`
- `GET/POST /api/v1/appointments`
- `PATCH /api/v1/appointments/{appointment_id}`
- `POST /api/v1/appointments/{appointment_id}/sync-calendar`
- `GET/POST /api/v1/invoices`
- `PATCH /api/v1/invoices/{invoice_id}/status`
- `GET/POST /api/v1/messages`
- `POST /api/v1/notifications/single`
- `POST /api/v1/notifications/broadcast`

## Frontend Pages
- Login (Google Sign-In entry)
- Dashboard
- Appointments
- Invoices
- Messages
- Notifications
- Availability (owner only)
