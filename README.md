<p align="center">
  <img src="logo.svg" alt="FoneGate" width="260">
</p>

# 📱 FoneGate (Full-Stack Monorepo)

An open-source, self-hosted SMS Gateway that turns any Android phone into an SMS server. Send and receive SMS messages programmatically via a REST API, real-time WebSockets, and Webhooks.

---

## 🏗️ Architecture

```
                       [ Third-Party App / External API ]
                                   │
              POST /api/v1/sms/send│    Webhook HTTP POST (HMAC Signed)
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          NODE.JS BACKEND SERVER                             │
│                                                                             │
│  ┌────────────────────────┐  ┌───────────────────┐  ┌────────────────────┐  │
│  │     REST API Layer     │  │ SQLite Data Store │  │  Webhook Dispatcher│  │
│  │ (Auth, Devices, Logs)  │  │    (WAL Mode)     │  │ (Retry & Signatures│  │
│  └────────────────────────┘  └───────────────────┘  └────────────────────┘  │
│                                   │                                         │
│                ┌──────────────────┴──────────────────┐                      │
│                │     WebSocket Hub (/ws/gateway)     │                      │
│                └──────────────────┬──────────────────┘                      │
└───────────────────────────────────┼─────────────────────────────────────────┘
                                    │
               ┌────────────────────┴────────────────────┐
               │ Bidirectional WebSocket                 │ WebSocket / REST
               ▼                                         ▼
┌───────────────────────────────────┐    ┌────────────────────────────────────┐
│   ANDROID PHONE (FLUTTER APP)     │    │     FLUTTER WEB ADMIN DASHBOARD    │
│                                   │    │                                    │
│  • Foreground Service (24/7)      │    │  • Live Gateway Monitor & Battery  │
│  • Battery Optimization Bypass    │    │  • SMS Composer (Segment Counter)  │
│  • Android SmsManager (Send)      │    │  • Live Messages Table (In/Out)    │
│  • SMS BroadcastReceiver (Rx)     │    │  • Device Pairing & Token Manager  │
│  • Multi-SIM / Dual-SIM Slot      │    │  • Webhooks Config & Event Logs    │
│  • Auto-Reconnect Socket          │    └────────────────────────────────────┘
└───────────────────────────────────┘
```

---

## 📂 Project Structure

| Directory | Tech Stack | Description |
|---|---|---|
| `backend/` | **Node.js, TypeScript, SQLite, Express, `ws`** | REST API, dual WebSocket server, and HMAC webhook dispatcher. |
| `frontend/` | **Flutter Web** | Real-time administrative dashboard for monitoring devices and managing SMS. |
| `mobile_app/releases/` | **Pre-built APK** | Android gateway app (release APK only; source is private). |

---

## ⚡ Quick Start

### 1. Start the Backend

**Using Docker (recommended):**
```bash
docker compose up -d
```

**Or directly with Node.js:**
```bash
cd backend
npm install
npm run dev
```

The server starts at `http://localhost:8080`.

---

### 2. Launch the Web Dashboard
```bash
cd frontend
flutter run -d chrome
```
* **Default Admin Credentials:**
  * **Username:** `admin`
  * **Password:** `admin123`

*(Change your password via the profile menu in the top-right corner.)*

---

### 3. Install & Pair the Android App

1. Install the release APK from `mobile_app/releases/` on your Android device:
   ```bash
   adb install -r mobile_app/releases/fonegate.apk
   ```
2. Open the **FoneGate** app on the phone:
   - Grant SMS, Phone, and Notification permissions when prompted.
   - Tap **"Enable"** on the battery optimization banner to ensure 24/7 background operation.
   - Tap **Settings** (top-right gear icon) and enter:
     - **Backend WebSocket URL:** `ws://<YOUR_BACKEND_IP>:8080/ws/gateway`
     - **Device Token:** Generated from the Web Dashboard (Devices tab → "Pair New Phone").
   - Toggle **"Gateway Service"** ON. The status will turn green (**Online & Active**).

---

### 4. Backup & Restore
* **Export:** Click **"Backup / Restore"** in the dashboard header → **"Export JSON"** to download a full snapshot.
* **Import:** Click **"Import JSON"** and choose:
  * **Merge Mode:** Adds new records without deleting existing ones.
  * **Wipe & Replace:** Clears everything and restores from the backup.

---

## 📡 REST API Usage Guide

> **Base URL:** `http://localhost:8080`

### Authentication

FoneGate uses two auth methods:

