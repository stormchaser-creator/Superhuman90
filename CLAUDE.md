# Superhuman90 — Session Orientation

**What:** 90-day fitness PWA. Tracks workouts (4 selectable routines: SH90, Omar Monthly, PHAT, Yoga), habits, weight, steps, 90-day rounds. AI coach (Gemini). Device-based auth (no login required). Single-file HTML app.

**Stack:** Single `index.html` (all-in-one, React 18 + Babel standalone), Supabase backend, deployed on Netlify at https://sh90.netlify.app. Uses DM Sans / DM Mono fonts. PWA with service worker and manifest.

**Deploy routine:** push to main → GitHub Actions (`.github/workflows/deploy.yml`) → Netlify. Version bumps must touch THREE places or CI fails / clients reload-loop: `APP_VERSION` in index.html, `version.txt`, `CACHE_VERSION` in sw.js. Clients self-update via SW skip-waiting + version.txt check on launch/resume.

**Tickets:** In-app Support & Tickets card (Me tab) → `support_tickets`/`support_messages` in Supabase. A nightly claude.ai cloud routine ("SH90 Nightly Maintenance", 10:00 UTC) triages open tickets, implements fixes, and pushes (which auto-deploys).

**Status:** v3.1 deployed and working.

## Key Files
- `index.html` — The entire app (single file)
- `supabase-schema.sql` — Database schema (devices, profiles, exercise_logs, sessions, weight_log, habit_log, habit_notes, step_log)
- `sw.js` — Service worker for offline capability
- `manifest.json` — PWA manifest
- `version.txt` — Current version

## Architecture Notes
- Device-based auth: generates UUID per device, no user accounts
- Supabase handles all data persistence
- All UI logic is in the single HTML file — React via CDN
- CSP headers configured in `_headers`
