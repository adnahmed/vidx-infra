# PLAN — Social Media module (Video Production + Social Media Campaign)

_Status: **COMPLETE**. Implemented, tested, deployed to Render, and verified
in the deployed environment (2026-10-03)._

This document is the implementation plan plus a full record of what was
actually built, changed, debugged, and verified. It supersedes nothing in
`Architecture.md` / `IMPLEMENTATION_SUMMARY.md` (those describe the original
video-merger project); it describes the Social Media module added on top.

---

## 1. Objective

Add a top-level **Social Media** tab to the existing React + Python video
editor with two project types:

- **Social Media Campaign** — validated project creation, LinkedIn behind an
  extensible platform interface, a calendar over the project date range with
  per-day post counts, day modals, post CRUD, timezone-aware scheduling, and
  Draft/Scheduled/Published/Failed publishing.
- **Video Production** — Excel import (one row per scene), database as the
  source of truth after import, editable prompts, independent per-component
  regeneration, generated-asset references, and full status/error/job
  tracking.

Generation must go through **external provider APIs only** (no internal
model inference), using an async contract:
`submit job → provider job id → processing → webhook → store result →
continue pipeline`. The existing Python/FFmpeg engine is reused for
post-processing and final rendering; the database stores **references**, not
media blobs.

Authoritative spec: `C:\Users\Adnan\claude-exports\seed-full.md` plus the
detailed task brief (both preserved as constraints).

---

## 2. Architecture

```
                    ┌───────────────────────────────┐
  Browser ─────────►│ vidx-frontend (static, React) │
                    │ hash routing, Social Media tab│
                    └──────────────┬────────────────┘
                                   │ HTTPS/JSON + Bearer JWT
                    ┌──────────────▼────────────────┐
                    │ vidx-backend (FastAPI)        │
                    │  /api/projects /posts /scenes │
                    │  /api/webhooks/{provider}     │──┐ signed callbacks
                    │  /api/media/generated/*       │  │
                    │  /api/internal/artifacts      │  │
                    │  embedded MongoDB + Redis     │◄─┘
                    └──────────────┬────────────────┘
                       private net │ 27017 / 6379
                    ┌──────────────▼────────────────┐
                    │ vidx-worker (Celery + beat)   │
                    │ renders, final assembly,      │
                    │ publish-due-social-posts      │
                    └───────────────────────────────┘

  Providers (external):  HTTPAIProvider (generic HTTP, prod)
                         SimulatedProvider (transport stand-in, demo/dev)
```

Key decisions:

| Decision | Rationale |
|---|---|
| Single `Project` collection with `project_type` discriminator | both types share the list/create UI and lifecycle |
| `ComponentState` sub-documents on `Scene` | per-component status, provider job id, correlation id, storage ref, error, timestamps |
| Atomic MongoDB `$set`/`$inc` per component path | concurrent submissions/callbacks must not clobber each other |
| `SocialPlatformAdapter` interface + registry | LinkedIn first; facebook/instagram/threads/x/tiktok/youtube registered as planned |
| Celery beat + atomic claim for due posts | timezone-aware `scheduled_at_utc`, stale-claim reclaim, no double publish |
| HMAC-signed webhooks with job-id + correlation-id match | authenticity and safe correlation; duplicates are idempotent |
| `AIProvider` with `submit_job` / `parse_webhook` | endpoint, credentials, model, params all external env config |
| `SimulatedProvider` transport stand-in | exercises the real async contract without credentials; produces artifacts with FFmpeg (no model inference) |
| Reuse `settings.ffmpeg` for new rendering | logo overlay, subtitle burn-in, audio mux, concat — engine untouched |
| Split Render topology (API+data / worker / static site) | 512 MB instances OOM'd all-in-one; worker is stateless |
| HTTP artifact bridge for local storage | API and worker have separate filesystems; upload/download keeps `local` storage usable |

---

## 3. Phase plan and completion

