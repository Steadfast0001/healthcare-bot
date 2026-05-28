# Healthcare Chatbot Deployment Guide

## Overview

This guide provides comprehensive instructions for deploying the Healthcare Chatbot application, which consists of:

- **Frontend**: Flutter web application
- **Backend**: FastAPI server with PostgreSQL database
- **AI Integration**: Google Gemini for healthcare chat responses

The application provides secure healthcare assistance with emergency detection, symptom assessment, and user profile management.

## Prerequisites

### System Requirements

- **Python**: 3.11 or later
- **PostgreSQL**: 14+ (or compatible database)
- **Flutter**: 3.11+ SDK
- **Git**: For version control
- **Node.js**: 16+ (optional, for additional tooling)

### Development Tools

- **Windows**: Visual Studio with Desktop development workload (for Flutter desktop)
- **macOS/Linux**: Standard development tools
- **Database Client**: pgAdmin, DBeaver, or psql command line

## Quick Start (Development)

### 1. Clone and Setup Repository

```bash
git clone <repository-url>
cd healthcare-chatbot
```

### 2. Backend Setup

```powershell
# Create virtual environment
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Setup environment variables
cd ..
copy .env.example .env
# Edit .env with your configuration
```

### 3. Database Setup

```sql
-- Create database
CREATE DATABASE healthcare_db;
CREATE USER healthcare_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE healthcare_db TO healthcare_user;

-- Or use the provided migration script
psql -U postgres -d healthcare_db -f wadocta_migration.sql
```

### 4. Frontend Setup

```bash
# Install Flutter dependencies
flutter pub get

# Configure environment
copy flutter.env.example flutter.env
# Edit flutter.env with backend URL
```

### 5. Launch Application

```powershell
# Terminal 1: Start backend
cd backend
.\.venv\Scripts\Activate.ps1
uvicorn main:app --reload --host 0.0.0.0 --port 8001

# Terminal 2: Start frontend
flutter run -d edge --web-port=8080
```

## Detailed Backend Deployment

### Environment Configuration

Create a `.env` file in the project root with the following variables:

```bash
# Database
DATABASE_URL=postgresql://healthcare_user:password@localhost:5432/healthcare_db

# Authentication
JWT_SECRET_KEY=your-super-secure-random-key-here-min-32-chars
ACCESS_TOKEN_EXPIRE_MINUTES=1440

# AI Integration
GOOGLE_API_KEY=your_google_api_key_here
GOOGLE_MODEL=gemini-flash-latest

# Email (optional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
EMAIL_FROM=noreply@healthcare-app.com

# Frontend
FRONTEND_BASE_URL=http://localhost:8080

# Security
EMAIL_VERIFICATION_TOKEN_EXPIRE_HOURS=24
PASSWORD_RESET_TOKEN_EXPIRE_HOURS=1
```

### Database Migration

The application uses SQLAlchemy for ORM. Tables are auto-created, but run the migration script for additional data:

```powershell
# Apply seed data
psql -U healthcare_user -d healthcare_db -f wadocta_migration.sql

# Or use the API endpoint after starting the server
curl http://localhost:8001/seed
```

### Starting the Backend Server

```powershell
# Development mode
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8001

# Production mode
uvicorn backend.main:app --host 0.0.0.0 --port 8001 --workers 4
```

## Detailed Frontend Deployment

### Flutter Environment Setup

1. **Install Flutter SDK** (if not already installed):

   ```bash
   # Download from `https://flutter.dev`
   # Add to PATH
   flutter doctor
   ```

2. **Configure Environment Variables**:

   Create `flutter.env` in the project root:

   ```bash
   BACKEND_URL=http://localhost:8001
   ```

3. **Install Dependencies**:

   ```bash
   flutter pub get
   ```

### Running the Application

#### Web Deployment (Recommended for Development)

```bash
flutter run -d edge --web-port=8080
```

- Access at: `http://localhost:8080`
- Hot reload enabled for development

