# Dental Queue Cloud Staging Deployment Guide

This guide documents how the Dental Queue Management System is configured for isolated cloud staging across **Neon PostgreSQL**, **Render (FastAPI)**, **Vercel (React/Vite)**, and **Flutter Android**.

> **Important:** Never copy local development credentials, database dumps, or real patient information into staging.

---

## 1. Platform Architecture & Known Free-Tier Limitations

- **Backend (Render Web Service, Python `3.12.7`)**
  - Runs FastAPI with Uvicorn on **1 worker (`--workers 1`)**.
  - **Why 1 worker is required:** WebSocket connections (`app.realtime.manager`), the background Smart Call auto-call timer (`run_smart_call_timer_loop`), and the API rate limiter (`app.core.rate_limit.SlidingWindowRateLimiter`) currently keep state in-process in memory. Running multiple workers would split WebSocket broadcasts, duplicate timer sweeps, and fragment rate-limit counters.
  - **Free tier limitations:** Render Free instances sleep after inactivity (~15 minutes of no inbound traffic). While asleep, active WebSockets close and the Smart Call timer pauses until the next request wakes the service (cold start typically takes ~30–60s). Instance restarts also clear in-memory rate-limit counters.
- **Database (Neon PostgreSQL)**
  - Use Neon's **pooled** connection string (`-pooler` hostname) for `DATABASE_URL` at runtime. `backend/app/db/session.py` sets `prepare_threshold=None` on `postgresql+psycopg://` connections so PgBouncer transaction pooling does not hit prepared-statement collisions, along with `pool_pre_ping=True` and `pool_recycle=300`.
  - Use Neon's **direct (non-pooled)** connection string for `ALEMBIC_DATABASE_URL` when running `alembic upgrade head` migrations (`backend/alembic/env.py` already prefers `ALEMBIC_DATABASE_URL` with `NullPool`).
- **Frontend (Vercel Static / Vite)**
  - Root directory: `web`
  - `web/vercel.json` configures the SPA fallback rewrite (`/(.*) -> /index.html`) so deep links such as `/login`, `/reception`, `/admin/analytics`, and `/display/1` load cleanly.
  - **Free tier note:** Vercel Hobby plans are strictly restricted to personal, non-commercial use. If commercial clinic demonstrations or client usage expand beyond Hobby terms, upgrade to Vercel Pro.
- **Mobile (Flutter Android)**
  - `mobile/android/app/src/main/AndroidManifest.xml` declares `android.permission.INTERNET` for release/staging APKs.
  - Ensure `mobile/android/app/google-services.json` belongs to the **same** Firebase project as the backend service account JSON mounted on Render if testing FCM push notifications.

---

## 2. Neon PostgreSQL Setup (Isolated Staging Database)

1. Create a dedicated Neon project/database for staging only (do not connect local dev `dental_db`).
2. Ensure both connection strings include `sslmode=require`:
   - `DATABASE_URL` (pooled `-pooler` URL for runtime)
   - `ALEMBIC_DATABASE_URL` (direct non-pooler URL for Alembic migrations)
3. Run migrations manually from a controlled shell before starting traffic:
   ```bash
   cd backend
   ALEMBIC_DATABASE_URL="<NEON_DIRECT_URL>" alembic upgrade head
   ```

---

## 3. Render Backend Configuration

Create a Web Service in Render with:

- **Root Directory:** `backend`
- **Python Version:** `3.12.7` (pinned via `backend/.python-version` and `PYTHON_VERSION=3.12.7`)
- **Build Command:**
  ```bash
  pip install -r requirements.txt
  ```
- **Start Command (single worker required):**
  ```bash
  uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers 1
  ```
- **Health Check Path:** `/api/health` (kept exempt from rate limiting; `/api/health/db` verifies live DB connectivity)

### Required Render Environment Variables

