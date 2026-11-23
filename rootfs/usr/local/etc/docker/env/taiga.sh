# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610102130-git
# @@Author           :  CasjaysDev
# @@Contact          :  CasjaysDev <docker-admin@casjaysdev.pro>
# @@License          :  WTFPL
# @@Copyright        :  Copyright: (c) 2026 CasjaysDev
# @@File             :  taiga.sh
# @@Description      :  derives the complete Taiga runtime environment from the container environment
# @@Terminal App     :  no
# @@sudo/root        :  no
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
# This file is sourced (never executed) by entrypoint.sh, every init.d script and the service wrappers.
# It is idempotent and holds no secrets: anything secret comes from the environment or is generated
# on first start and persisted in /config/taiga (volume).
# - - - - - - - - - - - - - - - - - - - - - - - - -
TAIGA_ROOT="/usr/local/share/taiga"
TAIGA_VENV="/opt/taiga"
TAIGA_STATE_DIR="${TAIGA_STATE_DIR:-/config/taiga}"
TAIGA_DATA_DIR="${TAIGA_DATA_DIR:-/data/taiga}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# lower case true/false -> True/False (django) ; $2 is the default
__taiga_bool_py() {
  local v="${1:-$2}"
  case "${v,,}" in
  true | yes | on | 1) echo "True" ;;
  *) echo "False" ;;
  esac
}
# True/False -> true/false (taiga-front conf.json)
__taiga_bool_js() {
  local v="${1:-$2}"
  case "${v,,}" in
  true | yes | on | 1) echo "true" ;;
  *) echo "false" ;;
  esac
}
# percent-encode a string for use inside a url
__taiga_urlencode() {
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
    [a-zA-Z0-9.~_-]) out+="$c" ;;
    *) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# public url of the site
TAIGA_SITES_SCHEME="${TAIGA_SITES_SCHEME:-${TAIGA_SCHEME:-http}}"
TAIGA_SITES_DOMAIN="${TAIGA_SITES_DOMAIN:-${TAIGA_DOMAIN:-localhost}}"
TAIGA_SUBPATH="${TAIGA_SUBPATH:-${SUBPATH:-}}"
if [ "$TAIGA_SITES_SCHEME" = "https" ]; then
  TAIGA_WEBSOCKETS_SCHEME="${TAIGA_WEBSOCKETS_SCHEME:-${WEBSOCKETS_SCHEME:-wss}}"
else
  TAIGA_WEBSOCKETS_SCHEME="${TAIGA_WEBSOCKETS_SCHEME:-${WEBSOCKETS_SCHEME:-ws}}"
fi
TAIGA_URL="${TAIGA_SITES_SCHEME}://${TAIGA_SITES_DOMAIN}"
TAIGA_WEBSOCKETS_URL="${TAIGA_WEBSOCKETS_SCHEME}://${TAIGA_SITES_DOMAIN}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# secret key: environment first, then the persisted file, otherwise generate once and persist
TAIGA_SECRET_KEY="${TAIGA_SECRET_KEY:-${SECRET_KEY:-}}"
if [ -z "$TAIGA_SECRET_KEY" ]; then
  if [ -s "$TAIGA_STATE_DIR/secret_key" ]; then
    TAIGA_SECRET_KEY="$(<"$TAIGA_STATE_DIR/secret_key")"
  else
    TAIGA_SECRET_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    if mkdir -p "$TAIGA_STATE_DIR" 2>/dev/null; then
      (umask 027 && printf '%s\n' "$TAIGA_SECRET_KEY" >"$TAIGA_STATE_DIR/secret_key") 2>/dev/null || true
      chgrp taiga "$TAIGA_STATE_DIR/secret_key" 2>/dev/null || true
    fi
  fi
