# Deploy admin panel to GitHub Pages (no problems checklist)

Your admin UI lives in `admin-panel/`. The phone app and Flask code stay in the same repo, but **only this folder** is published as the website.

## 1. Turn on GitHub Pages (Actions)

1. Open https://github.com/vibesubmanager-cloud/vibei
2. **Settings** → **Pages**
3. Under **Build and deployment** → **Source**, choose **GitHub Actions**
4. Save

## 2. Deploy

This repo already has `.github/workflows/deploy-admin-pages.yml`.

- Push to `main`, **or**
- **Actions** → **Deploy Admin Panel** → **Run workflow**

Wait until the workflow is green.

## 3. Open the site

URL will be:

`https://vibesubmanager-cloud.github.io/vibei/`

## 4. Connect it to Render

On the login screen, set **API base URL** to your Render service, for example:

`https://vibei.onrender.com`

(no trailing slash)

On Render, set:

`ADMIN_CORS_ORIGINS=https://vibesubmanager-cloud.github.io`

Then redeploy / restart the web service so CORS updates.

## 5. Create the first admin (once)

With the backend live:

```bash
curl -X POST https://YOUR-RENDER-URL/bootstrap/admin ^
  -H "Content-Type: application/json" ^
  -H "X-Bootstrap-Token: YOUR_ADMIN_BOOTSTRAP_TOKEN" ^
  -d "{\"email\":\"admin@example.com\",\"password\":\"ChangeMeNow1!\",\"token\":\"YOUR_ADMIN_BOOTSTRAP_TOKEN\"}"
```

Then sign in on the GitHub Pages admin site with that email/password.

## Common mistakes to avoid

| Mistake | Fix |
|---|---|
| Pages Source = “Deploy from a branch” with `/` | Use **GitHub Actions** instead |
| Root Directory confusion | Pages uses `admin-panel/` via the workflow; do not put `backend` here |
| CORS errors in browser | Set `ADMIN_CORS_ORIGINS` on Render to the Pages origin |
| Wrong API URL | Use `https://….onrender.com` with **https**, no `/admin` path |