| Variable | Value / Guidance |
| :--- | :--- |
| `ENVIRONMENT` | `staging` |
| `DATABASE_URL` | Neon **pooled** URL (`postgresql+psycopg://...pooler...?sslmode=require`) |
| `SECRET_KEY` | Unique randomly generated secret (>= 32 chars) |
| `ALGORITHM` | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `30` |
| `REFRESH_TOKEN_EXPIRE_DAYS` | `7` |
| `CHECK_IN_QR_EXPIRE_MINUTES` | `180` |
| `CORS_ORIGINS` | Exact Vercel origin(s), comma-separated, e.g. `https://your-staging-app.vercel.app` (no `*`, no trailing `/`, HTTPS required in `staging`) |
| `RATE_LIMIT_ENABLED` | `true` |
| `TRUSTED_PROXY_HOPS` | `1` (reads rightmost client IP behind Render's reverse proxy, ignoring spoofed leftmost `X-Forwarded-For` values) |
| `FIREBASE_CREDENTIALS_PATH` | `/etc/secrets/firebase-service-account.json` (when uploading a Render Secret File) |

> **Firebase Secret File:** Upload the Firebase Admin SDK service-account JSON via Render Dashboard -> **Secret Files** at `/etc/secrets/firebase-service-account.json`. If omitted, push notifications are gracefully disabled without crashing startup.

---

## 4. Isolated Staging Bootstrap (Manual & Fail-Closed)

Do **not** run `app.db.seed` against staging. After migrations succeed, run the dedicated bootstrap script first in default dry-run mode, then with `--execute`:

```bash
cd backend
export DATABASE_URL="<NEON_DIRECT_OR_POOLED_URL_WITH_SSLMODE_REQUIRE>"
export STAGING_ADMIN_PASSWORD="<STRONG_12+_CHAR_PASSWORD>"
export STAGING_RECEPTION_PASSWORD="<STRONG_12+_CHAR_PASSWORD>"
# Optional overrides (default fictional +998901000001 / +998901000002):
# export STAGING_ADMIN_PHONE="+99890..."
# export STAGING_RECEPTION_PHONE="+99890..."

# 1. Dry-run verification (makes zero writes)
python -m app.db.staging_bootstrap --expected-host "<NEON_HOST>" --expected-db "<NEON_DB_NAME>"

# 2. Execute bootstrap (idempotent; creates only missing clinic/staff/specializations/doctors)
python -m app.db.staging_bootstrap --expected-host "<NEON_HOST>" --expected-db "<NEON_DB_NAME>" --execute
```

Safety rules enforced by `app.db.staging_bootstrap`:
- Refuses `localhost`, `127.0.0.1`, `dental_db`, `dental_app_test`, `postgres`, and URLs missing `sslmode=require`.
- Refuses to proceed if `DATABASE_URL` host or DB name differs from `--expected-host` / `--expected-db`.
- Enforces >= 12 char strong passwords (upper, lower, digit, special; no common words) without ever printing secrets.
- Creates **Aurora Demo Dental Clinic** (`Asia/Tashkent`), 1 Admin, 1 Receptionist, 3 dental specializations, and 3 fictional doctors without creating any patient accounts or modifying/deleting existing rows.

---

## 5. Vercel Frontend Configuration

Create a Vercel project pointing at repository root directory **`web`**:

- **Framework Preset:** Vite
- **Root Directory:** `web`
- **Build Command:** `npm run build`
- **Output Directory:** `dist`
- **Environment Variables:**
  - `VITE_API_BASE_URL` = `https://<your-render-backend>.onrender.com`

Verify `CORS_ORIGINS` on Render exactly matches the deployed `https://<your-vercel-app>.vercel.app` origin (no trailing slash).

---

## 6. Flutter Android Staging Build

Point the Flutter app cleanly to the staging Render URL at build time (HTTPS automatically maps WebSockets to `wss://` via `ApiConfig.clinicDisplayWsUri`):

```bash
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=https://<your-render-backend>.onrender.com
```