| Method | Header | Use For |
|---|---|---|
| **API Key** | `X-API-Key: fg_xxx...` | SMS endpoints — for external apps & integrations |
| **JWT Token** | `Authorization: Bearer <token>` | Admin dashboard & management endpoints |

**Create API keys** from the dashboard → **API Keys** tab, or via the admin API (see below).

---

### Step 1: Create an API Key

From the **FoneGate Dashboard** → **API Keys** tab → **Create API Key**.

Or via the admin API (requires JWT login first):
```bash
# Login to get admin JWT
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}'

# Create API key (use JWT from login response)
curl -X POST http://localhost:8080/api/v1/api-keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <jwt-token>" \
  -d '{"name": "My CRM Integration"}'
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "...",
    "name": "My CRM Integration",
    "key": "fg_a1b2c3d4e5f6...",
    "permissions": ["sms:send", "sms:read"],
    "is_active": 1
  }
}
```

Use the `key` value (`fg_...`) in all SMS API requests below.

---

### Step 2: Send a Single SMS

```bash
curl -X POST http://localhost:8080/api/v1/sms/send \
  -H "Content-Type: application/json" \
  -H "X-API-Key: fg_a1b2c3d4e5f6..." \
  -d '{
    "to": "+1234567890",
    "message": "Hello from FoneGate!",
    "simSlot": 0
  }'
```

**Response:**
```json
{
  "success": true,
  "message": "SMS queued successfully",
  "data": {
    "id": "msg_xyz789",
    "phone_number": "+1234567890",
    "message": "Hello from FoneGate!",
    "status": "queued"
  }
}
```

**Fields:**
| Field | Type | Description |
|---|---|---|
| `to` | string | Recipient phone number (required) |
| `message` | string | SMS body text (required) |
| `simSlot` | number | SIM slot: `0` (SIM 1) or `1` (SIM 2). Default: `0` |
| `deviceId` | string | Target a specific paired phone. Default: any online device |

---

### Step 3: Send Bulk SMS

```bash
curl -X POST http://localhost:8080/api/v1/sms/send-bulk \
  -H "Content-Type: application/json" \
  -H "X-API-Key: fg_a1b2c3d4e5f6..." \
  -d '{
    "messages": [
      { "to": "+1234567890", "message": "Hello User 1" },
      { "to": "+1987654321", "message": "Hello User 2" },
      { "to": "+1555000111", "message": "Hello User 3" }
    ]
  }'
```

**Response:**
```json
{
  "success": true,
  "count": 3,
  "data": [
    { "id": "msg_001", "phone_number": "+1234567890", "status": "queued" },
    { "id": "msg_002", "phone_number": "+1987654321", "status": "queued" },
    { "id": "msg_003", "phone_number": "+1555000111", "status": "queued" }
  ]
}
```

---

### Step 4: Check Message Status

**Get a single message:**
```bash
curl http://localhost:8080/api/v1/sms/messages/msg_xyz789 \
  -H "X-API-Key: fg_a1b2c3d4e5f6..."
```

**List all messages (paginated):**
```bash
curl "http://localhost:8080/api/v1/sms/messages?page=1&limit=25" \
  -H "X-API-Key: fg_a1b2c3d4e5f6..."
```

**Filter by status:**
```bash
curl "http://localhost:8080/api/v1/sms/messages?status=delivered&page=1&limit=10" \
  -H "X-API-Key: fg_a1b2c3d4e5f6..."
```

**Possible statuses:** `pending`, `queued`, `sent`, `delivered`, `failed`

---

### Step 5: Retry a Failed Message

```bash
curl -X POST http://localhost:8080/api/v1/sms/messages/msg_xyz789/retry \
  -H "X-API-Key: fg_a1b2c3d4e5f6..."
```

---

### Step 6: Delete a Message

```bash
curl -X DELETE http://localhost:8080/api/v1/sms/messages/msg_xyz789 \
  -H "X-API-Key: fg_a1b2c3d4e5f6..."
```

---

## 📊 Admin API Endpoints (JWT Required)

> These endpoints require the admin JWT token from `/api/v1/auth/login`, not an API key.

### Admin Login
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}'
```
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": { "id": "...", "username": "admin" }
}
```

### Gateway Statistics
```bash
curl http://localhost:8080/api/v1/stats \
  -H "Authorization: Bearer <token>"
```
```json
{
  "totalSent": 142,
  "totalDelivered": 138,
  "totalFailed": 4,
  "totalReceived": 57,
  "pendingQueue": 0,
  "activeDevices": 1,
  "totalDevices": 2
}
```

### List Connected Devices
```bash
curl http://localhost:8080/api/v1/devices \
  -H "Authorization: Bearer <token>"
```

