#!/bin/bash
# roytalk -- prepare a fresh Ubuntu 24.04 VM (e.g. Oracle Cloud Always Free,
# 1 OCPU / 1 GB) and install the app. Run as root from the unpacked app folder:
#
#   sudo deploy/setup-server.sh
#
# Safe to run again: every step checks what is already there.
set -euo pipefail

APP_SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR=/srv/roytalk
APP_USER=roytalk
DB_NAME=roytalk
DB_USER=roytalk
SRC=/usr/local/src/roytalk-deps

say() { printf '\n== %s\n' "$*"; }

say "Swap (2 GB): building Guile code and pandoc both like memory"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 && echo 'vm.swappiness=10' > /etc/sysctl.d/90-roytalk.conf
fi

say "Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q guile-3.0 guile-3.0-dev guile-json postgresql pandoc msmtp \
  autoconf automake libtool texinfo pkg-config gettext make gcc git \
  libnss3-dev libargon2-dev libpq-dev libcurl4-openssl-dev ca-certificates rclone rsync fuse3

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

say "PostgreSQL, sized for 1 GB of RAM"
PGCONF=$(ls -d /etc/postgresql/*/main | tail -1)/conf.d
mkdir -p "$PGCONF" && cp "$APP_SRC/deploy/postgresql-small.conf" "$PGCONF/roytalk.conf"
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
# citext is a trusted extension: the database owner creates it, so it also owns
# it, and tools/restore.sh runs entirely as the app's role.
PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -qc "CREATE EXTENSION IF NOT EXISTS citext"

say "App in $APP_DIR"
id "$APP_USER" >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
mkdir -p "$APP_DIR"
# prv/asset-private/ is the rclone mount of the private R2 bucket (backups):
# never sync, delete or chown into it. $APP_DIR is also the roytalk user's
# home, so its dot directories (systemd user units, rclone config) stay too.
rsync -a --delete --exclude prv/settings.scm --exclude prv/asset-private/ \
  --exclude log/ --exclude tmp/ --exclude '/.*' "$APP_SRC/" "$APP_DIR/"
mkdir -p "$APP_DIR"/{log,tmp,prv}
mountpoint -q "$APP_DIR/prv/asset-private" || mkdir -p "$APP_DIR/prv/asset-private"
sed -i -e "s/^db.passwd = .*/db.passwd = $DB_PASS/" "$APP_DIR/conf/artanis.conf"
if [ ! -f "$APP_DIR/prv/settings.scm" ]; then
  SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  sed -e "s/\"CHANGE-ME\"/\"$SECRET\"/" -e 's/(mail-mode . log)/(mail-mode . send)/' \
    "$APP_DIR/prv/settings.example.scm" > "$APP_DIR/prv/settings.scm"
  echo "!! Edit $APP_DIR/prv/settings.scm: author-emails, mail-from, OAuth keys."
fi
find "$APP_DIR" -path "$APP_DIR/prv/asset-private" -prune -o -exec chown "$APP_USER:$APP_USER" {} +
chmod 700 "$APP_DIR/prv"
PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q -f "$APP_DIR/db/schema.sql"

say "Services"
cp "$APP_SRC"/deploy/roytalk-web.service "$APP_SRC"/deploy/roytalk-mailer.service \
   "$APP_SRC"/deploy/roytalk-digest.service "$APP_SRC"/deploy/roytalk-digest.timer /etc/systemd/system/
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

say "Done"
echo "The app listens on 127.0.0.1:3000. Put Cloudflare in front (deploy/README.md)."
echo "Mail relay: /etc/msmtprc (deploy/msmtprc.example)."
echo "The monthly digest runs from roytalk-digest.timer: systemctl list-timers roytalk-digest.timer"
echo "Preview it with:"
echo "  cd /srv/roytalk && sudo -u roytalk env LANG=C.UTF-8 \\"
echo "    XDG_CACHE_HOME=/var/lib/roytalk-guile-cache guile -L lib tools/digest.scm --dry-run"
echo "!! Backups are not scheduled yet: install the user units in deploy/systemd-user/"
echo "   (backup timer and, optionally, the rclone mount). See README.md, Backups."
