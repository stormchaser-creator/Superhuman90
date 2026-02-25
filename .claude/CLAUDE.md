# Superhuman90 — Project Instructions

## What This Is

A 90-day fitness and habit tracking Progressive Web App. Single HTML file with embedded React, deployed on Netlify. No build process — just open the file or deploy.

## Architecture

- **Single file:** `index.html` (~184KB, fully self-contained)
- **React 18.2.0** loaded from unpkg CDN
- **Babel Standalone** for in-browser JSX compilation
- **Styling:** Inline CSS-in-JS (no framework)
- **Storage:** localStorage with `sh90_` key prefix
- **Hosting:** Netlify

## Features

- 12-week structured workout program (6 workout types across Legs/Torso/Arms)
- 100+ exercise database with alternatives and substitutions
- Progressive tracking: sets, reps, weight, notes per session
- 8 daily habits (Reading, No ASPM, 10K Steps, Workout, Track Weight, Track Food, Deep Work, Reflection)
- Weight tracking with chart visualization
- User profile (name, age, height, goal weight)
- 5 color themes (Midnight, Obsidian, Forest, Arctic, Ember)
- PWA — installable on mobile, works offline

## Key Commands

```bash
# Deploy to Netlify
netlify deploy --prod

# Local development — just open the file
open index.html
```

## Conventions

- Everything lives in `index.html` — no separate files
- Exercise data is embedded as JavaScript objects
- Theme colors use CSS custom properties
- All state persists via localStorage