| # | Phase | Status | Evidence |
|---|---|---|---|
| 1 | Recon: seed spec, repo, Render capabilities | done | service/DB inventory, Render MCP docs |
| 2 | Backend models, DAOs, atomic updates | done | `db/models/{project,scene,social_post}.py`, `db/dao/project_dao.py` |
| 3 | Storage extensions (`save_bytes`, `save_from_url`, `materialize`) | done | `services/storage/*`, storage tests |
| 4 | Platform interface + LinkedIn adapter + registry | done | `services/social/*`, registry/compat tests |
| 5 | Campaign validation + scheduling/publishing | done | `services/social/service.py`, Celery task, scheduler endpoint, DST test |
| 6 | Provider abstraction (HTTP + simulated) + webhooks | done | `services/providers/*`, provider tests |
| 7 | Generation orchestrator (gating, correlation, continuation) | done | `services/generation/orchestrator.py`, orchestrator tests |
| 8 | FFmpeg render service (scene render, logo, subtitles, assembly) | done | `services/render/*`, real-ffmpeg tests |
| 9 | Excel import (openpyxl) | done | `services/excel/importer.py`, importer tests |
| 10 | REST API routes + auth prefixes + media/internal routes | done | `web/api/{projects,webhooks,media,internal}/*` |
| 11 | Frontend: Social Media tab, project create, calendar, video production | done | `src/components/social/*`, `projectsApi.ts`, Dashboard tab |
| 12 | Tests + local browser E2E | done | 61 backend tests; browser session logs |
| 13 | Docker/deploy prep (uv, bookworm, entrypoints, redis broker) | done | `Dockerfile`, `render-entrypoint.sh`, `render.yaml` |
| 14 | Push feature branches to GitHub | done | backend `bd2f902..68a9439`, frontend `5988c40..f24f889`, infra `14404c0..e8791a5` |
| 15 | Render deployment (api + worker + static site) | done | services live, API health 200 |
| 16 | Deployed E2E verification + fixes | done | final 2,574,702-byte MP4 produced and served |
| 17 | Docs (this file, AGENTS.md, BACKEND/FRONTEND/HANDOFF updates) | done | repo docs |

---

## 4. What was implemented (file map)

### Backend (`adnahmed/vidx @ feature/social-media`)

- **Models**: `Project`, `SocialPost`, `Scene` + `ComponentState`
  (status/provider/provider_job_id/correlation_id/storage_ref/error/
  attempts/submitted_at/completed_at).
- **DAOs**: `ProjectDAO`, `SceneDAO` (incl. atomic `update_component`,
  `update_fields`, `find_by_provider_job`), `SocialPostDAO`.
- **Social**: `SocialPlatformAdapter`, `LinkedInAdapter`
  (`/rest/posts` + image upload + hashtag/link composition),
  `PlatformRegistry`, `SocialPublishingService` (validation, timezone math,
  publish), scheduler task and `/api/social/scheduler/run`.
- **Providers**: `AIProvider` ABC, `HTTPAIProvider`, `SimulatedProvider`
  (FFmpeg artifacts + real signed webhooks; concurrency capped),
  HMAC `sign_payload`/`verify_signature`.
- **Generation**: `GenerationOrchestrator` (preconditions incl. video-after-
  image gating, job submission, correlation, callback handling, storage).
- **Rendering**: `RenderService` (scale/pad, logo overlay, subtitle burn-in,
  silent-track fallback, video concat), Celery `render_scene` and
  `assemble_project_video` tasks, `svc/celery/db.py` worker Beanie bootstrap.
- **Excel**: `parse_scene_workbook` with header aliases, derived scene
  numbers, duplicate/invalid-row rejection.
- **API**: `/api/projects*`, `/api/posts*`, `/api/scenes*`,
  `/api/social/platforms`, `/api/webhooks/{provider}`,
  `/api/media/generated/{name}`, `/api/internal/artifacts`.
- **Infra changes**: Redis broker support, `application.py` CORS from env,
  auth middleware 401 fix (invalid/expired JWT no longer 500s), uv Dockerfile
  on `python:3.11-slim-bookworm`, embedded Mongo (`--auth` + localhost-
  exception user bootstrap) and Redis, worker-only entrypoint mode.

### Frontend (`adnahmed/vidx-app-1 @ feature/social-media`)

