## 👋 Welcome to taiga 🚀

taiga README

An all-in-one [Taiga](https://taiga.io) (Kaleidos taiga 6.x) image. One container serves the complete
application behind a single nginx gateway on port **80**; the only external services needed are
**PostgreSQL** and **RabbitMQ**. Use RabbitMQ 3.x: 4.x rejects the transient queues that Taiga events
and Celery declare, so the workers cannot connect.

| Service | Upstream | Listens on | Started by |
|---------|----------|------------|------------|
| taiga-front | taiga-front-dist (static files) | served by nginx | `05-taiga-front.sh` (writes `conf.json`) |
| taiga-back | taiga-back (Django, gunicorn WSGI) | 127.0.0.1:8000 | `10-taiga-back.sh` (runs migrations first) |
| taiga-async | taiga-back (celery worker + beat) | - | `20-taiga-async.sh` |
| taiga-events | taiga-events (node websocket) | 8888 (liveness 3023) | `30-taiga-events.sh` |
| taiga-protected | taiga-protected (signed media) | 127.0.0.1:8003 | `40-taiga-protected.sh` |
| gateway | nginx | **80** | `99-nginx.sh` |

Gateway routing (same as the upstream `taiga-gateway`): `/` front, `/api/` and `/admin/` back,
`/static/` collected static files, `/media/` protected (signed urls, served through
`/_protected/`), `/events` events websocket.

Pinned upstream releases (build args): taiga-back `6.10.2`, taiga-front `6.10.3`,
taiga-events `6.10.0`, taiga-protected `6.10.1`, front contrib plugins `6.10.0`.

## Install my system scripts

```shell
 sudo bash -c "$(curl -q -LSsf "https://github.com/systemmgr/installer/raw/main/install.sh")"
 sudo systemmgr --config && sudo systemmgr install scripts
```

## Automatic install/update

```shell
dockermgr update taiga
```

## Install and run container

```shell
dockerHome="/srv/$USER/docker/casjaysdevdocker/taiga/latest/volumes"
mkdir -p "$dockerHome"
git clone "https://github.com/dockermgr/taiga" "$HOME/.local/share/CasjaysDev/dockermgr/taiga"
cp -Rfva "$HOME/.local/share/CasjaysDev/dockermgr/taiga/volumes/." "$dockerHome/"
docker run -d \
--restart always \
--name casjaysdevdocker-taiga-latest \
--hostname taiga \
-e TZ=${TIMEZONE:-America/New_York} \
-e TAIGA_SITES_DOMAIN=localhost:9000 \
-e POSTGRES_HOST=postgres \
-e POSTGRES_USER=taiga \
-e POSTGRES_PASSWORD=change-me \
-e RABBITMQ_HOST=rabbitmq \
-e RABBITMQ_USER=taiga \
-e RABBITMQ_PASS=change-me \
-v "$dockerHome/data:/data:z" \
-v "$dockerHome/config:/config:z" \
-p 9000:80 \
casjaysdevdocker/taiga:latest
```

## via docker-compose

```yaml
services:
  taiga:
    image: casjaysdevdocker/taiga
    container_name: casjaysdevdocker-taiga
    environment:
      - TZ=America/New_York
      - HOSTNAME=taiga
      - TAIGA_SITES_SCHEME=http
      - TAIGA_SITES_DOMAIN=localhost:9000
      - POSTGRES_HOST=taiga-db
      - POSTGRES_DB=taiga
      - POSTGRES_USER=taiga
      - POSTGRES_PASSWORD=change-me
      - RABBITMQ_HOST=taiga-rabbitmq
      - RABBITMQ_USER=taiga
      - RABBITMQ_PASS=change-me
      - RABBITMQ_VHOST=taiga
      # optional: create the first administrator on start
      - TAIGA_ADMIN_USERNAME=admin
      - TAIGA_ADMIN_PASSWORD=change-me-too
    volumes:
      - "/srv/$USER/docker/casjaysdevdocker/taiga/latest/volumes/data:/data:z"
      - "/srv/$USER/docker/casjaysdevdocker/taiga/latest/volumes/config:/config:z"
    ports:
      - 9000:80
    depends_on:
      taiga-db:
        condition: service_healthy
      taiga-rabbitmq:
        condition: service_started
    restart: always

  taiga-db:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=taiga
      - POSTGRES_USER=taiga
      - POSTGRES_PASSWORD=change-me
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U taiga"]
      interval: 5s
      timeout: 15s
      retries: 10
    volumes:
      - "/srv/$USER/docker/casjaysdevdocker/taiga/latest/volumes/db:/var/lib/postgresql/data:z"
    restart: always

  taiga-rabbitmq:
    image: rabbitmq:3-management-alpine
    hostname: taiga-rabbitmq
    environment:
      - RABBITMQ_DEFAULT_USER=taiga
      - RABBITMQ_DEFAULT_PASS=change-me
      - RABBITMQ_DEFAULT_VHOST=taiga
    volumes:
      - "/srv/$USER/docker/casjaysdevdocker/taiga/latest/volumes/rabbitmq:/var/lib/rabbitmq:z"
    restart: always
```

Open `http://localhost:9000/`. Taiga 6 ships no default account: set `TAIGA_ADMIN_USERNAME` and
`TAIGA_ADMIN_PASSWORD` (above), or create one by hand:

```shell
docker exec -it casjaysdevdocker-taiga bash -c '. /usr/local/etc/docker/env/taiga.sh && cd "$TAIGA_ROOT/taiga-back" && exec gosu taiga "$TAIGA_VENV/venv-back/bin/python" manage.py createsuperuser'
```

## First start

Migrations (`manage.py migrate`) and the initial data (`loaddata initial_project_templates`) run
automatically before taiga-back and taiga-async start. The container waits (default 180 s) for
PostgreSQL and RabbitMQ, so start order does not matter. The RabbitMQ vhost must exist
(`RABBITMQ_DEFAULT_VHOST=taiga` on the rabbitmq image).

## Environment variables

Nothing secret is baked into the image; all runtime configuration is generated at start from these.

### Required

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_PASSWORD` | | PostgreSQL password |
| `RABBITMQ_PASS` | | RabbitMQ password (alias `RABBITMQ_PASSWORD`) |

### Site

| Variable | Default | Description |
|----------|---------|-------------|
| `TAIGA_SITES_SCHEME` | `http` | Public scheme, `http` or `https` (alias `TAIGA_SCHEME`) |
| `TAIGA_SITES_DOMAIN` | `localhost` | Public host, include `:port` when not 80/443 (alias `TAIGA_DOMAIN`) |
| `TAIGA_SUBPATH` | | Serve under a subpath such as `/taiga` (alias `SUBPATH`); the outer proxy must strip the prefix |
| `TAIGA_WEBSOCKETS_SCHEME` | `ws` / `wss` | Follows the scheme (alias `WEBSOCKETS_SCHEME`) |
| `TAIGA_SECRET_KEY` | generated | Django/JWT secret (alias `SECRET_KEY`); when unset one is generated once and kept in `/config/taiga/secret_key` |
| `TAIGA_ADMIN_USERNAME` | `admin` | First administrator, only used with `TAIGA_ADMIN_PASSWORD` |
| `TAIGA_ADMIN_EMAIL` | `admin@<domain>` | First administrator email |
| `TAIGA_ADMIN_PASSWORD` | | When set, the administrator is created on start if it does not exist |

### PostgreSQL

| Variable | Default |
|----------|---------|
| `POSTGRES_HOST` | `postgres` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB` | `taiga` |
| `POSTGRES_USER` | `taiga` |
| `POSTGRES_SSLMODE` | `disable` |

### RabbitMQ

One broker serves both the events backend and the celery broker.

| Variable | Default |
|----------|---------|
| `RABBITMQ_HOST` | `rabbitmq` |
| `RABBITMQ_PORT` | `5672` |
| `RABBITMQ_USER` | `taiga` |
| `RABBITMQ_VHOST` | `taiga` |
| `EVENTS_PUSH_BACKEND_URL` | built from the values above |
| `CELERY_BROKER_URL` | built from the values above |

### Email

| Variable | Default | Description |
|----------|---------|-------------|
| `EMAIL_BACKEND` | `console` | `console`, `smtp`, ... or a full django backend path |
| `DEFAULT_FROM_EMAIL` | `system@taiga.io` | Sender (alias `EMAIL_DEFAULT_FROM`) |
| `EMAIL_HOST` | `localhost` | SMTP host |
| `EMAIL_PORT` | `587` | SMTP port |
| `EMAIL_HOST_USER` | `user` | SMTP user |
| `EMAIL_HOST_PASSWORD` | `password` | SMTP password |
| `EMAIL_USE_TLS` | `false` | STARTTLS |
| `EMAIL_USE_SSL` | `false` | SMTPS |

### Features

| Variable | Default | Description |
|----------|---------|-------------|
| `ATTACHMENTS_MAX_AGE` | `360` | Lifetime in seconds of signed attachment urls (taiga-protected `MAX_AGE`) |
| `PUBLIC_REGISTER_ENABLED` | `false` | Allow public sign-up |
| `ENABLE_SLACK` | `false` | Slack contrib |
| `ENABLE_GITHUB_AUTH` | `false` | GitHub login (needs public sign-up); `GITHUB_API_CLIENT_ID`, `GITHUB_API_CLIENT_SECRET` |
| `ENABLE_GITLAB_AUTH` | `false` | GitLab login (needs public sign-up); `GITLAB_API_CLIENT_ID`, `GITLAB_API_CLIENT_SECRET`, `GITLAB_URL` |
| `ENABLE_GITHUB_IMPORTER` | `false` | `GITHUB_IMPORTER_CLIENT_ID`, `GITHUB_IMPORTER_CLIENT_SECRET` |
| `ENABLE_JIRA_IMPORTER` | `false` | `JIRA_IMPORTER_CONSUMER_KEY`, `JIRA_IMPORTER_CERT`, `JIRA_IMPORTER_PUB_CERT` |
| `ENABLE_TRELLO_IMPORTER` | `false` | `TRELLO_IMPORTER_API_KEY`, `TRELLO_IMPORTER_SECRET_KEY` |
| `ENABLE_TELEMETRY` | `false` | Opt-in telemetry |
| `WEBHOOKS_ENABLED` | `true` | Project webhooks |
| `WEBHOOKS_ALLOW_PRIVATE_ADDRESS` | `false` | |
| `WEBHOOKS_ALLOW_REDIRECTS` | `false` | |
| `DEFAULT_PROJECT_SLUG_PREFIX` | `false` | Prefix project slugs with the username |
| `DEFAULT_LANGUAGE` | `en` | Front default language |
| `LANGUAGE_CODE` | `en-us` | Back language |
| `CELERY_TIMEZONE` | `$TZ` | Celery beat timezone |
| `SESSION_COOKIE_SECURE` / `CSRF_COOKIE_SECURE` | `true` with https, else `false` | Secure cookies |
| `DEBUG` | `false` | Debug mode |

### Tuning

| Variable | Default |
|----------|---------|
| `GUNICORN_WORKERS` | `3` |
| `PROTECTED_WORKERS` | `2` |
| `CELERY_CONCURRENCY` | `4` |
| `TAIGA_WAIT_TIMEOUT` | `180` (seconds to wait for PostgreSQL and RabbitMQ) |

Any init script can be turned off with `TAIGA_BACK_ENABLED=no`, `TAIGA_ASYNC_ENABLED=no`,
`TAIGA_EVENTS_ENABLED=no`, `TAIGA_PROTECTED_ENABLED=no`, `TAIGA_FRONT_ENABLED=no` or `NGINX_ENABLED=no`.

## Ports

| Port | Purpose |
|------|---------|
| 80 | nginx gateway (the only published port) |

## Volumes

| Path | Content |
|------|---------|
| `/data` | `/data/taiga/media` uploads and exports, `/data/taiga/celerybeat-schedule`, logs in `/data/logs/` |
| `/config` | `/config/taiga/secret_key`, `/config/nginx/` (gateway config, editable), `/config/env/` (framework env overrides) |

Overrides: put a complete `conf.json` in `/config/taiga-front/` to replace the generated front
configuration, or a `config.py` in `/config/taiga-back/` to replace the back settings.

## Get source files

```shell
dockermgr download src casjaysdevdocker/taiga
```

OR

```shell
git clone "https://github.com/casjaysdevdocker/taiga" "$HOME/Projects/github/casjaysdevdocker/taiga"
```

## Build container

```shell
cd "$HOME/Projects/github/casjaysdevdocker/taiga"
buildx
```

Override the pinned releases with `--build-arg TAIGA_BACK_VERSION=...`, `TAIGA_FRONT_VERSION`,
`TAIGA_EVENTS_VERSION`, `TAIGA_PROTECTED_VERSION`, `TAIGA_CONTRIB_VERSION`.

## Authors

🤖 casjay: [Github](https://github.com/casjay) 🤖
⛵ casjaysdevdocker: [Github](https://github.com/casjaysdevdocker) [Docker](https://hub.docker.com/u/casjaysdevdocker) ⛵
