# What this image is

A self-contained Docker image for [Taiga](https://taiga.io) (Kaleidos taiga 6.x), the open-source agile project management platform. The image bundles the complete application in a single Alpine Linux container behind one nginx gateway on port 80: taiga-front (prebuilt static files), taiga-back (Django API under gunicorn), taiga-async (celery worker with the embedded beat scheduler), taiga-events (node websocket server) and taiga-protected (signed media service). PostgreSQL and RabbitMQ are the only external dependencies; they are supplied by the compose stack (`composemgr` taiga stack) and configured through environment variables.

# How this image is built and wired

## Base image and tooling

Built from `casjaysdev/alpine:latest` via a multi-stage Dockerfile (build stage -> `FROM scratch` final). `tini` is PID 1; `gosu` drops privileges. Python 3.11, the version taiga-back and taiga-protected are built and tested against, is not packaged by Alpine, so the musl build is copied from the official `python:3.11-alpine` image in a throwaway stage (the same pattern as the `tianon/gosu` stage); nothing else is taken from non-casjaysdev images.

## Pinned upstream inputs (Dockerfile build ARGs)

| ARG | Default | Source |
|-----|---------|--------|
| `TAIGA_BACK_VERSION` | `6.10.2` | github.com/taigaio/taiga-back tag |
| `TAIGA_FRONT_VERSION` | `6.10.3` | github.com/taigaio/taiga-front-dist tag (prebuilt dist of taiga-front) |
| `TAIGA_EVENTS_VERSION` | `6.10.0` | github.com/taigaio/taiga-events tag |
| `TAIGA_PROTECTED_VERSION` | `6.10.1` | github.com/taigaio/taiga-protected tag |
| `TAIGA_CONTRIB_VERSION` | `6.10.0` | taiga-contrib-{slack,github-auth,gitlab-auth} front plugins |
| `TAIGA_PYTHON_VERSION` | `3.11` | python:{version}-alpine used as the interpreter source |

The back contribs (`requirements-contribs.txt` in taiga-back) install from the upstream git tags pinned there.

## Build-time setup flow (`rootfs/root/docker/setup/`)

| Script | Role |
|--------|------|
| `00-init.sh`, `01-system.sh`, `02-packages.sh` | Template defaults (02 refreshes the CA bundle) |
| `03-files.sh` | Installs `rootfs/tmp/etc/*` (the nginx gateway config) into `/etc/*` |
| `04-users.sh` | Creates the `taiga` system user/group (uid/gid 1000) |
| `05-custom.sh` | **Core setup**: adds temporary build packages, unpacks and installs taiga-back into `/usr/local/share/taiga/taiga-back` (venv `/opt/taiga/venv-back`, compilemessages, collectstatic), taiga-protected (venv `/opt/taiga/venv-protected`), taiga-events (`npm ci --omit=dev`), taiga-front (dist plus contrib plugins), removes the stock nginx site and the build packages |
| `06-post.sh`, `07-cleanup.sh` | Template defaults |

## Runtime

`rootfs/usr/local/etc/docker/env/taiga.sh` is sourced by the entrypoint, every init.d script and every service wrapper. It derives the whole runtime environment (database, rabbitmq urls, site url, email, feature flags, secret key) from the container environment, so no secret is stored in the image. The secret key, when not supplied, is generated once and persisted in `/config/taiga/secret_key`.

Service wrappers in `rootfs/usr/local/etc/docker/bin/`: `taiga-back`, `taiga-async`, `taiga-events`, `taiga-protected` (each `exec`s the real daemon) and `taiga-migrate` (waits for PostgreSQL and RabbitMQ, runs `migrate` and `loaddata initial_project_templates`, optionally creates the first administrator).

### init.d scripts (start order)

| Script | Service | Notes |
|--------|---------|-------|
| `05-taiga-front.sh` | taiga-front | Configuration service (`SERVICE_USES_PID=no`); writes `conf.json` and the `<base href>` of the front from the environment, or uses `/config/taiga-front/conf.json` when present |
| `10-taiga-back.sh` | taiga-back | `taiga` user; `__pre_execute` runs `taiga-migrate` (a failure stops the container); gunicorn on 127.0.0.1:8000 |
| `20-taiga-async.sh` | taiga-async | `taiga` user; celery worker `-B`, schedule file in `/data/taiga` |
| `30-taiga-events.sh` | taiga-events | `taiga` user; websocket on 8888, liveness `/healthz` on 3023 |
| `40-taiga-protected.sh` | taiga-protected | `taiga` user; gunicorn on 127.0.0.1:8003 |
| `99-nginx.sh` | gateway | root master, `nginx` workers; `nginx -t` pre-check; port 80 |

Gateway routing (`rootfs/tmp/etc/nginx/conf.d/taiga.conf`), identical to the upstream taiga-gateway: `/` front (SPA fallback), `/api/` and `/admin/` back, `/static/` collected static, `/media/exports/` unprotected exports, `/media/` taiga-protected, `/_protected/` internal media alias, `/events` websocket upgrade.

### Health

`entrypoint.sh healthcheck` checks the `tini nginx taiga-back taiga-async taiga-events taiga-protected` processes, `http://127.0.0.1/_health` (nginx) and `http://127.0.0.1:3023/healthz` (events).

## Exposed port, volumes

- Port `80` (nginx gateway). Everything else binds to loopback or stays internal.
- Volumes `/config` and `/data`; media lives in `/data/taiga/media`.

## Deviations and exceptions

- The final Dockerfile has an extra build stage `FROM python:3.11-alpine AS python` only as a COPY source for the interpreter (Alpine has no python 3.11 package). The runtime still derives from `casjaysdev/alpine`.
- nginx runs its master process as root (workers as `nginx`) so the pid, log and temp paths work without extra capabilities; all Taiga daemons run as the unprivileged `taiga` user.
- Telemetry (`ENABLE_TELEMETRY`) defaults to `false` (opt-in), unlike the upstream default.
- Secure cookies default to on only when `TAIGA_SITES_SCHEME=https`.
