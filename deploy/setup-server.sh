#!/bin/bash
# roytalk -- prepare a fresh Ubuntu 24.04 VM (e.g. Oracle Cloud Always Free,
# 1 OCPU / 1 GB) and install the app. Run as root from the unpacked app folder:
#
#   sudo deploy/setup-server.sh                  # every stage
#   sudo deploy/setup-server.sh --from user      # user, db, app, services
#   sudo deploy/setup-server.sh --from db        # db, app, services
#   sudo deploy/setup-server.sh --from services  # just the systemd units
#   sudo deploy/setup-server.sh --list           # stage names, in order
#
# Stages, in order:
#   swap      create /swapfile (building Guile code needs it)
#   packages  apt-get install the runtime packages
#   deps      build guile-dbi, guile-curl, guile-redis and GNU Artanis
#   user      create the service account and its home ($APP_DIR)
#   db        size PostgreSQL, create the role, database and citext
#   app       copy the app to $APP_DIR, write prv/settings.scm, load schema
#   services  install the systemd units and (re)start them
#
# --from runs the named stage and everything after it; the stage right before
# services is useful to "just redo services". With no flag every stage runs.
# Safe to run again: every stage checks what is already there.
#
# APP_DIR is where the app is installed and defaults to /var/www/roytalk. The
# systemd units are rewritten from the ones in deploy/ with that path, so a
# different install location needs no hand-editing:
#
#   sudo APP_DIR=/var/www/roytalk deploy/setup-server.sh --from services
set -euo pipefail

APP_SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR=${APP_DIR:-/var/www/roytalk}
APP_USER=${APP_USER:-roytalk}
DB_NAME=${DB_NAME:-roytalk}
DB_USER=${DB_USER:-roytalk}
SRC=${SRC:-/usr/local/src/roytalk-deps}
DB_PASS=

STAGES=(swap packages deps user db app services)

say() { printf '\n== %s\n' "$*"; }
die() { echo "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--from STAGE] [--list]

Stages, in order:
  ${STAGES[*]}

No flag runs every stage. --from START runs START and everything after it.
--list prints the stage names.

Environment: APP_DIR (default /var/www/roytalk), APP_USER, DB_NAME, DB_USER, SRC.
EOF
}

stage_index() {
  local want=$1 i
  for i in "${!STAGES[@]}"; do
    [ "${STAGES[$i]}" = "$want" ] && { echo "$i"; return 0; }
  done
  die "unknown stage \"$want\" (known: ${STAGES[*]})"
}

FROM=
while [ $# -gt 0 ]; do
  case "$1" in
    --from) [ $# -ge 2 ] || die "--from needs a stage name"; FROM=$2; shift 2 ;;
    --list) printf '%s\n' "${STAGES[@]}"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