### Delete a Device
```bash
curl -X DELETE http://localhost:8080/api/v1/devices/d_abc123 \
  -H "Authorization: Bearer <token>"
```

### Verify Session
```bash
curl http://localhost:8080/api/v1/auth/me \
  -H "Authorization: Bearer <token>"
```

### Change Password
```bash
curl -X POST http://localhost:8080/api/v1/auth/change-password \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"currentPassword": "admin123", "newPassword": "myNewSecurePass"}'
```

### Manage API Keys
```bash
# List all keys
curl http://localhost:8080/api/v1/api-keys \
  -H "Authorization: Bearer <token>"

# Create a new key
curl -X POST http://localhost:8080/api/v1/api-keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"name": "My App"}'

# Enable/Disable a key
curl -X PATCH http://localhost:8080/api/v1/api-keys/<key-id>/toggle \
  -H "Authorization: Bearer <token>"

# Delete a key
curl -X DELETE http://localhost:8080/api/v1/api-keys/<key-id> \
  -H "Authorization: Bearer <token>"
```

### Health Check (no auth required)
```bash
curl http://localhost:8080/health
```
```json
{ "status": "ok", "service": "FoneGate Backend" }
```

---

## 🪝 Webhooks

### Register a Webhook
```bash
curl -X POST http://localhost:8080/api/v1/webhooks \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "url": "https://your-server.com/webhook",
    "secret": "my-webhook-secret",
    "events": ["sms.received", "sms.delivered", "sms.failed"]
  }'
```

### List Webhooks
```bash
curl http://localhost:8080/api/v1/webhooks \
  -H "Authorization: Bearer <token>"
```

### Test a Webhook
```bash
curl -X POST http://localhost:8080/api/v1/webhooks/<webhook-id>/test \
  -H "Authorization: Bearer <token>"
```

### Delete a Webhook
```bash
curl -X DELETE http://localhost:8080/api/v1/webhooks/<webhook-id> \
  -H "Authorization: Bearer <token>"
```

### View Webhook Logs
```bash
curl http://localhost:8080/api/v1/webhooks/logs \
  -H "Authorization: Bearer <token>"
```

### Supported Webhook Events
| Event | Trigger |
|---|---|
| `sms.received` | Incoming SMS received by the phone |
| `sms.sent` | Carrier confirms transmission |
| `sms.delivered` | Carrier confirms receipt on recipient device |
| `sms.failed` | Transmission failed (no service, radio off, etc.) |

### Webhook Signature Verification (HMAC-SHA256)

Each webhook POST includes an `X-SMS-Signature` header. Verify it on your server:

```javascript
const crypto = require('crypto');

function verifyWebhook(rawBody, signature, secret) {
  const expected = crypto.createHmac('sha256', secret)
    .update(rawBody)
    .digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(signature),
    Buffer.from(expected)
  );
}

// In your Express handler:
app.post('/webhook', (req, res) => {
  const isValid = verifyWebhook(
    JSON.stringify(req.body),
    req.headers['x-sms-signature'],
    'my-webhook-secret'
  );
  if (!isValid) return res.status(401).send('Invalid signature');
  // Process the event...
  res.sendStatus(200);
});
```

---

### Backup & Restore via API

**Export:**
```bash
curl http://localhost:8080/api/v1/backup/export \
  -H "Authorization: Bearer <token>" \
  -o fonegate_backup.json
```

**Import (merge):**
```bash
curl -X POST http://localhost:8080/api/v1/backup/import \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d "{\"mode\": \"merge\", \"data\": $(cat fonegate_backup.json)}"
```

---

## 🐳 Docker Deployment

```bash
# Clone and start
docker compose up -d

# View logs
docker compose logs -f

# Stop
docker compose down
```

**Environment variables** (set in `.env` or `docker-compose.yml`):
| Variable | Default | Description |
|---|---|---|
| `PORT` | `8080` | Backend server port |
| `HOST` | `0.0.0.0` | Backend bind address |
| `DB_PATH` | `./data/sms_gateway.db` | SQLite database file path |
| `API_KEY` | `change-me-in-production` | API key for device pairing |
| `JWT_SECRET` | `change-me-in-production` | Secret for JWT token signing |
| `CORS_ORIGIN` | `*` | Allowed CORS origins |
| `WEBHOOK_TIMEOUT_MS` | `5000` | Webhook delivery timeout (ms) |
| `FRONTEND_PORT` | `3000` | Frontend container exposed port |

---

## 📄 License

This project is licensed under the MIT License — open source and free for personal and commercial use.
