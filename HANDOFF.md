# vidx-infra — Project Handoff

This document is the single source of truth for the next agent working on `vidx-infra`.
It captures what the project is, how to run it, what was verified, and the bugs that were
found and fixed on 2026-10-02.

## 1. What this project is

A video-transition SaaS ("vidx" / clipifie):

- **Frontend** — a React single-page app where a user signs up, picks 2+ video clips, picks a
  GLSL transition, optionally adds audio, and submits a merge request.
- **Backend** — a FastAPI control plane that accepts uploads, validates them, and dispatches
  async merge jobs.
- **Worker** — Celery workers that do the heavy FFmpeg rendering (with a custom
  `gl-transition` FFmpeg build) out of band from the HTTP request.
- **Storage** — MongoDB (job/user metadata) + RabbitMQ (job queue) + object storage
  (S3/local) for the large media files.

`backend/` and `frontend/` are **git submodules** (`.gitmodules`):
`backend` → `github.com/adnahmed/vidx`, `frontend` → `github.com/adnahmed/vidx-app-1`.
The repo root holds infra/deploy assets only (docker-compose, terraform, k8s, nginx, docs).

## 2. Repo layout

```
vidx-infra/
  backend/            # FastAPI + Celery (git submodule)
    vidx/web/         # FastAPI app (routes, middleware, lifespan)
    vidx/db/          # Beanie models + DAOs (MongoDB)
    vidx/services/    # Celery worker, task execution, storage, auth
    vidx/settings.py  # pydantic-settings config (env prefix VIDX_)
    compose.dev.yml   # Mongo + RabbitMQ only (dev deps)
    Dockerfile        # full image incl. custom gl-transition ffmpeg build
    .venv/            # uv-managed venv, CPython 3.13.5
  frontend/           # React CRA + CRACO (git submodule)
    src/lib/api.ts    # API base URL logic
    src/lib/auth.ts   # localStorage session
    src/components/   # Dashboard, VideoUploader, TransitionGallery, ...
    public/videos/sintel/  # sample clips cut1-3 (.mp4/.webm)
  docker-compose.yml  # full app stack (api, db, rabbitmq, celery, frontend, nginx)
  docker-compose.localstack.yml  # LocalStack + Mongo + RabbitMQ (alt dev deps)
  Architecture.md     # the architecture doc
  ...
```

## 3. How to run locally (verified working)

Prerequisite infra (already running via Docker):
```powershell
docker compose -f backend/compose.dev.yml up -d   # Mongo :27017, RabbitMQ :5672/:15672 (vidx/vidx)
```

Backend (FastAPI, port 8000) — from `backend/`:
```powershell
$env:FFPROBE_BINARY = "C:\Users\Adnan\AppData\Local\Microsoft\WinGet\Links\ffprobe.exe"
$env:FFMPEG_BINARY  = "C:\Users\Adnan\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe"
.\.venv\Scripts\python.exe -m uvicorn vidx.web.application:get_app --host 127.0.0.1 --port 8000 --reload --factory
```

Celery worker — from `backend/` (note `--pool=solo`; the default prefork pool breaks when the task
shells out to ffmpeg on Windows):
```powershell
.\.venv\Scripts\python.exe -m celery -A vidx.services.celery.worker.celery worker --loglevel=info --pool=solo
```

Frontend (CRA dev server, port 3000) — from `frontend/`:
```powershell
yarn start
```

Health/smoke: `GET http://127.0.0.1:8000/api/health` → 200; Swagger at `/api/docs`.

> **Critical run-time gotchas**
> - Run from `backend/`, NOT the repo root — `settings.py` uses `env_file=".env"` and the repo
>   root `.env` contains `LOCALSTACK_AUTH_TOKEN`, which pydantic-settings rejects as an extra field.
> - Do **not** use `python -m vidx`: with `reload=False` (the default) it selects Gunicorn,
>   which is Linux-only. Use the explicit `uvicorn … --factory` command above.
> - `FFPROBE_BINARY` must point at a real ffprobe or `POST /video/merge` 500s during validation.

## 4. Backend map

- **Stack:** FastAPI 0.115.12, Python 3.13.5 (uv), Beanie (async ODM) over Motor → **MongoDB**,
  Celery 5.5.2 over **RabbitMQ** (broker) + **MongoDB** (result backend).
- **Everything is mounted under `/api`** (`vidx/web/application.py` mounts
  `api_router` with `prefix="/api"`). Docs live at `/api/docs`, `/api/redoc`, `/api/openapi.json`.
- **Auth middleware** (`vidx/web/middleware/auth.py`) protects only `/api/video/*`
  (`protected_prefix = "/api/video"`); auth/transcript routes are open. JWT HS256, default
  secret `"change_me"` (`VIDX_JWT_SECRET`), 60 min expiry.

### Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/health` | public | |
| POST | `/api/auth/register` | public | `{email, password(≥8), full_name?}` → `{access_token, token_type, provider}` |
| POST | `/api/auth/login` | public | `{email, password}` → token |
| GET | `/api/auth/google/login` · `/callback` | public | OAuth |
| POST | `/api/auth/logout` | Bearer | |
| POST | `/api/video/merge` | Bearer | multipart `transition` + `videos[]` (+ optional `audio`) → 202 `{task_id, status}` |
| GET | `/api/video/merge?task_id=` | Bearer | returns merged file |
| GET | `/api/video/merge/status?task_id=` | Bearer | returns `VideoStatus` string |
| GET | `/api/video/history` | Bearer | |
| POST | `/api/transcript/fetch` and others | public | transcript module |

### Upload validation rules (`vidx/web/api/video/schema.py`)

- Videos: **min 2, max 10**; all must share the **same MIME and resolution** (checked via ffprobe).
- Valid video MIME: `video/mp4`, `video/webm`, `video/ogg`; audio: `audio/mpeg`, `audio/wav`, `audio/ogg`.
- Optional audio must be **≥** total video duration (longer audio is cropped via ffmpeg).
- MIME detection uses `python-magic` when available, else `mimetypes` fallback (Windows path).

### Worker / task execution (`vidx/services/celery/tasks.py`)

- Task `vidx.tasks.merge_videos` → `ExecutionStrategyFactory`: `LocalProcessExecutor` in dev
  (`environment=dev`), AWS Batch in prod/staging.
- `_merge_videos_sync` shells out to ffmpeg with `gltransition=…:source=<shader>.glsl` filters.
  **Requires the custom gl-transition-patched ffmpeg** (built in `backend/Dockerfile`,
  `build_ffmpeg_gl_transitions.{sh,ps1}`). Shader `.glsl` files must sit next to the ffmpeg binary.
- Writes intermediate/final files to hardcoded `/tmp/...` → **the actual merge only runs on Linux
  (Docker/WSL), not Windows.**

## 5. Frontend map

- **Stack:** React 18 + Create React App + CRACO, `wouter` routing, Tailwind, `motion`,
  `gl-react`/`gl-transitions` (WebGL preview). Plain `fetch`, no axios, no global store.
- **Routes** (`src/App.tsx`): `/` → Main, `/login`, `/signup`, fallback 404. `Main.tsx` reads the
  localStorage session and renders Dashboard vs LandingPage.
- **API base URL** (`src/lib/api.ts`): dev → `http://localhost:8000/api`; prod →
  `REACT_APP_API_URL` or fallback `http://212.85.25.109:8000`. `.env.production` uses `/api`
  (same-origin reverse proxy).
- **Auth** (`src/lib/auth.ts`): localStorage keys `authToken`, `authTokenType`, `authProvider`,
  `userEmail`, `userName`, `planMaxVideos`; header = `Authorization: <type> <token>`.
- **Merge flow** (`src/components/Dashboard.tsx`): `VideoUploader` (2+ files) → `TransitionGallery`
  → `AudioUploader` (optional) → `handleMerge` posts multipart → polls
  `/api/video/merge/status?task_id=` every 2s until SUCCESS/FAILURE.
- Sample clips live in `frontend/public/videos/sintel/` (all h264 1280×544 @24fps, 5s).

## 6. What was verified end-to-end (2026-10-02)

Ran the full flow against the live backend + worker (native Windows, infra in Docker):

1. **Register** — two local users registered successfully (201, JWT returned).
2. **Login** — 200, JWT returned.
3. **Merge submit** — `POST /api/video/merge` (multipart `transition=fade` + `cut1.mp4` +
   `cut2.mp4`) → **202** `{"task_id":"…","status":"PENDING"}`.
4. **Worker pickup** — Celery received the task from RabbitMQ and ran `_merge_videos_sync`.
5. **Status** — `/api/video/merge/status` transitioned `PENDING` → **`FAILURE`**.

The `FAILURE` is the **expected** outcome for this session: the merge shell-out uses the standard
ffmpeg which has no `gltransition` filter (`No such filter: 'gltransition'`), because the custom
gl-transition ffmpeg build only runs in Linux/Docker. This still proves the full
API → RabbitMQ → worker → status pipeline. (Full ffmpeg E2E is deferred.)

## 7. Bugs found & fixed

1. **`_resolve_submitted_name` crash** (`vidx/web/api/video/views.py`) — `isinstance(upload, UploadFile)`
   is `False` for the `starlette.datastructures.UploadFile` that FastAPI's multipart parser actually
   produces (`fastapi.datastructures.UploadFile` is a subclass). It fell through to `httpx.URL(upload)`
   → 500 on every merge. **Fix:** check `isinstance(upload, (UploadFile, StarletteUploadFile))`.
2. **`google_sub` unique index collision** (`vidx/db/models/user.py`) — `Indexed(unique=True)` on an
   optional field means every local user (with `google_sub=null`) collides (`E11000 dup key google_sub: null`),
   so only one local user could ever register. **Fix:** partial unique index
   `Indexed(unique=True, partialFilterExpression={"google_sub": {"$type": "string"}})`.
   (Also dropped the stale non-partial `google_sub_1` index from Mongo so Beanie could recreate it.)

## 8. Known gotchas / risks (for the next agent)

- `/api` prefix everywhere — health is `/api/health`; calls without the prefix 404.
- Only `/api/video/*` is auth-protected; auth/transcript routes are unauthenticated.
- `python -m vidx` → Gunicorn (Linux-only); use `uvicorn … --factory`.
- Root `.env` (`LOCALSTACK_AUTH_TOKEN`) breaks `Settings()` if you launch from repo root; run from `backend/`.
- `FFPROBE_BINARY` must be set on Windows or upload validation 500s.
- Gl-transition merge can't run on Windows (`/tmp/...` + missing patched ffmpeg); use Docker/WSL for real merges.
- Transition naming mismatch: frontend sends lowercase gl-transitions names; dashed names like
  `coord-from-in` fail `Transition[value.upper()]` (a `KeyError`); `fade`/`circleopen` are safe.
- `backend/Dockerfile` and `backend/compose.yml` still reference `poetry`/`poetry.lock`, but the repo
  now uses `uv`/`uv.lock` — Docker builds will fail until migrated.
- Google OAuth `clientId` is hard-coded in `frontend/src/App.tsx` and the callback is unverified/hypothetical.
- No automated e2e tests for the workflow (only pytest scaffolding + auth unit tests).
- Celery on Windows: use `--pool=solo` (prefork breaks when the task spawns ffmpeg subprocesses).

## 9. Render deployment

The deployment is split so each service fits comfortably in a 512 MB
instance (an all-in-one container OOM-killed the 512 MB starter during
concurrent FFmpeg work):

- `vidx-backend` (web, Docker, `adnahmed/vidx`,
  `https://vidx-backend.onrender.com`): FastAPI + embedded MongoDB + Redis.
  MongoDB/Redis bind `0.0.0.0` and are reachable only over Render's private
  network (the public route only maps the assigned port). `VIDX_RUN_WORKER=false`.
- `vidx-worker` (web, worker-only mode, `dockerCommand=render-entrypoint.sh`):
  Celery worker + beat with an HTTP health shim on `$PORT`; connects to
  `vidx-backend:27017` / `vidx-backend:6379` over the private network.
