# Backend Connection Setup Guide

This guide will help you fix the "not connected to backend server" issue on your Android device.

## Common Causes

- **Backend server not running** - The Python backend needs to be started
- **Incorrect IP address** - The `BACKEND_URL` in `.env` or `flutter.env` doesn't match your development machine's IP
- **Device and PC not on same network** - They need to be connected to the same WiFi
- **Firewall blocking** - Windows firewall might block the backend port
- **Wrong port** - The backend should run on port 8001, not 8000

---

## Step-by-Step Setup

### Step 1: Find Your Development Machine's IP Address

On **Windows**:

1. Open Command Prompt or PowerShell
2. Type: `ipconfig`
3. Look for "IPv4 Address" under your WiFi adapter (usually starts with 192.168.x.x or 10.x.x.x)
4. **Remember this IP** - you'll need it in the next steps

Example output:

```powershell
Wireless LAN adapter WiFi:
    IPv4 Address. . . . . . . . . . : 192.168.1.100
```

### Step 2: Update the Backend URL Configuration

Edit the file: `.env`

Find this line:

```bash
BACKEND_URL=http://10.0.2.2:8001
```

Replace `10.0.2.2` with your actual IP address from Step 1. For example:

```bash
BACKEND_URL=http://192.168.1.100:8001
```

**Important Notes:**

- `10.0.2.2` only works for Android emulators
- For physical Android devices, you MUST use your PC's actual IP address
- The port must be **8001** (not 8000)

### Step 3: Set Up the Database

The backend requires a database. We use SQLite by default (no PostgreSQL needed).

The database file will be created automatically at `wadocta.db` when you start the backend for the first time.

### Step 4: Start the Backend Server

On your **Windows development machine**:

**Option A: Using the setup script (Recommended)**

1. Navigate to your project folder in File Explorer
2. Double-click `run_backend.bat`
3. A command window will open and show status messages
4. You should see: `Application startup complete`
5. **Leave this window open** - the backend is now running

**Option B: Manual setup**

1. Open Command Prompt or PowerShell in your project folder
2. Run:

```powershell
pip install -r backend/requirements.txt
cd .
uvicorn backend.main:app --host 0.0.0.0 --port 8001 --reload
```

You should see output like:

```
Uvicorn running on http://0.0.0.0:8001
Application startup complete
```

### Step 5: Ensure Device and PC Are on Same Network

- Go to your Android device's WiFi settings
- Connect to the **same WiFi network** as your development PC
- Note down the WiFi network name

### Step 6: Run the Flutter App

On your **Android device**:

- Open the Wadocta app
- Try logging in
- **If you see better error messages now**, the connection is working!

---

## Testing the Connection

To verify your backend is accessible:

### From your PC

```powershell
# Test if backend is running locally
curl http://localhost:8001/health
```

Should respond with:

```json
{"status":"ok","message":"API and database are running properly."}
```

### From your Android device:
1. Open a web browser
2. Go to: `http://YOUR_IP:8001/health` (replace YOUR_IP with your actual IP)
3. You should see the JSON response above

---

## Troubleshooting

### Issue: "Connection refused" or "Unable to connect"

**Cause:** Backend server is not running

**Solution:**

- Double-click `run_backend.bat` on your Windows PC
- Wait for it to say "Application startup complete"
- Try the app again

### Issue: "Connection timeout"

**Cause:** IP address is wrong or devices not on same network

**Solution:**

- Run `ipconfig` on your PC again - verify the IPv4 address
- Update `.env` file with the correct IP
- On Android device, go to WiFi settings and verify you're connected to the same network as your PC
- Try the app again

### Issue: Backend starts but database error appears

**Cause:** SQLite database not created yet

**Solution:**

- The database will be created automatically on first startup
- Wait 5-10 seconds after starting backend
- Try the app again

### Issue: Port 8001 is already in use

**Cause:** Another application is using port 8001

**Solution:**

The `run_backend.bat` script automatically fixes this. Just run it again.

Or manually:

```powershell
# Find process using port 8001
netstat -aon | findstr :8001

# Kill the process (replace PID with the actual number)
taskkill /F /PID <PID>
```

### Issue: Windows Firewall Blocking

**Cause:** Windows firewall is blocking Python/uvicorn

**Solution:**

- Open Windows Defender Firewall
- Click "Allow an app through firewall"
- Find Python in the list
- Check both "Private" and "Public" boxes
- Click OK

---

## Quick Diagnosis Checklist

Before trying again, confirm:

- [ ] Backend server is running (`run_backend.bat` window open)
- [ ] `.env` file has correct IP address (not 10.0.2.2 for physical devices)
- [ ] Port is 8001 (not 8000)
- [ ] Android device is connected to same WiFi as PC
- [ ] You can see `http://YOUR_IP:8001/health` in browser on phone

---

## File Configuration Reference

### `.env` (Backend Configuration)

```bash
BACKEND_URL=http://YOUR_IP:8001  # Update with your PC's IP
DATABASE_URL=sqlite:///./wadocta.db
```

### `flutter.env` (Flutter App Configuration)

```bash
BACKEND_URL=http://10.0.2.2:8001  # For emulator
# For physical device, this is overridden by .env BACKEND_URL
```

---

## Getting Help

If you're still having issues:

- **Check the backend console** for error messages
- **Run ipconfig** and confirm your PC's IP address is in the `.env` file
- **Verify WiFi connection** on both devices
- **Check port 8001** is accessible: `netstat -aon | findstr :8001`
- **Try from another device** on the same network to narrow down the issue
