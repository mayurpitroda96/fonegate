<p align="center">
  <img src="../logo.svg" alt="FoneGate" width="220">
</p>

# 🚀 FoneGate Backend

An open-source, lightweight, high-performance Node.js backend for turning any Android phone into a self-hosted SMS Gateway.

- **Stack:** Node.js, Express, TypeScript, SQLite (`better-sqlite3`), WebSockets (`ws`).
- **Zero Heavy Infrastructure:** Uses an embedded SQLite database in WAL mode (no separate Postgres/MySQL required).
- **Dual WebSocket Hub:** Dedicated socket channel for the Android gateway phone (`/ws/gateway`) and live event stream for frontend dashboards (`/ws/dashboard`).
- **Webhook Dispatcher:** Dispatches signed HMAC-SHA256 HTTP POST callbacks for incoming messages and delivery reports.

---

## 📦 Quick Start

### 1. Local Run
```bash
cd backend
npm install
npm run dev
```

### 2. Run with Docker
```bash
docker build -t opensms-backend .
docker run -d -p 8080:8080 -v $(pwd)/data:/app/data opensms-backend
```

---

## 📡 Endpoints Overview

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Service health status |
| `POST` | `/api/v1/sms/send` | Queue single SMS (`{ to, message, simSlot, deviceId }`) |
| `POST` | `/api/v1/sms/send-bulk` | Queue batch SMS |
| `GET` | `/api/v1/sms/messages` | List inbox & outbox messages (paginated) |
| `GET` | `/api/v1/sms/messages/:id` | Get message status and delivery receipts |
| `POST` | `/api/v1/sms/messages/:id/retry` | Re-queue a failed SMS |
| `GET` | `/api/v1/devices` | List registered & connected Android phones |
| `POST` | `/api/v1/devices` | Pair new Android device |
| `GET` | `/api/v1/webhooks` | List webhook subscriptions |
| `POST` | `/api/v1/webhooks` | Register new webhook URL |
| `POST` | `/api/v1/webhooks/:id/test` | Test webhook delivery |
| `GET` | `/api/v1/stats` | Gateway throughput & metrics |
| `WS` | `/ws/gateway` | Android device connection endpoint |
| `WS` | `/ws/dashboard` | Frontend real-time updates endpoint |

---

## 🔐 Webhook Verification

Webhooks sent by this server contain an HMAC-SHA256 signature in the `X-SMS-Signature` header computed with your webhook secret:

```javascript
const signature = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
const isValid = req.headers['x-sms-signature'] === signature;
```