- `SocialMediaTab` (project list + create modal with end ≥ start validation,
  platform/date/timezone/image fields).
- `CampaignProjectView` (month calendar over the range, day counts, day
  modal with post list, add/edit/delete/publish).
- `VideoProductionView` (Excel import, editable prompts, per-component
  Generate/Regenerate, video-after-image gating, asset previews, scene
  render, final assembly, 3 s status polling).
- `AuthedMedia` (object-URL image/video loading + status badges).
- `projectsApi.ts` typed client with 401 session handling; hash routing in
  `App.tsx`; Dashboard nav integration.

### Infra (`adnahmed/vidx-infra @ feature/social-media`)

- `render.yaml` (split topology), `HANDOFF.md` (deployment record),
  `BACKEND.md` / `FRONTEND.md` (module maps), this `PLAN.md`, `AGENTS.md`.

---

## 5. Verification evidence

### Tests / build (local)

- `cd backend && pytest tests -q` with `FFMPEG_BINARY` set → **61 passed**
  (includes real-ffmpeg scene render, silence fallback, concat duration).
- `cd frontend && yarn build` → production bundle builds.

### Local end-to-end (browser + Docker)

- Browser: register/login; campaign create (end<start blocked); calendar
  counts; post add/edit; publish → Failed with exact LinkedIn credential
  error; Excel import of 3 scenes; image → gated video/audio/subtitles;
  independent regeneration (image job id changed, other component job ids
  untouched); scene renders; final assembly.
- Exact deployment image run locally (`render-entrypoint.sh` with embedded
  Mongo/Redis/worker): full pipeline, final video 2,808,527 bytes.

### Render deployment (verified)

- Services live: `vidx-backend` (`https://vidx-backend.onrender.com`,
  API+embedded Mongo/Redis), `vidx-worker` (Celery+beat, private network),
  `vidx-frontend-b7fm.onrender.com` (static).
- Deployed E2E: register → project → Excel import → image → video/audio/
  subtitle → 3/3 scene renders → final assembly →
  **final MP4 2,574,702 bytes downloaded through the authenticated API**.
- Deployed campaign: day badge + day modal showing the FAILED post with
  `LinkedIn is not configured on the server. Missing:
  VIDX_LINKEDIN_ACCESS_TOKEN, VIDX_LINKEDIN_AUTHOR_URN`; Celery beat fired
  `publish-due-social-posts` and transitioned the post.
- Deployed UI: project card `COMPLETED`, scene video players, SRT download,
  existing Video Studio editor intact (screenshot captured).

---

## 6. Bugs found and fixed during verification

| # | Bug | Fix |
|---|---|---|
| 1 | Debian 11 (bullseye) security pool 404s — base image EOL | migrated Dockerfile to `python:3.11-slim-bookworm` (package renames incl. libvpx7/libx264-164/libx265-199/libglew2.2) |
| 2 | `gpg` missing for the MongoDB apt key | install `gnupg` |
| 3 | gl-transitions `dissolve.glsl` normalization assumed a directory | handle file-or-directory, assert the file exists |
| 4 | `pip wheel .` re-resolved latest deps → duplicate conflicting wheels; `|| true` swallowed the install failure | `--no-deps` + scoped the cleanup so pip failure aborts the build |
| 5 | custom ffmpeg missing `libsndio.so.7` at runtime | `libsndio7.0` in the runtime stage |
| 6 | embedded mongod without auth rejected credentialed clients | run with `--auth` + create the app user via the localhost exception |
| 7 | expired/invalid JWT fell through to Google verification → 500 without CORS headers (browser "Failed to fetch") | middleware returns 401 for unverifiable tokens |
| 8 | Render static sites have no SPA fallback (deep links 404) | switched the app to hash routing; 401 handler uses `#/login` |
| 9 | concurrent component submissions clobbered each other via full-document saves | atomic per-component Mongo updates (`$set`/`$inc` on component paths) |
| 10 | 512 MB all-in-one container OOM-killed under concurrent simulated ffmpeg | split worker into its own service; `VIDX_SIMULATED_MAX_CONCURRENCY=1`; `MALLOC_ARENA_MAX=2`; Redis maxmemory cap |
| 11 | worker couldn't read API-local generated files (separate filesystems) | HTTP artifact bridge: `POST /api/internal/artifacts` + remote upload/download in `LocalStorageStrategy` |
| 12 | libx264 saw all host CPUs and allocated huge thread buffers → worker OOM during renders/assembly | `-threads 1` + `-x264-params threads=1:lookahead_threads=1` everywhere |
| 13 | worker crashed mid-task and the task was silently lost | Celery `task_acks_late` + `task_reject_on_worker_lost` |