fi
SECRET_KEY="$TAIGA_SECRET_KEY"
# taiga-events reads SECRET
SECRET="$TAIGA_SECRET_KEY"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# postgresql
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-taiga}"
POSTGRES_USER="${POSTGRES_USER:-taiga}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_SSLMODE="${POSTGRES_SSLMODE:-disable}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# rabbitmq: one broker serves both the events backend and the celery broker
RABBITMQ_HOST="${RABBITMQ_HOST:-rabbitmq}"
RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"
RABBITMQ_USER="${RABBITMQ_USER:-taiga}"
RABBITMQ_PASS="${RABBITMQ_PASS:-${RABBITMQ_PASSWORD:-}}"
RABBITMQ_VHOST="${RABBITMQ_VHOST:-taiga}"
__taiga_amqp_url="amqp://$(__taiga_urlencode "$RABBITMQ_USER"):$(__taiga_urlencode "$RABBITMQ_PASS")@${RABBITMQ_HOST}:${RABBITMQ_PORT}/$(__taiga_urlencode "$RABBITMQ_VHOST")"
EVENTS_PUSH_BACKEND_URL="${EVENTS_PUSH_BACKEND_URL:-$__taiga_amqp_url}"
CELERY_BROKER_URL="${CELERY_BROKER_URL:-$__taiga_amqp_url}"
RABBITMQ_URL="${RABBITMQ_URL:-$EVENTS_PUSH_BACKEND_URL}"
unset __taiga_amqp_url
# - - - - - - - - - - - - - - - - - - - - - - - - -
# email: EMAIL_BACKEND accepts a short name (smtp, console, ...) or the full django backend path
EMAIL_BACKEND="${EMAIL_BACKEND:-console}"
case "$EMAIL_BACKEND" in
*.*) ;;
*) EMAIL_BACKEND="django.core.mail.backends.${EMAIL_BACKEND}.EmailBackend" ;;
esac
DEFAULT_FROM_EMAIL="${DEFAULT_FROM_EMAIL:-${EMAIL_DEFAULT_FROM:-system@taiga.io}}"
EMAIL_USE_TLS="$(__taiga_bool_py "$EMAIL_USE_TLS" false)"
EMAIL_USE_SSL="$(__taiga_bool_py "$EMAIL_USE_SSL" false)"
EMAIL_HOST="${EMAIL_HOST:-localhost}"
EMAIL_PORT="${EMAIL_PORT:-587}"
EMAIL_HOST_USER="${EMAIL_HOST_USER:-user}"
EMAIL_HOST_PASSWORD="${EMAIL_HOST_PASSWORD:-password}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# behaviour switches (back wants True/False, front wants true/false)
PUBLIC_REGISTER_ENABLED_PY="$(__taiga_bool_py "$PUBLIC_REGISTER_ENABLED" false)"
PUBLIC_REGISTER_ENABLED_JS="$(__taiga_bool_js "$PUBLIC_REGISTER_ENABLED" false)"
DEBUG_PY="$(__taiga_bool_py "$DEBUG" false)"
DEBUG_JS="$(__taiga_bool_js "$DEBUG" false)"
ENABLE_SLACK_PY="$(__taiga_bool_py "$ENABLE_SLACK" false)"
ENABLE_SLACK_JS="$(__taiga_bool_js "$ENABLE_SLACK" false)"
ENABLE_GITHUB_AUTH_PY="$(__taiga_bool_py "$ENABLE_GITHUB_AUTH" false)"
ENABLE_GITHUB_AUTH_JS="$(__taiga_bool_js "$ENABLE_GITHUB_AUTH" false)"
ENABLE_GITLAB_AUTH_PY="$(__taiga_bool_py "$ENABLE_GITLAB_AUTH" false)"
ENABLE_GITLAB_AUTH_JS="$(__taiga_bool_js "$ENABLE_GITLAB_AUTH" false)"
ENABLE_GITHUB_IMPORTER_PY="$(__taiga_bool_py "$ENABLE_GITHUB_IMPORTER" false)"
ENABLE_GITHUB_IMPORTER_JS="$(__taiga_bool_js "$ENABLE_GITHUB_IMPORTER" false)"
ENABLE_JIRA_IMPORTER_PY="$(__taiga_bool_py "$ENABLE_JIRA_IMPORTER" false)"
ENABLE_JIRA_IMPORTER_JS="$(__taiga_bool_js "$ENABLE_JIRA_IMPORTER" false)"
ENABLE_TRELLO_IMPORTER_PY="$(__taiga_bool_py "$ENABLE_TRELLO_IMPORTER" false)"
ENABLE_TRELLO_IMPORTER_JS="$(__taiga_bool_js "$ENABLE_TRELLO_IMPORTER" false)"
WEBHOOKS_ENABLED="$(__taiga_bool_py "$WEBHOOKS_ENABLED" true)"
WEBHOOKS_ALLOW_PRIVATE_ADDRESS="$(__taiga_bool_py "$WEBHOOKS_ALLOW_PRIVATE_ADDRESS" false)"
WEBHOOKS_ALLOW_REDIRECTS="$(__taiga_bool_py "$WEBHOOKS_ALLOW_REDIRECTS" false)"
DEFAULT_PROJECT_SLUG_PREFIX="$(__taiga_bool_py "$DEFAULT_PROJECT_SLUG_PREFIX" false)"
CELERY_ENABLED="$(__taiga_bool_py "$CELERY_ENABLED" true)"
# telemetry is opt-in
ENABLE_TELEMETRY="$(__taiga_bool_py "$ENABLE_TELEMETRY" false)"
# secure cookies only make sense when the site is served over https
if [ "$TAIGA_SITES_SCHEME" = "https" ]; then
  SESSION_COOKIE_SECURE="$(__taiga_bool_py "$SESSION_COOKIE_SECURE" true)"
  CSRF_COOKIE_SECURE="$(__taiga_bool_py "$CSRF_COOKIE_SECURE" true)"
