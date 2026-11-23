#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610102115-git
# @@Author           :  CasjaysDev
# @@Contact          :  CasjaysDev <docker-admin@casjaysdev.pro>
# @@License          :  WTFPL
# @@Copyright        :  Copyright 2026 CasjaysDev
# @@Created          :  Sat Oct 10 09:15:02 PM EDT 2026
# @@File             :  05-custom.sh
# @@Description      :  script to run custom
# @@Changelog        :  newScript
# @@TODO             :  Refactor code
# @@Other            :  N/A
# @@Resource         :  N/A
# @@Terminal App     :  yes
# @@sudo/root        :  yes
# @@Template         :  templates/dockerfiles/init_scripts/05-custom.sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set bash options
set -eo pipefail
if [ "$DEBUGGER" = "on" ]; then
  echo "Enabling debugging"
  set -x$DEBUGGER_OPTIONS
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set env variables
exitCode=0

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Predefined actions

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Main script
TAIGA_ROOT="/usr/local/share/taiga"
TAIGA_VENV="/opt/taiga"
PYTHON_BIN="/usr/local/bin/python3.11"
BUILD_DIR="$(mktemp -d /tmp/taiga-build-XXXXXX)"
GITHUB="https://github.com/taigaio"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# download a release tarball and unpack it: __fetch_tag url dest strip
__fetch_tag() {
  local url="$1" dest="$2" strip="${3:-1}"
  mkdir -p "$dest"
  curl -fsSL --retry 5 --retry-delay 3 "$url" -o "$BUILD_DIR/archive.tgz"
  tar -xzf "$BUILD_DIR/archive.tgz" -C "$dest" --strip-components="$strip"
  rm -f "$BUILD_DIR/archive.tgz"
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# build time only packages - removed again at the end
apk add --no-cache --virtual .taiga-build \
  build-base git gettext linux-headers npm \
  libffi-dev libpq-dev jpeg-dev zlib-dev freetype-dev lcms2-dev openjpeg-dev libwebp-dev \
  libxml2-dev libxslt-dev cairo-dev
mkdir -p "$TAIGA_ROOT" "$TAIGA_VENV"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# taiga-back (django api, celery tasks)
echo "Installing taiga-back ${TAIGA_BACK_VERSION}"
__fetch_tag "$GITHUB/taiga-back/archive/refs/tags/${TAIGA_BACK_VERSION}.tar.gz" "$TAIGA_ROOT/taiga-back"
"$PYTHON_BIN" -m venv "$TAIGA_VENV/venv-back"
# scikit-image has no musllinux wheel; its pythran sources need C++17
export CXXFLAGS="${CXXFLAGS:-} -std=gnu++17"
"$TAIGA_VENV/venv-back/bin/python" -m pip install --no-cache-dir --upgrade pip wheel
(
  cd "$TAIGA_ROOT/taiga-back"
  "$TAIGA_VENV/venv-back/bin/python" -m pip install --no-cache-dir -r requirements.txt
  "$TAIGA_VENV/venv-back/bin/python" -m pip install --no-cache-dir -r requirements-contribs.txt
  cp -f docker/config.py settings/config.py
  export DJANGO_SETTINGS_MODULE="settings.config"
  # throwaway key so compilemessages and collectstatic can import settings; never kept
  export TAIGA_SECRET_KEY="build-time-only-not-used-at-runtime" SECRET_KEY="build-time-only-not-used-at-runtime"
  "$TAIGA_VENV/venv-back/bin/python" manage.py compilemessages
  "$TAIGA_VENV/venv-back/bin/python" manage.py collectstatic --no-input
  mkdir -p media/exports
  rm -Rf requirements.txt requirements-contribs.txt tests docker
  find . -name '*.po' -type f -delete
)
# - - - - - - - - - - - - - - - - - - - - - - - - -
# taiga-protected (signed media service)
echo "Installing taiga-protected ${TAIGA_PROTECTED_VERSION}"
__fetch_tag "$GITHUB/taiga-protected/archive/refs/tags/${TAIGA_PROTECTED_VERSION}.tar.gz" "$TAIGA_ROOT/taiga-protected"
"$PYTHON_BIN" -m venv "$TAIGA_VENV/venv-protected"
"$TAIGA_VENV/venv-protected/bin/python" -m pip install --no-cache-dir --upgrade pip wheel
sed '/^-i /d' "$TAIGA_ROOT/taiga-protected/requirements.txt" >"$BUILD_DIR/protected-requirements.txt"
"$TAIGA_VENV/venv-protected/bin/python" -m pip install --no-cache-dir -r "$BUILD_DIR/protected-requirements.txt"
rm -Rf "$TAIGA_ROOT/taiga-protected/requirements.txt" "$TAIGA_ROOT/taiga-protected/docker"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# taiga-events (node websocket server)
echo "Installing taiga-events ${TAIGA_EVENTS_VERSION}"
__fetch_tag "$GITHUB/taiga-events/archive/refs/tags/${TAIGA_EVENTS_VERSION}.tar.gz" "$TAIGA_ROOT/taiga-events"
(
  cd "$TAIGA_ROOT/taiga-events"
  npm ci --omit=dev --no-audit --no-fund || npm install --omit=dev --no-audit --no-fund
  npm cache clean --force
  rm -Rf docker
)
# - - - - - - - - - - - - - - - - - - - - - - - - -
# taiga-front (prebuilt distribution) and the front contrib plugins
echo "Installing taiga-front ${TAIGA_FRONT_VERSION}"
__fetch_tag "$GITHUB/taiga-front-dist/archive/refs/tags/${TAIGA_FRONT_VERSION}.tar.gz" "$BUILD_DIR/front-dist"
mkdir -p "$TAIGA_ROOT/taiga-front"
cp -Rf "$BUILD_DIR/front-dist/dist/." "$TAIGA_ROOT/taiga-front/"
for contrib in slack github-auth gitlab-auth; do
  echo "Installing taiga-contrib-${contrib} ${TAIGA_CONTRIB_VERSION}"
  mkdir -p "$TAIGA_ROOT/taiga-front/plugins/$contrib"
  curl -fsSL --retry 5 --retry-delay 3 "$GITHUB/taiga-contrib-${contrib}/archive/refs/tags/${TAIGA_CONTRIB_VERSION}.tar.gz" -o "$BUILD_DIR/contrib.tgz"
  tar -xzf "$BUILD_DIR/contrib.tgz" -C "$TAIGA_ROOT/taiga-front/plugins/$contrib" --strip-components=3 --wildcards '*/front/dist/*'
  rm -f "$BUILD_DIR/contrib.tgz"
done
# - - - - - - - - - - - - - - - - - - - - - - - - -
# the stock alpine nginx site is replaced by the taiga gateway installed from /tmp/etc/nginx by 03-files.sh
rm -f /etc/nginx/http.d/default.conf /etc/nginx/conf.d/default.conf 2>/dev/null || true
# - - - - - - - - - - - - - - - - - - - - - - - - -
# runtime state: media lives on the data volume, static files are baked in
rm -Rf "$TAIGA_ROOT/taiga-back/media"
ln -sf /data/taiga/media "$TAIGA_ROOT/taiga-back/media"
# the container health check matches processes by exact name, so each service runs
# through a link carrying its own name (a venv link keeps pyvenv.cfg detection)
ln -sf python "$TAIGA_VENV/venv-back/bin/taiga-back"
ln -sf python "$TAIGA_VENV/venv-back/bin/taiga-async"
ln -sf python "$TAIGA_VENV/venv-protected/bin/taiga-protected"
ln -sf "$(command -v node)" /usr/local/bin/taiga-events
chmod 755 /usr/local/etc/docker/bin/* 2>/dev/null || true
chown -R taiga:taiga "$TAIGA_ROOT/taiga-back" "$TAIGA_ROOT/taiga-protected" "$TAIGA_ROOT/taiga-events"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# cleanup
apk del --no-cache .taiga-build
rm -Rf "$BUILD_DIR" /root/.cache /root/.npm /tmp/taiga-build-* 2>/dev/null || true
true

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the exit code
exitCode=$?
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit $exitCode
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -

