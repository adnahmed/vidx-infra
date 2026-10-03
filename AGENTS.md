# AGENTS.md — quick project understanding

Read this first. It tells you what this workspace is, how to run it, how to
test it, and the rules that keep it working.

## What this is

`vidx-infra` is the **workspace root** for the vidx video editor. The code
lives in two git submodules:

| Path | GitHub | What it is |
|---|---|---|
| `backend/` | `adnahmed/vidx` | FastAPI + MongoDB (Beanie) + Celery + custom FFmpeg engine |
| `frontend/` | `adnahmed/vidx-app-1` | React 18 (CRA + CRACO) + Tailwind + wouter SPA |
| root | `adnahmed/vidx-infra` | infra docs, `render.yaml`, submodule pointers |

**Product** (branch `feature/social-media` on all three):
a **Video Studio** (existing transition-merger editor) plus a top-level
**Social Media** tab with two project types:

- **Social Media Campaign** — calendar-based post scheduling/publishing.
- **Video Production** — Excel-imported scenes, AI-image/video/audio
  generation through external providers, FFmpeg scene rendering and final
  assembly.

Deep dives: `PLAN.md` (plan + what was built + verification),
`BACKEND.md` (backend map), `FRONTEND.md` (frontend map),
`HANDOFF.md` (deployment record). `Architecture.md` and other root docs
describe the original merger project.

## Run locally

Prereqs: Python 3.11 + uv, Node + yarn, Docker (Mongo + RabbitMQ), and an
FFmpeg binary on PATH.

```powershell
# 1. Infrastructure (MongoDB + RabbitMQ)
cd backend; docker compose -f compose.dev.yml up -d   # or use existing containers

# 2. Backend API (http://127.0.0.1:8000)
cd backend; .\.venv\Scripts\python.exe -m uvicorn vidx.web.application:get_app --host 127.0.0.1 --port 8000 --factory
# env needed for generation/rendering locally:
$env:FFMPEG_BINARY="...\ffmpeg.exe"; $env:FFPROBE_BINARY="...\ffprobe.exe"
$env:VIDX_PUBLIC_BASE_URL="http://localhost:8000"   # webhook URL the simulated provider calls back

# 3. Celery worker (renders, assembly, scheduled publishing)
cd backend; .\.venv\Scripts\python.exe -m celery -A vidx.services.celery.worker.celery worker --loglevel=info --pool=solo

# 4. Frontend (http://localhost:3000)
cd frontend; $env:BROWSER="none"; yarn start
```

Register a user in the UI; the Social Media tab is in the sidebar.

## Test / build

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest tests -q          # 61 tests; in-memory Mongo (mongomock-motor)
$env:FFMPEG_BINARY="..."; ... -m pytest tests -q       # enables the 3 real-ffmpeg render tests
.\.venv\Scripts\ruff.exe check vidx/services/<dir>     # lint new code (repo has a legacy baseline)

cd frontend
yarn build                                             # type-check + production bundle
```

## Deployed topology (Render)

| Service | URL | Role |
|---|---|---|
| `vidx-backend` | https://vidx-backend.onrender.com | API + **embedded MongoDB + Redis** (private-network bindings) |
| `vidx-worker` | (worker-only web service) | Celery worker + beat; connects to `vidx-backend:27017/6379` |
| `vidx-frontend` | https://vidx-frontend-b7fm.onrender.com | static React bundle |

Deploy source: `feature/social-media` branches. `render.yaml` documents
env vars. Redeploy = push + trigger deploy per service. The embedded MongoDB
is ephemeral; external Atlas/managed Redis is the production path.

## Rules that keep it working

1. **External providers only.** No model inference in this repo. Everything
   goes through `vidx/services/providers/` (submit → job id → webhook →
   store → continue). `VIDX_AI_PROVIDER_MODE=http` selects real endpoints;
   `simulated` is a transport stand-in for dev/demo (FFmpeg artifacts, real
   signed webhooks).
2. **DB stores references, not blobs.** Generated media goes through
   `StorageService`; records keep a storage ref string.
3. **Never full-save a Scene concurrently.** Use `SceneDAO.update_component`
   / `update_fields` (atomic `$set` on component paths). Full-document saves
   clobber concurrent video/audio/subtitle work.
4. **Video requires a completed image.** Enforced in
   `GenerationOrchestrator._precondition_error`; the UI disables the button.
5. **Excel is import-only.** After import, scenes are edited/generated from
   the database; never re-read the workbook.
6. **Cap FFmpeg threads** (`-threads 1`, `x264-params threads=1:lookahead_threads=1`).
   The container sees all host CPUs; libx264 otherwise OOMs small instances.
7. **Split deployments share artifacts over HTTP.** Worker sets
   `VIDX_STORAGE_REMOTE_BASE_URL`; `LocalStorageStrategy` uploads to
   `POST /api/internal/artifacts` and downloads via `/api/media/generated/*`.
8. **Secrets stay in env.** `VIDX_JWT_SECRET`, `VIDX_PROVIDER_WEBHOOK_SECRET`,
   `VIDX_SCHEDULER_TOKEN`, `VIDX_INTERNAL_TOKEN`, `REDIS_PASSWORD`,
   `VIDX_LINKEDIN_*`, `VIDX_AI_*_API_KEY`. Never commit them; never send
   them to the client.
9. **Hash routing is intentional.** Render static sites lack SPA fallback;
   `App.tsx` uses `useHashLocation`. Deep links are `/#/login`, `/#/signup`.
10. **Webhook handlers must stay idempotent + correlated.**
    `handle_callback` matches provider + job id + correlation id, ignores
    duplicates, and rejects mismatches.
11. **Windows dev quirks**: CRLF warnings on commit are cosmetic; use
    `--pool=solo` for Celery on Windows; scripts use
    `.\.venv\Scripts\python.exe` (uv-managed venv, no bare `pip`).

## Where things live (cheat sheet)

```
backend/vidx/
  db/models/{project,scene,social_post}.py     # Project, Scene, SocialPost, ComponentState
  db/dao/project_dao.py                        # ProjectDAO, SceneDAO, SocialPostDAO (atomic updates)
  services/social/                             # platform interface, LinkedIn, registry, publishing
  services/providers/                          # AIProvider, HTTP + simulated providers, webhook signing
  services/generation/orchestrator.py          # submit/gating/callback continuation
  services/render/ffmpeg_render.py             # scene render + final assembly
  services/excel/importer.py                   # Excel parsing/validation
  services/storage/                            # local + S3 (+ HTTP artifact bridge)
  services/celery/{tasks,worker,db}.py         # render/assembly/publish tasks, beat, worker Beanie
  web/api/{projects,posts,scenes,webhooks,media,internal}/views.py
  web/api/projects/schema.py                   # request/response models
frontend/src/
  components/social/SocialMediaTab.tsx         # project list + create modal
  components/social/CampaignProjectView.tsx    # calendar + day modal + post form
  components/social/VideoProductionView.tsx    # scenes, generation, rendering
  lib/projectsApi.ts                           # typed API client (401 handling)
```

## When in doubt

- Run `pytest` and `yarn build` before calling anything done.
- For deploy issues, check the Render service events
  (`oomKilled` is the usual suspect) and `render.yaml` env drift.
- If a generation job is stuck in `processing`, check the worker service
  logs — Celery `acks_late` will redeliver after a crash, and re-submitting
  with `force: true` is always safe.
