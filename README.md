# Qprint

Print / file-sharing platform: customers upload documents, nearby shopkeepers print them. Includes web apps, a customer Android app, and a shopkeeper Windows app.

## Project layout

```
qprint_release/
├── backend/           Go API (Chi + PostgreSQL)
├── frontend/          Customer / shopkeeper web (Next.js)
├── admin_frontend/    Admin panel (Next.js, port 3001)
├── customer_app/      Customer mobile app (Flutter / Android)
├── shopkeeper_app/    Shopkeeper desktop app (Flutter / Windows)
├── scripts/           Shared helpers (OAuth config, upload tools)
├── build.bat / build.sh
├── manage.bat / manage.sh
└── render.yaml
```

## Prerequisites

- Go 1.22+
- Node.js 18+ and npm
- PostgreSQL 12+
- Flutter (stable) for mobile/desktop apps
- Android SDK (customer app) / Windows desktop enabled in Flutter (shopkeeper app)

## Environment setup

Never commit real secrets. Copy the examples and fill in local values:

```bash
# Backend
copy backend\.env.example backend\.env

# Web frontends
copy frontend\.env.example frontend\.env.local
copy admin_frontend\.env.example admin_frontend\.env.local
```

Backend `.env` keys (see `backend/.env.example`):

| Variable | Purpose |
|----------|---------|
| `PORT` | API port (default `8080`) |
| `DATABASE_URL` | Postgres connection string |
| `JWT_SECRET` | Auth signing secret |
| `RAZORPAY_*` | Payments (test or live) |
| `ALLOWED_ORIGINS` | CORS origins |
| `GOOGLE_CLIENT_IDS` | Comma-separated OAuth client IDs |

Frontend `.env.local`:

| Variable | Purpose |
|----------|---------|
| `NEXT_PUBLIC_API_URL` | Backend URL |
| `NEXT_PUBLIC_GOOGLE_CLIENT_ID` | Google Sign-In (web) |

Customer Android also needs Firebase config:

```text
copy customer_app\android\app\google-services.json.example
     customer_app\android\app\google-services.json
```

Fill `google-services.json` from the Firebase console. For release signing, copy:

```text
customer_app\android\key.properties.example  → key.properties
customer_app\android\local.properties.example → local.properties
```

Shared public Google OAuth IDs used by builds live in `scripts/google_oauth.config.bat` (and `.sh`).

## Database

```sql
CREATE DATABASE filesharing;
```

Point `DATABASE_URL` at that database. Tables are created/migrated when the API starts.

## Run locally (dev)

Windows:

```bat
manage.bat start
```

Linux/macOS:

```bash
./manage.sh start
```

- API: http://localhost:8080  
- Web: http://localhost:3000  
- Admin: `cd admin_frontend && npm run dev` → http://localhost:3001  

Stop with `manage.bat stop` / `./manage.sh stop`.

## Build everything

One script builds backend, web frontends, customer Android, and shopkeeper Windows in **debug/test** or **release** mode.

### Windows

```bat
build.bat                 rem interactive menu
build.bat debug           rem all targets, debug/test
build.bat release         rem all targets, release
build.bat release frontend
build.bat release customer
build.bat release customer aab
build.bat debug shopkeeper
```

### Linux / macOS

```bash
chmod +x build.sh
./build.sh
./build.sh debug
./build.sh release
./build.sh release customer aab
```

### What each mode does

| Target | Debug / test | Release |
|--------|--------------|---------|
| `backend` | `go build` → `qprint-api-debug` | `go build` → `qprint-api` |
| `frontend` | install + lint; run via `npm run dev` | `npm run build` |
| `admin` | install + lint; run via `npm run dev -p 3001` | `npm run build` |
| `customer` | debug APK (API → `10.0.2.2:8080`) | release APK or AAB |
| `shopkeeper` | debug Windows build (API → localhost) | release Windows build |

Release customer outputs:

- APK: `customer_app/build/app/outputs/flutter-apk/app-release.apk`
- AAB: `customer_app/build/app/outputs/bundle/release/app-release.aab`

Shopkeeper Windows output: `shopkeeper_app/build/windows/x64/runner/Release/` (or `Debug/`).

Shopkeeper PDF printing expects `SumatraPDF.exe` under `shopkeeper_app/windows/runner/bin/`. If missing, `scripts/setup_sumatra.ps1` can fetch it on Windows.

## Optional helpers

Kept under `scripts/` and app `scripts/` folders (signing certs, Sumatra/LibreOffice setup, release upload). Use only when you need those one-off tasks — day-to-day builds go through `build.bat` / `build.sh`.

## Deploy notes

- Backend: `render.yaml` is included for Render.
- Frontends: Vercel-compatible Next.js apps (`vercel.json` in each frontend folder).
- Set the same secrets on the host that you use in local `.env` files — do not put them in git.

## License / ownership

Private project — do not publish secrets, keystores, or production `.env` files.