---

## 7. Deployment runbook (Render)

Current topology (created through the Render MCP; `render.yaml` documents it):

| Service | Type | Repo / branch | Notes |
|---|---|---|---|
| `vidx-backend` | web + Docker | `adnahmed/vidx` @ `feature/social-media` | API + embedded MongoDB/Redis; `dockerCommand=/usr/local/bin/render-entrypoint.sh`; health `/api/health` |
| `vidx-worker` | web + Docker | same | `VIDX_WORKER_ONLY=true`, `VIDX_RUN_WORKER=true`; Celery+beat + HTTP health shim; talks to `vidx-backend:27017/6379` (private network) |
| `vidx-frontend` | static | `adnahmed/vidx-app-1` @ `feature/social-media` | `yarn install && yarn build`, publish `build`, `REACT_APP_API_URL=https://vidx-backend.onrender.com/api` |

Key environment (see `render.yaml` for the full list):

- Shared: `QUEUE_TYPE=redis`, `REDIS_PASSWORD`, `VIDX_INTERNAL_TOKEN`,
  `VIDX_JWT_SECRET`, `VIDX_PROVIDER_WEBHOOK_SECRET`, `VIDX_SCHEDULER_TOKEN`.
- Backend: `VIDX_EMBEDDED_MONGO=true`, `VIDX_EMBEDDED_REDIS=true`,
  `VIDX_RUN_WORKER=false`, `VIDX_PUBLIC_BASE_URL`, `VIDX_CORS_ORIGINS`,
  `VIDX_AI_PROVIDER_MODE=simulated`, `VIDX_SIMULATED_MAX_CONCURRENCY=1`.
- Worker: `VIDX_DB_HOST=vidx-backend`, `VIDX_DB_PORT=27017`,
  `VIDX_DB_USER/PASS=vidx`, `REDIS_HOST=vidx-backend`,
  `VIDX_STORAGE_REMOTE_BASE_URL=https://vidx-backend.onrender.com`.

Redeploy: push to the branch, then trigger a deploy per service
(dashboard or Render MCP `trigger_deploy`). After an API restart the
embedded MongoDB is empty (container filesystem) — data is re-created by
import; production should use MongoDB Atlas.

To switch to production providers:

```
VIDX_AI_PROVIDER_MODE=http
VIDX_AI_IMAGE_ENDPOINT / VIDX_AI_IMAGE_API_KEY / VIDX_AI_IMAGE_MODEL
VIDX_AI_VIDEO_ENDPOINT / ...      (same for AUDIO/SUBTITLE)
VIDX_LINKEDIN_ACCESS_TOKEN / VIDX_LINKEDIN_AUTHOR_URN
VIDX_DB_* (Atlas) and RABBITMQ_* or REDIS_* (managed), embedded flags off
```

---

## 8. Known limitations / next steps

- **No external AI credentials or LinkedIn token were supplied**, so the
  deployed pipeline runs the `simulated` provider transport and publishing
  fails with an explicit configuration error. The adapters are real; only
  env config is missing.
- Embedded MongoDB/Redis on Render live on the container filesystem
  (ephemeral); use Atlas/managed Redis for durable data.
- The pre-existing gl-transition merge engine is unchanged and was not
  exercised in the deployed container (its custom ffmpeg build is intact).
- Optional: move the Celery worker to a Render background worker via
  blueprint sync; add S3-compatible storage (`STORAGE_TYPE=s3`) to drop the
  HTTP artifact bridge.