- `vidx-frontend` (static site, `adnahmed/vidx-app-1`,
  `https://vidx-frontend-b7fm.onrender.com`): hash-routed SPA; the app uses
  hash routing because Render static sites have no SPA rewrite rule.

Artifact bridge: the worker and API have separate ephemeral filesystems, so
`VIDX_STORAGE_REMOTE_BASE_URL` on the worker makes `LocalStorageStrategy`
upload generated artifacts to `POST /api/internal/artifacts` (shared
`VIDX_INTERNAL_TOKEN`) and download API-owned artifacts back through
`/api/media/generated/*`. Local storage therefore behaves like a shared
object store across containers.

Memory/CPU guards: `VIDX_SIMULATED_MAX_CONCURRENCY=1`, `MALLOC_ARENA_MAX=2`,
Redis `maxmemory 32-64mb`, and all FFmpeg renders use `-threads 1` +
`x264-params threads=1:lookahead_threads=1` (libx264 otherwise allocates
per-CPU thread buffers and OOMs small instances). Celery runs with
`task_acks_late` + `task_reject_on_worker_lost` so a crashed render is
redelivered instead of lost.

Env summary: `QUEUE_TYPE=redis`, `VIDX_EMBEDDED_MONGO/REDIS=true` (API),
`VIDX_AI_PROVIDER_MODE=simulated`, `VIDX_PUBLIC_BASE_URL`,
`VIDX_CORS_ORIGINS`, `VIDX_JWT_SECRET`, `VIDX_PROVIDER_WEBHOOK_SECRET`,
`VIDX_SCHEDULER_TOKEN`, `VIDX_INTERNAL_TOKEN`, `REDIS_PASSWORD`.
`render.yaml` (repo root) documents the topology; services were created via
the Render MCP, so blueprint sync is manual.

For production, point `VIDX_DB_*` at MongoDB Atlas and Redis/RabbitMQ at
managed services, disable the embedded flags, and configure real AI
provider endpoints (`VIDX_AI_*_ENDPOINT/API_KEY/MODEL`) plus LinkedIn
credentials.

## 10. Social Media module (added 2026-10-03)

A top-level **Social Media** tab with two project types:

- **Social Media Campaign** — create projects (platform, name, description,
  image/logo, start/end dates, timezone), calendar over the project range
  with per-day post counts, day modal, post add/edit/delete/save, timezone
  aware scheduling, platform-limit validation, Draft/Scheduled/Published/
  Failed states, and publish (LinkedIn adapter behind an extensible platform
  interface; Facebook/Instagram/Threads/X/TikTok/YouTube registered as
  planned).
- **Video Production** — Excel import only (one row per scene: image/scene/
  audio prompts, optional scene number derived from row order), scenes
  persisted with the database as source of truth, editable prompts,
  independent per-component regeneration (image → video gating), and
  generated asset references with provider job ids/correlation ids and
  timestamps.
- **Generation pipeline** — external provider contract
  (submit → job id → webhook → store → continue) behind `AIProvider`
  (generic HTTP provider + a simulated transport stand-in used for
  offline/demo verification; no internal model inference). Signed webhooks
  with HMAC validation, correlation and idempotency.
- **Rendering** — FFmpeg scene post-processing (logo overlay, subtitles,
  audio) and final assembly via the existing configured ffmpeg binary.

See `BACKEND.md` and `FRONTEND.md` for full module maps, and the local E2E
evidence in the goal session log.

## 11. Next agent TODO

- [ ] Full ffmpeg gl-transition merge E2E in the deployed container.
- [ ] Wire real external AI provider endpoints (`VIDX_AI_PROVIDER_MODE=http`
      + per-component endpoints/keys/models) and LinkedIn credentials.
- [ ] Move the deployment to managed MongoDB Atlas / Redis outside Render for
      durable storage (embedded Mongo on the container fs is ephemeral).
- [ ] Optional: split the Celery worker into a Render background worker via
      the dashboard blueprint sync.
