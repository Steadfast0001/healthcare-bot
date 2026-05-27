# Healthcare Chatbot Demo

This project is a Flutter frontend paired with a FastAPI backend and PostgreSQL database. It is designed to provide a safe healthcare assistant experience with symptom discussion, emergency detection, chat history, and health tips.

## Features

- User signup/login with JWT authentication
- AI-powered healthcare chat with structured response output
- Emergency keyword detection and urgent care guidance
- Symptom assessment backed by database-driven conditions
- Health tips loaded from the database by category
- Patient profile editing and chat history persistence
- Safe medical disclaimer and no claims of diagnosis

## Setup Instructions

For a more detailed deployment guide, see `DEPLOYMENT.md`.

### Backend Setup

1. Create a Python virtual environment and install dependencies:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

1. Create a PostgreSQL database.
1. Copy `.env.example` to `.env` and update values:

```text
DATABASE_URL=postgresql://username:password@localhost:5432/healthcare_db
GOOGLE_API_KEY=your_google_api_key_here
JWT_SECRET_KEY=replace-this-with-a-secure-random-value
FRONTEND_BASE_URL=http://localhost:8080
```

1. Apply the database migration script:

```powershell
psql -f backend/migrations.sql
```

1. Start the backend server:

```powershell
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8001
```

### Frontend Setup

1. Install Flutter dependencies:

```bash
flutter pub get
```

1. Configure environment variables by copying `flutter.env.example` to `flutter.env`:

```text
BACKEND_URL=http://127.0.0.1:8001
```

1. Run the Flutter app:

```bash
flutter run -d edge --web-port=8080
```

The app will be available at `http://localhost:8080`.

## Validation Status

✅ Backend endpoints validated (health, auth, chat, symptom assessment, profile)
✅ Database schema repaired and migrations applied
✅ Frontend builds successfully and runs on web
✅ End-to-end integration tested
✅ Deployment documentation completed

## Architecture

- **Backend**: FastAPI with SQLAlchemy, PostgreSQL, JWT authentication, Google Gemini integration
- **Frontend**: Flutter web app with responsive UI, state management, and API integration
- **Database**: PostgreSQL with tables for users, chats, profiles, symptoms, conditions, and health tips
- **Security**: JWT tokens, password hashing, email verification, CORS handling

```text
BACKEND_URL=http://localhost:8001
```

## Available Backend Endpoints

- `GET /` - API status page
- `GET /health` - health check for backend and database
- `POST /auth/signup` - create a new user
- `POST /auth/login` - login and receive JWT
- `GET /auth/me` - get current authenticated user profile
- `PUT /auth/me` - update profile details
- `POST /auth/forgot-password` - request a password reset email
- `POST /auth/reset-password` - reset password using token
- `POST /chat` - submit an authenticated chat message
- `GET /chat/history` - retrieve the user’s previous conversations
- `DELETE /chat/history` - clear the user’s chat history
- `GET /health-tips` - list health tips from the database
- `POST /symptom-assessment` - submit a symptom assessment

## Notes

- Never commit `.env` or `flutter.env` to source control.
- Keep the Google API key only in the backend environment.
- Use the Flutter emulator’s `10.0.2.2` host if testing on Android.
- The assistant is educational only and not a substitute for licensed care.
