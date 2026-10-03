# vidx backend map

FastAPI control plane + Celery workers for the video editor, extended with
the Social Media module (Social Media Campaigns + Video Production).

## Stack

- **FastAPI** 0.115 (mounted under `/api`), **Beanie/Motor** over MongoDB.
- **Celery** 5.5 with a pluggable broker: RabbitMQ (default), Redis
  (`QUEUE_TYPE=redis`, used by the Render deployment), or SQS.
- **Storage**: local filesystem or S3 (`STORAGE_TYPE`); generated media is
  referenced by location string, never stored as a database blob.
- **FFmpeg**: the configured `FFMPEG_BINARY`/`FFPROBE_BINARY` (custom
  gl-transition build in Docker) is reused for all rendering.

## Existing endpoints (unchanged)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/health` | |
| POST | `/api/auth/register`, `/api/auth/login`, `/api/auth/logout` | JWT |
| POST | `/api/video/merge` | multipart transition merge (202 + task id) |
| GET | `/api/video/merge/status?task_id=` | Celery state |
| GET | `/api/video/merge?task_id=` | merged file |
| GET | `/api/video/history` | |
| POST | `/api/transcript/fetch` | transcript module |

Auth middleware protects `/api/video`, `/api/projects`, `/api/posts`,
`/api/scenes`. Webhooks and generated-media routes are public but
signature-validated / unguessable.

## Social Media module

### Models (`vidx/db/models/`)

- `Project` — `project_type` (`social_campaign` | `video_production`), name,
  description, platform, dates, timezone, image ref, status,
  `final_video: ComponentState`.
- `SocialPost` — content, image ref, link, hashtags, local date/time +
  IANA timezone, `scheduled_at_utc`, status
  (Draft/Scheduled/Published/Failed), provider post id, error, claim
  timestamps.
- `Scene` — scene number, image/scene/audio prompts, and per-component
  `ComponentState` for image, video, audio, subtitle and final render
  (status, provider, provider job id, correlation id, storage ref, error,
  attempts, submitted/completed timestamps), plus derived `overall_status`.

All component updates are **atomic per-field Mongo updates** so concurrent
submissions/callbacks (e.g. video + audio + subtitles together) never
clobber each other.

### REST API

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/social/platforms` | platform capabilities (LinkedIn available; others planned) |
| GET/POST | `/api/projects` | list (filter `project_type`) / create (multipart with image) |
| GET/PATCH/DELETE | `/api/projects/{id}` | detail / update / delete (cascades posts+scenes) |
| POST | `/api/projects/{id}/image` | upload project image/logo |
| GET | `/api/projects/{id}/calendar` | calendar days + per-day counts + posts |
| GET/POST | `/api/projects/{id}/posts` | list (optional `date=`) / create (multipart) |
| PUT/DELETE | `/api/posts/{id}` | update / delete |
| POST | `/api/posts/{id}/publish` | immediate publish attempt |
| POST | `/api/social/scheduler/run` | publish due Scheduled posts (token-protected when configured) |
| POST | `/api/projects/{id}/import-scenes?mode=replace\|append` | Excel import (openpyxl) |
| GET | `/api/projects/{id}/scenes` | scene list with component states |
| POST | `/api/projects/{id}/generate-all` | bulk component submission |
| POST | `/api/projects/{id}/render` | assemble final video (requires every scene render) |
| GET | `/api/scenes/{id}` | scene detail |
| PATCH | `/api/scenes/{id}` | edit prompts (atomic) |
| DELETE | `/api/scenes/{id}` | delete scene |
| POST | `/api/scenes/{id}/generate` | `{component, force}` → submit to provider |
| POST | `/api/scenes/{id}/render` | FFmpeg scene render task |
| GET | `/api/scenes/{id}/assets/{component}` | serve generated asset |
| POST | `/api/webhooks/{provider}` | signed provider callback |
| GET | `/api/media/generated/{name}` | public generated artifact (for providers) |

### Platform interface (`vidx/services/social/`)

`SocialPlatformAdapter` (capabilities + validate_post + publish) with the
LinkedIn adapter implemented (`/rest/posts`, image upload, comment
composition of hashtags/links). Facebook, Instagram, Threads, X, TikTok and
YouTube are registered as planned capability descriptors; adding one means
implementing the adapter and registering it — no route/service changes.
Credentials come from `VIDX_LINKEDIN_*` environment variables.

### Scheduling / publishing

- Posts store local date/time + IANA timezone; `scheduled_at_utc` is
  normalized with the tz database (DST-safe).
- Celery beat runs `vidx.tasks.publish_due_social_posts` every 60 s; the
  task claims due posts atomically (stale-claim reclaim), publishes through
  the platform adapter and records Published/Failed + error + provider id.
- `POST /api/social/scheduler/run` exposes the same logic for cron.

### Generation pipeline (`vidx/services/providers`, `vidx/services/generation`)

External provider contract:
`Input → Submit Job → Provider Job ID → Processing → Webhook → Store Result
→ Continue Pipeline`.

- `AIProvider` interface: `submit_job(request)` (endpoint, credentials,
  model, parameters supplied externally) and `parse_webhook(payload)`.
- `HTTPAIProvider` — generic external HTTP API adapter.
- `SimulatedProvider` — transport stand-in for offline/dev verification
  (no model inference; artifacts are produced with FFmpeg, callbacks are
  real signed HTTP webhooks). Production sets `VIDX_AI_PROVIDER_MODE=http`
  and the per-component endpoints/models/keys.
- `GenerationOrchestrator` enforces gating (video requires a completed
  image; subtitles can use the generated audio), records correlation ids,
  and on callback validates the HMAC signature, correlates by provider +
  job id + correlation id, stores the artifact via the StorageService,
  marks Completed/Failed and derives the scene overall status. Duplicate
  callbacks are idempotent.

### FFmpeg rendering (`vidx/services/render/`)

`RenderService` reuses the configured FFmpeg binary for:
- scene render: scale/pad, logo overlay (project image), subtitle burn-in,
  audio mux (silent track added when absent);
- final assembly: normalized concat of all rendered scenes.

Celery tasks `vidx.tasks.render_scene` and
`vidx.tasks.assemble_project_video` run these and persist atomically.

## Running tests

```powershell
cd backend
uv run pytest            # in-memory MongoDB (mongomock-motor); FFmpeg tests skip when absent
uv run ruff check vidx
```

## Deployment (Render)

`render.yaml` (repo root) describes the deployment. Render has no managed
MongoDB/RabbitMQ, so the backend container runs embedded MongoDB + Redis and
the Celery worker/beat via `render-entrypoint.sh`
(`VIDX_EMBEDDED_MONGO`, `VIDX_EMBEDDED_REDIS`, `VIDX_RUN_WORKER`,
`QUEUE_TYPE=redis`). For production, point `VIDX_DB_*` at MongoDB Atlas and
`RABBITMQ_*`/`REDIS_*` at managed services and disable the embedded flags.
