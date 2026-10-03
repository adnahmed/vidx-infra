# vidx frontend map

React 18 single-page app (Create React App + CRACO, `wouter` routing,
Tailwind) for the video editor and the Social Media module.

## Structure

- `src/App.tsx` — routes: `/`, `/login`, `/signup`, 404 fallback.
- `src/Main.tsx` — localStorage session gate → `Dashboard` or `LandingPage`.
- `src/components/Dashboard.tsx` — sidebar tabs: **Video Studio**
  (existing transition editor), **Transcripts**, **Social Media**.
- `src/lib/api.ts` — `API_BASE_URL`: dev `http://localhost:8000/api`,
  production `REACT_APP_API_URL` (Render static site sets it to
  `https://<backend>.onrender.com/api`).
- `src/lib/auth.ts` — localStorage session + `buildAuthHeaders()`.
- `src/lib/projectsApi.ts` — typed client for projects, posts, scenes,
  platform capabilities and authenticated media. Clears the session and
  redirects to `/login` on 401.

## Social Media tab

- `src/components/social/SocialMediaTab.tsx` — project list, create-project
  modal (type selector, name, description, platform, dates with
  end ≥ start validation, timezone, image/logo upload) and project routing.
- `src/components/social/CampaignProjectView.tsx` — month calendar across
  the project range, per-day post counts, day modal listing posts
  (content, image, time, link, hashtags, status) with publish/edit/delete,
  and the add/edit post form (platform character-limit counter, date range
  validation, timezone-aware time, optional image with project-image
  fallback, Draft/Scheduled/Published/Failed).
- `src/components/social/VideoProductionView.tsx` — Excel import panel,
  scene cards with editable Image/Scene/Audio prompts, per-component
  Generate/Regenerate actions (video gated on a completed image), asset
  previews (image/video/SRT download), scene render and final-video
  assembly, with 3-second polling while work is active.
- `src/components/social/AuthedMedia.tsx` — object-URL loaders for
  authenticated images/videos plus status badges.

## Existing editor

The Video Studio tab (VideoUploader → TransitionGallery → AudioUploader →
merge submit + status polling) is unchanged; the Social Media tab is
additive.

## Local development

```powershell
cd frontend
yarn start     # http://localhost:3000
yarn build     # production bundle
```