#### Desktop Deployment (Windows)

```bash
flutter run -d windows
```

*Requires Visual Studio with Desktop development workload*

#### Mobile Deployment (Android)

##### Physical Device

1. **Ensure phone and laptop are on the same network** (connected to the same WiFi)

2. **Update `flutter.env` with your laptop's IP address** (not `localhost`):

   ```bash
   # Get your laptop IP on Windows:
   ipconfig | findstr "IPv4"
   
   # Then update flutter.env:
   BACKEND_URL=http://YOUR_LAPTOP_IP:8001
   # Example: BACKEND_URL=http://192.168.1.100:8001
   ```

3. **Rebuild and run on phone**:

   ```bash
   flutter run -d android
   ```

##### Android Emulator

```bash
flutter run -d android
```

- Use `10.0.2.2` instead of `localhost` in `flutter.env` for Android emulator (this is the special IP that routes to the host machine)

#### Build for Production

```bash
# Web build
flutter build web --release

# Windows build
flutter build windows --release

# Android APK
flutter build apk --release
```

## Production Deployment

### Backend Production Setup

1. **Use a Production WSGI Server**:

   ```bash
   pip install gunicorn
   gunicorn -w 4 -k uvicorn.workers.UvicornWorker backend.main:app --bind 0.0.0.0:8001
   ```

2. **Use a Reverse Proxy** (nginx example):

   ```nginx
   server {
       listen 80;
       server_name your-domain.com;

       location /api {
           proxy_pass http://127.0.0.1:8001;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
       }
   }
   ```

3. **Environment Variables**:

   - Use strong, randomly generated `JWT_SECRET_KEY`
   - Set `FRONTEND_BASE_URL` to your production domain
   - Configure proper SMTP settings for email

### Frontend Production Setup

1. **Build Optimized Version**:

   ```bash
   flutter build web --release --web-renderer html
   ```

2. **Deploy to Web Server**:

   - Copy `build/web` contents to your web server
   - Configure CORS in production backend
   - Update `flutter.env` with production backend URL

### Database Production Setup

1. **Use Connection Pooling**:

   - Configure PostgreSQL connection limits
   - Use database URL with connection pooling parameters

2. **Backup Strategy**:

   ```bash
   pg_dump healthcare_db > backup.sql
   ```

## Environment Variables Reference

### Backend (.env)

| Variable                      | Description                  | Default                      | Required |
|-------------------------------|------------------------------|------------------------------|----------|
| `DATABASE_URL`                | PostgreSQL connection string | -                            | Yes      |
| `GOOGLE_API_KEY`              | Gemini/Google API key for chat | -                          | Yes      |
| `JWT_SECRET_KEY`              | JWT signing key (32+ chars)  | -                            | Yes      |
| `FRONTEND_BASE_URL`           | Frontend URL for emails      | `http://localhost:8080`      | Yes      |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | JWT token lifetime           | 1440                         | No       |
| `SMTP_HOST`                   | Email SMTP server            | -                            | No       |
| `SMTP_PORT`                   | SMTP port                    | 587                          | No       |
| `SMTP_USER`                   | SMTP username                | -                            | No       |
| `SMTP_PASSWORD`               | SMTP password                | -                            | No       |
| `EMAIL_FROM`                  | From email address           | no-reply@healthcare-app.local| No       |

### Frontend (flutter.env)

| Variable     | Description     | Default               | Required |
|--------------|-----------------|-----------------------|----------|
| `BACKEND_URL`| Backend API URL | `http://localhost:8001` | Yes      |

## API Endpoints

### Health Check

```bash
curl http://localhost:8001/health
```

### Authentication

- `POST /auth/signup` - User registration
- `POST /auth/login` - User login
- `GET /auth/me` - Get current user profile
- `PUT /auth/me` - Update user profile

### Chat

- `POST /chat` - Send chat message
- `GET /chat/history` - Get chat history

### Authentication

