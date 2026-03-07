# Superhuman90 — Session Orientation

**What:** 90-day fitness PWA. Tracks workouts (gym or home mode), habits, weight, steps. Device-based auth (no login required). Single-file HTML app.

**Stack:** Single `index.html` (222KB, all-in-one), Supabase backend, deployed on GitHub Pages. Uses DM Sans / DM Mono fonts. PWA with service worker and manifest.

**Status:** Deployed and working. Bug fixes applied (day advancement + rest button).

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
