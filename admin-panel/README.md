# PathFinder Admin Panel (GitHub Pages)

Static **HTML / CSS / JavaScript** dashboard. It does **not** run Flask.

It calls your Render backend:

- `POST /api/v1/admin/login`
- `GET  /api/v1/admin/dashboard`
- `GET  /api/v1/admin/users`
- `GET  /api/v1/admin/activities`
- `GET  /api/v1/admin/usage`

## Local

```bash
cd admin-panel
python -m http.server 5500
```

Open `http://127.0.0.1:5500`, set API base to `http://127.0.0.1:5000`.

## GitHub Pages

1. Publish this folder as a Pages site.
2. On Render set:
   `ADMIN_CORS_ORIGINS=https://<your-user>.github.io`
3. On the login form, enter your Render URL.

## What you see

- Every registered app user
- Last login / last seen
- AI request counts per user
- Object detection / scene description activity
- Live activity feed