else
  SESSION_COOKIE_SECURE="$(__taiga_bool_py "$SESSION_COOKIE_SECURE" false)"
  CSRF_COOKIE_SECURE="$(__taiga_bool_py "$CSRF_COOKIE_SECURE" false)"
fi
LANGUAGE_CODE="${LANGUAGE_CODE:-en-us}"
DEFAULT_LANGUAGE="${DEFAULT_LANGUAGE:-en}"
CELERY_TIMEZONE="${CELERY_TIMEZONE:-${TZ:-UTC}}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# taiga-protected
MAX_AGE="${ATTACHMENTS_MAX_AGE:-${MAX_AGE:-360}}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# internal listeners - fixed, because the nginx gateway config points at them; everything except nginx binds to loopback only
TAIGA_BACK_PORT="8000"
TAIGA_PROTECTED_PORT="8003"
TAIGA_EVENTS_PORT="8888"
TAIGA_EVENTS_HEALTH_PORT="3023"
GUNICORN_WORKERS="${GUNICORN_WORKERS:-3}"
PROTECTED_WORKERS="${PROTECTED_WORKERS:-2}"
CELERY_CONCURRENCY="${CELERY_CONCURRENCY:-4}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# how long (seconds) to wait for postgres and rabbitmq at start
TAIGA_WAIT_TIMEOUT="${TAIGA_WAIT_TIMEOUT:-180}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
DJANGO_SETTINGS_MODULE="settings.config"
PYTHONUNBUFFERED="1"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# names the back config.py reads
export TAIGA_ROOT TAIGA_VENV TAIGA_STATE_DIR TAIGA_DATA_DIR
export TAIGA_SITES_SCHEME TAIGA_SITES_DOMAIN TAIGA_SUBPATH TAIGA_WEBSOCKETS_SCHEME TAIGA_URL TAIGA_WEBSOCKETS_URL
export TAIGA_SECRET_KEY SECRET_KEY SECRET
export POSTGRES_HOST POSTGRES_PORT POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD POSTGRES_SSLMODE
export RABBITMQ_HOST RABBITMQ_PORT RABBITMQ_USER RABBITMQ_PASS RABBITMQ_VHOST
export EVENTS_PUSH_BACKEND_URL CELERY_BROKER_URL RABBITMQ_URL
export EMAIL_BACKEND DEFAULT_FROM_EMAIL EMAIL_USE_TLS EMAIL_USE_SSL EMAIL_HOST EMAIL_PORT EMAIL_HOST_USER EMAIL_HOST_PASSWORD
export WEBHOOKS_ENABLED WEBHOOKS_ALLOW_PRIVATE_ADDRESS WEBHOOKS_ALLOW_REDIRECTS DEFAULT_PROJECT_SLUG_PREFIX CELERY_ENABLED
export ENABLE_TELEMETRY SESSION_COOKIE_SECURE CSRF_COOKIE_SECURE LANGUAGE_CODE CELERY_TIMEZONE MAX_AGE
export TAIGA_BACK_PORT TAIGA_PROTECTED_PORT TAIGA_EVENTS_PORT TAIGA_EVENTS_HEALTH_PORT
export GUNICORN_WORKERS PROTECTED_WORKERS CELERY_CONCURRENCY TAIGA_WAIT_TIMEOUT DJANGO_SETTINGS_MODULE PYTHONUNBUFFERED
# the back config.py expects True/False for these, so hand it the converted values under the real names
export PUBLIC_REGISTER_ENABLED="$PUBLIC_REGISTER_ENABLED_PY" DEBUG="$DEBUG_PY"
export ENABLE_SLACK="$ENABLE_SLACK_PY" ENABLE_GITHUB_AUTH="$ENABLE_GITHUB_AUTH_PY" ENABLE_GITLAB_AUTH="$ENABLE_GITLAB_AUTH_PY"
export ENABLE_GITHUB_IMPORTER="$ENABLE_GITHUB_IMPORTER_PY" ENABLE_JIRA_IMPORTER="$ENABLE_JIRA_IMPORTER_PY" ENABLE_TRELLO_IMPORTER="$ENABLE_TRELLO_IMPORTER_PY"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# block until host:port accepts connections: __taiga_wait_for host port label
__taiga_wait_for() {
  local host="$1" port="$2" label="$3" waited=0
  while [ "$waited" -lt "$TAIGA_WAIT_TIMEOUT" ]; do
    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
      echo "$label is reachable at $host:$port"
      return 0
    fi
    [ "$waited" -eq 0 ] && echo "Waiting for $label at $host:$port (up to ${TAIGA_WAIT_TIMEOUT}s)"
    sleep 2
    waited=$((waited + 2))
  done
  echo "Timed out waiting for $label at $host:$port" >&2
  return 1
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
