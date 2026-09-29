# Production deploy on VPS (185.252.233.171)

## What changed vs development

Development `docker-compose.yml` bind-mounts `.:/usr/src/app`. That makes the
container user (`docker`, uid 9999) try to write `Gemfile.lock` on the host and
fails with:

```
Bundler::PermissionError ... /usr/src/app/Gemfile.lock (Errno::EACCES)
```

Production **does not mount source**. The app is baked into `Dockerfile.vps`.

| File | Role |
|------|------|
| `docker-compose.production.yml` | web, jobs, postgres, redis |
| `Dockerfile.vps` | production image (bundle + assets) |
| `deploy/config/*` | tracked YAML (because `/config/*.yml` is gitignored) |
| `.env.production` | secrets (gitignored) |

## On the VPS

```bash
# 1) Clone / sync this repo to the VPS
git clone <your-repo> canvas-lms && cd canvas-lms

# 2) Install Docker Engine + Compose plugin if needed

# 3) Copy env file (or let the script generate one)
cp .env.production.example .env.production
# edit secrets, or copy your local .env.production securely

# 4) Deploy
bash script/deploy_production.sh
```

Open: http://185.252.233.171

Admin is created from `CANVAS_LMS_ADMIN_EMAIL` / `CANVAS_LMS_ADMIN_PASSWORD` in `.env.production`.

## After first boot

- Open firewall port **80** (and 443 when you add TLS).
- Do **not** expose Postgres/Redis publicly (compose only `expose`s them).
- When you have a domain + TLS reverse proxy, set `ssl: true` in
  `config/domain.yml`, remove or adjust `production-local.rb`, rebuild.

## Logs / restart

```bash
docker compose -f docker-compose.production.yml --env-file .env.production logs -f web jobs
docker compose -f docker-compose.production.yml --env-file .env.production restart web jobs
```