START=0
END=$((${#STAGES[@]} - 1))
if [ -n "$FROM" ]; then
  START=$(stage_index "$FROM")
fi

[ "$(id -u)" -eq 0 ] || die "run as root (sudo $0)"

# ---------------------------------------------------------------- swap
swap() {
  say "Swap (2 GB): building Guile code and pandoc both like memory"
  if ! swapon --show | grep -q /swapfile; then
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    # Append rather than overwrite: deploy/tune-sysctl.sh owns this file with
    # a full set of settings, and must survive a redeploy.
    sysctl -w vm.swappiness=10
    grep -q '^vm.swappiness' /etc/sysctl.d/90-roytalk.conf 2>/dev/null \
      || echo 'vm.swappiness=10' >> /etc/sysctl.d/90-roytalk.conf
  fi
}

# ---------------------------------------------------------------- packages
packages() {
  say "Packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -y -q guile-3.0 guile-3.0-dev guile-json postgresql pandoc msmtp \
    autoconf automake libtool texinfo pkg-config gettext make gcc git \
    libnss3-dev libargon2-dev libpq-dev libcurl4-openssl-dev ca-certificates rclone rsync fuse3
}

# ---------------------------------------------------------------- deps
deps() {
  say "Guile libraries and GNU Artanis from source"
  mkdir -p "$SRC" && cd "$SRC"
  fetch() { [ -d "$2" ] && git -C "$2" pull -q || git clone -q --depth 1 "$1" "$2"; }
  build() { (cd "$1" && (./autogen.sh || autoreconf -vif) >/dev/null && ./configure --prefix=/usr >/dev/null && make -j1 >/dev/null && make install >/dev/null); }
  fetch https://github.com/opencog/guile-dbi guile-dbi
  build guile-dbi/guile-dbi && ldconfig && build guile-dbi/guile-dbd-postgresql && ldconfig
  fetch https://github.com/spk121/guile-curl guile-curl && build guile-curl
  fetch https://github.com/aconchillo/guile-redis guile-redis && build guile-redis
  EXT=$(guile -c '(display (assq-ref %guile-build-info (quote extensiondir)))')
  ln -sf /usr/lib/guile/3.0/extensions/libguile-curl.so* "$EXT/" 2>/dev/null || true
  ldconfig
  fetch https://github.com/NalaGinrut/artanis artanis && build artanis
  art version
}

# ---------------------------------------------------------------- user
# Kept apart from deps and app so it can be redone on its own (--from user);
# app calls it too, in case --from app skips this stage.
ensure_user() {
  id "$APP_USER" >/dev/null 2>&1 \
    || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
  mkdir -p "$APP_DIR"
  chown "$APP_USER:$APP_USER" "$APP_DIR"
}

user() {
  say "User $APP_USER (home $APP_DIR)"
  ensure_user
}

# ---------------------------------------------------------------- db
db() {
  say "PostgreSQL, sized for 1 GB of RAM"
  local cluster pgconf
  cluster=$(ls -d /etc/postgresql/*/main 2>/dev/null | tail -1 || true)
  [ -n "$cluster" ] || die "no PostgreSQL cluster found in /etc/postgresql/*/main"
  pgconf=$cluster/conf.d
  mkdir -p "$pgconf" && cp "$APP_SRC/deploy/postgresql-small.conf" "$pgconf/roytalk.conf"
  systemctl restart postgresql
  if [ ! -f /etc/roytalk/db.pass ]; then
    mkdir -p /etc/roytalk && head -c 18 /dev/urandom | base64 | tr -d '/+=' > /etc/roytalk/db.pass
    chmod 600 /etc/roytalk/db.pass
  fi
  DB_PASS=$(cat /etc/roytalk/db.pass)
  sudo -u postgres psql -qtc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 \
    || sudo -u postgres psql -qc "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS'"
  sudo -u postgres psql -qtc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
    || sudo -u postgres psql -qc "CREATE DATABASE $DB_NAME OWNER $DB_USER"
  # citext is a trusted extension: the database owner creates it, so it also
  # owns it, and tools/restore.sh runs entirely as the app's role.
  PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -qc "CREATE EXTENSION IF NOT EXISTS citext"
}

db_pass() {
  [ -n "$DB_PASS" ] && return 0
  [ -f /etc/roytalk/db.pass ] \
    || die "no /etc/roytalk/db.pass: run the db stage first (--from db)"
  DB_PASS=$(cat /etc/roytalk/db.pass)
}

# ---------------------------------------------------------------- app
app() {
  db_pass
  say "App in $APP_DIR"
  ensure_user
  # prv/asset-private/ is the rclone mount of the private R2 bucket (backups):
  # never sync, delete or chown into it. $APP_DIR is also the roytalk user's
  # home, so its dot directories (systemd user units, rclone config) stay too.
  # When the checkout is deployed in place (APP_SRC == APP_DIR), there is
  # nothing to copy and rsync would refuse to sync a directory onto itself.
  if [ "$(cd "$APP_SRC" && pwd -P)" != "$(cd "$APP_DIR" && pwd -P)" ]; then
    rsync -a --delete --exclude prv/settings.scm --exclude prv/asset-private/ \
      --exclude log/ --exclude tmp/ --exclude '/.*' "$APP_SRC/" "$APP_DIR/"
  else
    echo "APP_SRC is APP_DIR ($APP_DIR); the code is already in place"
  fi
  mkdir -p "$APP_DIR"/{log,tmp,prv}
  mountpoint -q "$APP_DIR/prv/asset-private" || mkdir -p "$APP_DIR/prv/asset-private"
  sed -i -e "s/^db.passwd = .*/db.passwd = $DB_PASS/" "$APP_DIR/conf/artanis.conf"
  if [ ! -f "$APP_DIR/prv/settings.scm" ]; then
    local secret
    secret=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    sed -e "s/\"CHANGE-ME\"/\"$secret\"/" -e 's/(mail-mode . log)/(mail-mode . send)/' \
      "$APP_DIR/prv/settings.example.scm" > "$APP_DIR/prv/settings.scm"
    echo "!! Edit $APP_DIR/prv/settings.scm: author-emails, mail-from, OAuth keys."
  fi
  find "$APP_DIR" -path "$APP_DIR/prv/asset-private" -prune -o -exec chown "$APP_USER:$APP_USER" {} +
  chmod 700 "$APP_DIR/prv"
  PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q -f "$APP_DIR/db/schema.sql"
}

# ---------------------------------------------------------------- services
services() {
  say "Services"
  # The units in deploy/ are written for /var/www/roytalk; rewrite the path when
  # the app lives elsewhere, so a redeploy doesn't point them back there.
  local unit
  for unit in roytalk-web roytalk-mailer roytalk-digest; do
    sed "s#/var/www/roytalk#$APP_DIR#g" "$APP_SRC/deploy/$unit.service" \
      > "/etc/systemd/system/$unit.service"
  done
  cp "$APP_SRC/deploy/roytalk-digest.timer" /etc/systemd/system/
  systemctl daemon-reload
  # Guile inlines small procedures across modules into each caller's compiled
  # .go, and only recompiles a file when its own source changes. After a
  # redeploy, a controller that didn't change could keep running the old copy
  # of a library function. Start from an empty compile cache every time.
  systemctl stop roytalk-digest.timer roytalk-digest.service 2>/dev/null || true
  systemctl stop roytalk-web roytalk-mailer 2>/dev/null || true
  rm -rf /var/lib/roytalk-guile-cache/* "$APP_DIR/tmp/cache"
  systemctl enable roytalk-web roytalk-mailer roytalk-digest.timer
  # Only the timer starts: a digest goes out on its schedule, never on deploy.
  systemctl restart roytalk-web roytalk-mailer roytalk-digest.timer
}

for ((i = START; i <= END; i++)); do
  "${STAGES[$i]}"
done

say "Done"
echo "The app listens on 127.0.0.1:3000; deploy/nginx-roytalk.conf fronts it on"
echo "127.0.0.1:8080, and the Cloudflare tunnel points there (deploy/cloudflared.yml.example)."
echo "Kernel/network tuning: sudo deploy/tune-sysctl.sh"
echo "Mail relay: /etc/msmtprc (deploy/msmtprc.example)."
echo "The monthly digest runs from roytalk-digest.timer: systemctl list-timers roytalk-digest.timer"
echo "Preview it with:"
echo "  cd $APP_DIR && sudo -u $APP_USER env LANG=C.UTF-8 \\"
echo "    XDG_CACHE_HOME=/var/lib/roytalk-guile-cache guile -L lib tools/digest.scm --dry-run"
echo "!! Backups are not scheduled yet: install the user units in deploy/systemd-user/"
echo "   (backup timer and, optionally, the rclone mount). See README.md, Backups."