- `POST /auth/signup` - User registration
- `POST /auth/login` - User login
- `GET /auth/me` - Get current user profile
- `PUT /auth/me` - Update user profile

### Chat

- `POST /chat` - Send chat message
- `GET /chat/history` - Get chat history

### Healthcare Features

- `POST /symptom-assessment` - Assess symptoms
- `GET /health-tips` - Get health tips
- `GET /health-tips/{category}` - Get tips by category

## Troubleshooting

### Backend Issues

#### "ModuleNotFoundError: No module named 'backend"

- Run uvicorn from the project root: `uvicorn backend.main:app`

#### Database connection errors

- Verify DATABASE_URL format
- Ensure PostgreSQL is running
- Check user permissions

#### Google Gemini API errors

- Verify GOOGLE_API_KEY is set
- Check API quota and billing

#### Email sending fails

- Configure SMTP settings in .env
- Use app passwords for Gmail
- Check firewall settings

### Frontend Issues

#### "Unable to find suitable Visual Studio toolchain"

- Install Visual Studio with Desktop development workload
- Run `flutter doctor` to verify installation

#### Backend connection fails

- Verify BACKEND_URL in flutter.env
- For Android emulator, use `10.0.2.2` instead of `localhost`
- Check CORS settings in backend

#### Build fails

- Run `flutter clean` then `flutter pub get`
- Update Flutter SDK: `flutter upgrade`

#### Phone: "Network error: unable to connect to server"

Root cause: Phone trying to connect to `localhost` which only exists on the phone itself, not your laptop

**Solution 1: Update `flutter.env` with your laptop's actual IP address on the network**

```bash
# Get your laptop's IP:
ipconfig | findstr "IPv4"

# Update flutter.env with the actual IP (example: 192.168.1.100)
BACKEND_URL=http://YOUR_LAPTOP_IP:8001
```

**Solution 2: Verify phone is on the same network as laptop**

**Solution 3: Check firewall allows port 8001**

```powershell
# Add firewall rule for port 8001
netsh advfirewall firewall add rule name="Flutter Backend" dir=in action=allow protocol=tcp localport=8001
```

### Database Issues

#### Missing tables

- Run the migration script: `psql -f wadocta_migration.sql`
- Or restart backend to auto-create tables

#### Permission denied

- Grant proper permissions to database user
- Check PostgreSQL authentication method

## Security Considerations

1. **Never commit secrets** to version control
2. **Use HTTPS** in production
3. **Implement rate limiting** for API endpoints
4. **Regularly update dependencies**
5. **Monitor logs** for security issues
6. **Use strong passwords** and JWT secrets

## Monitoring and Maintenance

### Health Checks

```bash
# Backend health
curl http://localhost:8001/health

# Database connectivity
psql -U healthcare_user -d healthcare_db -c "SELECT 1"
```

### Logs

- Backend logs are output to console
- Configure log rotation for production
- Monitor for errors and performance issues

### Updates

```bash
# Update dependencies
cd backend
pip install -r requirements.txt --upgrade

# Update Flutter
flutter upgrade

# Update database schema (if needed)
# Create new migration scripts
```

## Support

For issues not covered in this guide:

1. Check the README.md for additional information
2. Review backend logs for error details
3. Verify environment variable configuration
4. Test API endpoints individually

## Architecture Overview

```
┌─────────────────┐    HTTP     ┌─────────────────┐
│   Flutter Web   │◄────────────┤    FastAPI      │
│    Frontend     │             │    Backend      │
└─────────────────┘             └─────────────────┘
                                   │
                                   │ SQL
                                   ▼
                            ┌─────────────────┐
                            │  PostgreSQL     │
                            │   Database      │
                            └─────────────────┘
                                   │
                                   ▼
                            ┌─────────────────┐
                            │ Google Gemini   │
                            │      API        │
                            └─────────────────┘
```

This deployment provides a complete healthcare chatbot solution with secure authentication, AI-powered responses, and comprehensive healthcare features.
