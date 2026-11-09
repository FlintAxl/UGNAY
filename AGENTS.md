# AGENTS.md

Monorepo with three independently run services (Windows / PowerShell): `backend/`
(FastAPI + MongoDB), `face-service/` (FastAPI + InsightFace), `ugnay_app/` (Flutter).
No CI, no backend linter/formatter, no Flutter tests. `docs/` is empty.

## Commands

Each Python service has its own `.venv` (git-ignored). Activate from inside the service:
`.\\.venv\\Scripts\\Activate.ps1`, then `pip install -r requirements.txt`.

Run from the service directory (CWD matters: backend loads `.env` from CWD):
- Backend: `cd backend` -> `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000`
- Face service: `cd face-service` -> `uvicorn main:app --reload --host 0.0.0.0 --port 8001`
- Backend tests (from `backend/`): `python -m pytest -q`
  Single file: `python -m pytest -q tests\test_ginger.py`
- Seeds (from `backend/`): `python seed_admin.py` (interactive, needs face service running),
  `python seed_items.py` then `python seed_items.py --stock item_stock.csv`
- Flutter (from `ugnay_app/`): `flutter pub get`; `flutter devices`;
  `flutter run -d <device-id>`; `flutter analyze`

## Backend (`backend/app`)

- All routers are mounted under `/api/v1` in `main.py`; the only unprefixed route is `/health`.
  Routers: `auth` (register + 2-step face login), `admin`, `logistics`, `production`.
- Config is `pydantic-settings` reading `backend/.env` (git-ignored, required): `DB_URI`,
  `JWT_SECRET`, `CLOUDINARY_*`; optional `FACE_SERVICE_URL`, `FACE_THRESHOLD`, `DATABASE_NAME`.
- MongoDB via Motor; collections/indexes live in `database.py` and indexes are created in the
  FastAPI lifespan. `release`/`return` use Mongo transactions (`start_session` +
  `start_transaction`) -> **requires a replica set (e.g. Atlas), standalone mongod will fail.**
- Money is MongoDB `Decimal128`; convert only via `d128()`/`dec()`/`money()` in `pricing.py`.
  All rounding is half-up to centavos and all calendar logic uses `Asia/Manila`.
- Pure business rules belong in `app/pricing.py` (rentals) and `app/ginger_math.py` (bidding),
  which are unit-tested; keep routers thin. Tests need no DB.
- Errors must go through `api_error()` -> `{"detail": {"code", "message", ...}}`; the Flutter
  `parseError` contract depends on this shape.
- Auth: argon2 passwords + JWT. `/auth/login` returns only a short-lived `face_token`;
  `/auth/verify-face` returns the access/refresh tokens. Registrations start `PENDING` /
  `UNASSIGNED`; roles are `admin` plus assignable `logistics|production|marketing|microfinance|savings`.
- Images are uploaded to Cloudinary as `type="authenticated"` and exposed only as signed URLs.
- Backend calls the face service (`FACE_SERVICE_URL`, default `http://localhost:8001`) for
  registration and login, so that service must be running. Default match threshold is `0.4`.

## Face service (`face-service`)

- InsightFace `buffalo_s` on CPU; `POST /face/embed` (multipart field `image`) returns a 512-D
  embedding. First run downloads model weights (needs network); keep `numpy<2`.
- `python compare_faces.py photos` measures same/different-person similarity to calibrate the threshold.

## Flutter app (`ugnay_app`)

- `lib/config.dart` hardcodes the API base URL (`http://192.168.100.97:8000/api/v1`). Change it per
  machine. Android emulator must use `10.0.2.2`, a physical phone needs the PC's LAN IP and same Wi-Fi.
- Navigation uses plain `Navigator`/`MaterialPageRoute`. `go_router` and `flutter_riverpod` are
  declared in `pubspec.yaml` but unused — do not assume that architecture.
- Role landing screen is chosen by `screenForRole()` in `lib/screens/home_screen.dart`.
- API code is split: `lib/api_client.dart` (Dio/errors/auth/admin), `lib/logistics_api.dart`
  (inventory + rentals), and `lib/production_api.dart` (ginger bidding). Token refresh/session
  handling is centralized in `api_client.dart`.
