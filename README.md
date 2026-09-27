# Qprint

Print / file-sharing platform: customers upload documents, nearby shopkeepers print them. Includes web apps, a customer Android app, and a shopkeeper Windows app.

## After clone (required once)

```bat
git clone git@github.com:SurajrJadhav/qprint_release.git
cd qprint_release
setup.bat
```

Linux/macOS (deps + env only; Windows print binaries need Windows):

```bash
chmod +x setup.sh build.sh manage.sh
./setup.sh
```

`setup` is **idempotent**:

| Step | Behavior |
|------|----------|
| Env files | Creates from `*.example` only if missing — never overwrites yours |
| `npm install` / `go mod` / `flutter pub get` | Skips npm if `node_modules` already exists |
| SumatraPDF / LibreOffice | Downloads **only if missing or invalid**; partial downloads are deleted, not kept |

Options:

```bat
setup.bat              rem full (env + deps + Windows bins)
setup.bat env          rem env examples only
setup.bat deps         rem go / npm / flutter only
setup.bat bins         rem Sumatra + LibreOffice only (Windows)
```

`build.bat` does **not** download extras. Run `setup.bat` once after clone, then build anytime.

## Project layout

```
qprint_release/
├── backend/           Go API (Chi + PostgreSQL)
├── frontend/          Customer / shopkeeper web (Next.js)
├── admin_frontend/    Admin panel (Next.js, port 3001)
├── customer_app/      Customer mobile app (Flutter / Android)
├── shopkeeper_app/    Shopkeeper desktop app (Flutter / Windows)
├── scripts/           Shared helpers (OAuth config, upload tools)
├── setup.bat / setup.sh
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

`setup.bat` / `setup.sh` copies examples for you. Fill in real values (never commit secrets):

| File | Purpose |
|------|---------|
| `backend/.env` | API, DB, JWT, Razorpay, `GOOGLE_CLIENT_IDS` |
| `frontend/.env.local` | `NEXT_PUBLIC_API_URL`, Google web client ID |
| `admin_frontend/.env.local` | Admin API URL |
| `customer_app/android/app/google-services.json` | Firebase (replace example) |

Shared public Google OAuth IDs for app builds: `scripts/google_oauth.config.bat` (and `.sh`).

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

PDF print needs Sumatra under `shopkeeper_app/windows/runner/bin/` (from `setup.bat bins`). LibreOffice there is optional for Word/PPT.

## Deploy notes

- Backend: `render.yaml` is included for Render.
- Frontends: Vercel-compatible Next.js apps (`vercel.json` in each frontend folder).
- Set the same secrets on the host that you use in local `.env` files — do not put them in git.

## License / ownership

Private project — do not publish secrets, keystores, or production `.env` files.
