# Kanha QR Monitoring System - Phase 1

```
kanha-qr/
├─ docker-compose.yml      Postgres+PostGIS, Redis, MinIO, API, Celery worker, Celery beat
├─ .env                    settings (S3_PUBLIC_ENDPOINT, JWT_SECRET, SMTP...)
├─ backend/                FastAPI + SQLAlchemy + Alembic + Celery
│  └─ app/{models,security,deps,schemas,tasks,seed,main}.py
│     app/routers/{auth,sync,photos,registry,ops}.py
│     app/services/{rules,storage,tagsheet,alerts,reports}.py
├─ dashboard/              React + TypeScript + Vite + MapLibre
└─ mobile/                 Flutter app (lib/, pubspec.yaml, l10n.yaml, patch-android.ps1)
```

## 1. Backend (Windows PowerShell, Docker Desktop running)
```powershell
cd C:\dev\kanha-qr
docker compose up -d --build
docker compose exec api python -m app.seed
docker compose exec api python -m pytest -q
```
API docs: http://localhost:8000/docs - MinIO console: http://localhost:9001 (minioadmin / minioadmin)

Demo logins (PIN 1234): admin +919999900001, manager +919999900002, supervisor +919999900003, field staff +919999900004.

## 2. Dashboard
```powershell
cd C:\dev\kanha-qr\dashboard
npm install
npm run dev
```
Open http://localhost:5173 (manager login is pre-filled).

## 3. Mobile app
```powershell
cd C:\dev\kanha-qr
flutter create --org com.megaminds --project-name kanha_qr --platforms android,ios kanha_app
xcopy mobile\lib kanha_app\lib /E /I /Y
copy mobile\pubspec.yaml kanha_app\pubspec.yaml /Y
copy mobile\l10n.yaml kanha_app\l10n.yaml /Y
del kanha_app\test\widget_test.dart
powershell -ExecutionPolicy Bypass -File mobile\patch-android.ps1
cd kanha_app
flutter pub get
flutter gen-l10n
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1
```
* Android emulator reaches your PC at `10.0.2.2`. For a real phone use your PC's LAN IP (`ipconfig`) in `API_BASE`
  AND in `.env` as `S3_PUBLIC_ENDPOINT=http://<LAN-IP>:9000`, then `docker compose up -d`.
* iOS: add NSCameraUsageDescription and NSLocationWhenInUseUsageDescription to ios/Runner/Info.plist.
* If `flutter gen-l10n` complains about `synthetic-package`, delete that line from l10n.yaml.

## 4. Quick test (acceptance criteria)
1. Dashboard > Registry > "Generate A4 sheet PDF" (20 tags) - print or open on a second screen.
2. Phone, login as supervisor, Scan tag (a demo tag code is printed by the seed command), answer the checklist, take photo, submit.
3. Switch the phone to airplane mode, do several scans, turn the network on: the badge counts down to "All synced" and rows appear in Dashboard > Inspection review. Re-sync never duplicates (idempotent client UUIDs).
4. Answer "No" to "Is the mat in place?" for a water-pit mat: an issue appears in Dashboard > Issues. Assign it, fix it from the app (scan the same tag + after-photo), verify it as manager.
