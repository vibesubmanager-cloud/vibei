# VIBEI / PathFinder Backend (Flask → Render)

This is the **API + database** piece only.

| Piece | Folder | Host |
|---|---|---|
| Phone app | `apps/oriente_app` | Android device |
| **This backend** | `backend/` | **Render** |
| Admin UI (HTML/CSS/JS) | `admin-panel/` | **GitHub Pages** |

See root `ARCHITECTURE.md` for the full picture.

### Admin JSON API (for GitHub Pages)

- `POST /api/v1/admin/login` → admin JWT
- `GET /api/v1/admin/dashboard`
- `GET /api/v1/admin/users`
- `GET /api/v1/admin/activities`
- `GET /api/v1/admin/usage`
- `POST /api/v1/events` (phone reports offline feature usage)

Set `ADMIN_CORS_ORIGINS` to your GitHub Pages origin.

The old Jinja `/admin` UI still works if you open it on the Render URL.

## Local

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate   # Windows
pip install -r requirements.txt
set SECRET_KEY=dev
set MASTER_ENCRYPTION_KEY=dev-master
set ADMIN_BOOTSTRAP_TOKEN=bootstrap-secret
set DATABASE_URL=sqlite:///vibei_local.db
flask --app wsgi db upgrade
flask --app wsgi run
```

Bootstrap first admin:

```bash
curl -X POST http://127.0.0.1:5000/bootstrap/admin ^
  -H "Content-Type: application/json" ^
  -H "X-Bootstrap-Token: bootstrap-secret" ^
  -d "{\"email\":\"admin@example.com\",\"password\":\"ChangeMeNow1\",\"token\":\"bootstrap-secret\"}"
```

Then open `/admin`, sign in, set AI provider + key + model, optional Cloudinary.

## Render + Neon

1. Create a Neon PostgreSQL database; copy `DATABASE_URL` (SSL).
2. Create a Render Web Service from this `backend/` folder using `render.yaml`, or manually set start command:
   `flask --app wsgi db upgrade && gunicorn -c gunicorn.conf.py wsgi:app`
3. Set env vars: `DATABASE_URL`, `SECRET_KEY`, `MASTER_ENCRYPTION_KEY`, `ADMIN_BOOTSTRAP_TOKEN`.
4. Deploy, hit `/healthz`.
5. Call `/bootstrap/admin` once with the bootstrap token.
6. Open `https://YOUR-SERVICE.onrender.com/admin` and enter AI + Cloudinary secrets.
7. Set Flutter `--dart-define=VIBEI_API_BASE=https://YOUR-SERVICE.onrender.com`
