# PathFinder / VIBEI — System Structure

This project has **three separate parts**. They talk over HTTPS. Offline phone
features (object search, scene description, OCR) still work **without** the
backend; the backend is for accounts, optional cloud AI, and the admin panel.

```
┌─────────────────────┐         HTTPS          ┌──────────────────────────┐
│  PHONE APP          │ ─────────────────────► │  BACKEND (Flask)         │
│  Flutter / Android  │   /api/v1/*            │  Deploy on RENDER        │
│  apps/oriente_app   │                        │  backend/                │
└─────────────────────┘                        └────────────▲─────────────┘
                                                            │
                                                            │ HTTPS /api/v1/admin/*
                                                            │
                                               ┌────────────┴─────────────┐
                                               │  ADMIN PANEL             │
                                               │  HTML + CSS + JavaScript │
                                               │  Deploy on GITHUB PAGES  │
                                               │  admin-panel/            │
                                               └──────────────────────────┘
```

## 1. Phone app (`apps/oriente_app`)

- Runs on the user’s Android phone.
- **Offline core:** camera, object detection, OCR, scene description, speech.
- **Online (optional):** sign-in, sync, cloud describe/read when configured with
  `--dart-define=VIBEI_API_BASE=https://YOUR-RENDER-URL`.
- Reports usage to the backend via `POST /api/v1/events` (object search, scene
  description, etc.) when the user is signed in.

## 2. Backend (`backend/`) — Render

- **Flask + SQLAlchemy + PostgreSQL (Neon) or SQLite locally.**
- Serves the mobile JSON API under `/api/v1/...`.
- Serves the **admin JSON API** under `/api/v1/admin/...` for the GitHub Pages UI.
- Still has an optional server-rendered `/admin` (Jinja) for emergency use.
- Tracks:
  - Users (signup, login, last seen)
  - Activities (object detection, scene description, text search, …)
  - AI / API usage (describe, read, voice)
- Start: see `backend/README.md` and `backend/render.yaml`.

## 3. Admin panel (`admin-panel/`) — GitHub Pages

- Pure **HTML / CSS / JavaScript** (no React/Vue build).
- Hosted on **GitHub Pages** (or any static host).
- You type your Render API URL on the login screen.
- After admin login you can see:
  - All users
  - Sign-ins / last seen
  - Activity feed
  - How many AI requests each user made
  - Object-detection / scene-description counts

### Deploy admin panel to GitHub Pages

1. Create a GitHub repo (or use this monorepo).
2. Push the `admin-panel/` folder (as repo root, or enable Pages on `/admin-panel`).
3. Settings → Pages → Deploy from branch `/` (or `/docs` / `/admin-panel`).
4. On Render, set env `ADMIN_CORS_ORIGINS=https://YOURUSER.github.io`.
5. Open the Pages URL, paste `https://YOUR-SERVICE.onrender.com`, sign in.

## Data flow examples

| What happens | Where it runs | What admin sees |
|---|---|---|
| User says “find a bottle” | Phone detector (offline) | Activity `object_search` if event posted |
| User says “what is in front of me?” | Phone DESCRIBE_MODE → Gemini (online) | Activity `ai_describe` if event posted |
| User says “read this paper” | Phone READ_MODE → Gemini (online) | Activity `ai_read` if event posted |
| User says “find a bottle” | Phone OBJECT_SEARCH (offline detector) | Offline only |
| User says “find the word Exit” | Phone TEXT_SEARCH (offline OCR) | Offline only |
| User uses online describe | Render AI provider | Usage `describe` + activity `ai_describe` |
| User signs up / logs in | Render auth | Users list + `auth` activity |

## Local development

```bash
# Backend
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
set DATABASE_URL=sqlite:///vibei_local.db
set SECRET_KEY=dev
set MASTER_ENCRYPTION_KEY=dev-master
set ADMIN_BOOTSTRAP_TOKEN=bootstrap-secret
flask --app wsgi db upgrade
flask --app wsgi run

# Admin panel (any static server)
cd admin-panel
# e.g. VS Code Live Server, or:
python -m http.server 5500
# Open http://127.0.0.1:5500 — API base http://127.0.0.1:5000
```

Bootstrap admin once (see `backend/README.md`), then log into the admin panel.
