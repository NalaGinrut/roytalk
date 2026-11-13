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

# Write a unit file from stdin. If the destination already exists with
# different content, warn (yellow) and ask before replacing it, so a unit
# edited by hand on the server is not silently lost. Answering anything but
# y keeps the old file. Without a terminal (unattended run) it overwrites,
# as before.
install_unit() {
  local dst=$1 owner=${2:-root} mode=${3:-644} tmp answer= keep=
  tmp=$(mktemp) || die "mktemp failed"
  cat > "$tmp" || { rm -f "$tmp"; die "failed to read unit for $dst"; }

  if [ -f "$dst" ] && ! cmp -s "$tmp" "$dst"; then
    if (exec </dev/tty) 2>/dev/null; then
      if [ -t 2 ]; then
        printf '\n\033[1;33m!! %s exists and differs from deploy/%s\033[0m\n' \
          "$dst" "${dst##*/}" >&2
      else
        printf '\n!! %s exists and differs from deploy/%s\n' \
          "$dst" "${dst##*/}" >&2
      fi
      printf '   Overwrite it? [y/N] ' >&2
      read -r answer < /dev/tty || answer=n
      case "$answer" in
        y|Y|yes|YES) ;;
        *) keep=1 ;;
      esac
    fi
  fi

  if [ -n "$keep" ]; then
    echo "   kept $dst"
  else
    install -o "$owner" -g "$owner" -m "$mode" "$tmp" "$dst"
  fi
  rm -f "$tmp"
}

# Is PATH a mount point? mountpoint(1) stats the directory, but a FUSE mount
# made by another user refuses root (EACCES) without allow_other, so it would
# report "not a mountpoint". The kernel's mount table can always be read.
is_mountpoint() {
  grep -q " $1 " /proc/self/mountinfo
}

# Run systemctl --user for the app user. HOME and XDG_RUNTIME_DIR are set
# explicitly: runuser starts from a clean environment and systemctl needs them
# to find ~/.config/systemd/user and the user manager's socket.
user_systemctl() {
  local uid
  uid=$(id -u "$APP_USER")
  runuser -u "$APP_USER" -- env HOME="$APP_DIR" XDG_RUNTIME_DIR="/run/user/$uid" \
    systemctl --user "$@"
}

usage() {
  cat <<EOF
Usage: $0 [--from STAGE] [--list]

Stages, in order:
  ${STAGES[*]}

No flag runs every stage. --from START runs START and everything after it.
--list prints the stage names.

Environment: APP_DIR (default /var/www/roytalk), APP_USER, DB_NAME, DB_USER, SRC,
RCLONE_CONFIG_SRC (default /root/.config/rclone/rclone.conf).
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
  is_mountpoint "$APP_DIR/prv/asset-private" || mkdir -p "$APP_DIR/prv/asset-private"
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
  # The mount is made by the app user, so it must own the mountpoint. Do this
  # only when nothing is mounted: chowning a mountpoint would hit the R2 root.
  if ! is_mountpoint "$APP_DIR/prv/asset-private"; then
    chown "$APP_USER:$APP_USER" "$APP_DIR/prv/asset-private"
  fi
  PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q -f "$APP_DIR/db/schema.sql"
}

# ---------------------------------------------------------------- services
services() {
  say "Services"
  # The units in deploy/ are written for /var/www/roytalk; rewrite the path when
  # the app lives elsewhere, so a redeploy doesn't point them back there.
  local unit install_rclone= start_mount= mountpoint="$APP_DIR/prv/asset-private"
  # The app directory is also the app user's home; earlier manual setup may
  # have left .config owned by root, and systemctl --user needs to traverse it.
  if [ -d "$APP_DIR/.config" ]; then
    chown "$APP_USER:$APP_USER" "$APP_DIR/.config"
  fi
  for unit in roytalk-web roytalk-mailer roytalk-digest; do
    sed "s#/var/www/roytalk#$APP_DIR#g" "$APP_SRC/deploy/$unit.service" \
      | install_unit "/etc/systemd/system/$unit.service"
  done
  install_unit /etc/systemd/system/roytalk-digest.timer \
    < "$APP_SRC/deploy/roytalk-digest.timer"

  # R2 mount. It runs as the app user, so it needs that user's rclone config;
  # take the root setup's copy when there is none yet (RCLONE_CONFIG_SRC
  # overrides the source). Without any config prv/asset-private/ stays a plain
  # directory and backups are written to local disk.
  local rclone_conf="$APP_DIR/.config/rclone/rclone.conf"
  local rclone_src=${RCLONE_CONFIG_SRC:-/root/.config/rclone/rclone.conf}
  if [ ! -f "$rclone_conf" ] && [ -f "$rclone_src" ]; then
    install -d -o "$APP_USER" -g "$APP_USER" "$(dirname "$rclone_conf")"
    install -o "$APP_USER" -g "$APP_USER" -m 600 "$rclone_src" "$rclone_conf"
    echo "Copied $rclone_src to $rclone_conf"
  fi
  if [ -f "$rclone_conf" ]; then
    chown "$APP_USER:$APP_USER" "$rclone_conf"
    chmod 600 "$rclone_conf"
    sed -e "s#/var/www/roytalk#$APP_DIR#g" \
        -e "s#^User=roytalk\$#User=$APP_USER#" \
        -e "s#^Group=roytalk\$#Group=$APP_USER#" \
        "$APP_SRC/deploy/rclone-roytalk-assets-private.service" \
      | install_unit /etc/systemd/system/rclone-roytalk-assets-private.service
    install_rclone=1
    if is_mountpoint "$mountpoint" \
       && ! systemctl is-active --quiet rclone-roytalk-assets-private; then
      # A mount made by someone else (e.g. the old root-level unit): report it
      # rather than start a second mount that would fail and retry forever.
      echo "!! $mountpoint is mounted, but not by rclone-roytalk-assets-private." >&2
      echo "   Unmount it (fusermount3 -u $mountpoint) and rerun this stage." >&2
    else
      if ! is_mountpoint "$mountpoint"; then
        install -d "$mountpoint"
        chown "$APP_USER:$APP_USER" "$mountpoint"
      fi
      start_mount=1
    fi
  fi

  systemctl daemon-reload
  # Guile inlines small procedures across modules into each caller's compiled
  # .go, and only recompiles a file when its own source changes. After a
  # redeploy, a controller that didn't change could keep running the old copy
  # of a library function. Start from an empty compile cache every time.
  systemctl stop roytalk-digest.timer roytalk-digest.service 2>/dev/null || true
  systemctl stop roytalk-web roytalk-mailer 2>/dev/null || true
  rm -rf /var/lib/roytalk-guile-cache/* "$APP_DIR/tmp/cache"
  systemctl enable roytalk-web roytalk-mailer roytalk-digest.timer
  if [ -n "$install_rclone" ]; then
    systemctl enable rclone-roytalk-assets-private
    # start, not restart: a redeploy must not disturb a live mount
    if [ -n "$start_mount" ]; then
      systemctl start rclone-roytalk-assets-private
    fi
  fi
  # Only the timer starts: a digest goes out on its schedule, never on deploy.
  systemctl restart roytalk-web roytalk-mailer roytalk-digest.timer

  # Backup user units: they run under the app user's manager (which lingers,
  # so no login is needed) because that user owns conf/artanis.conf and the
  # mount.
  local user_units="$APP_DIR/.config/systemd/user"
  install -d -o "$APP_USER" -g "$APP_USER" "$user_units"
  for unit in roytalk-backup.service roytalk-backup.timer; do
    install_unit "$user_units/$unit" "$APP_USER" 644 \
      < "$APP_SRC/deploy/systemd-user/$unit"
  done
  # Left over from when the mount was a user unit; it is a system unit now.
  rm -f "$user_units/roytalk-asset-mount.service" \
        "$user_units/default.target.wants/roytalk-asset-mount.service" \
        "$user_units/multi-user.target.wants/roytalk-asset-mount.service"
  # Enable the timer with a symlink instead of `systemctl --user enable`:
  # systemd 255.4-1ubuntu8.{0,1,2} fails enable for units in ~/.config with a
  # bogus "Unit file ... does not exist".
  install -d -o "$APP_USER" -g "$APP_USER" "$user_units/timers.target.wants"
  ln -sfn ../roytalk-backup.timer "$user_units/timers.target.wants/roytalk-backup.timer"
  chown -h "$APP_USER:$APP_USER" "$user_units/timers.target.wants/roytalk-backup.timer"

  loginctl enable-linger "$APP_USER"
  systemctl start "user@$(id -u "$APP_USER")"
  user_systemctl daemon-reload
  user_systemctl start roytalk-backup.timer
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
echo "Backups run from roytalk-backup.timer as $APP_USER; check it with"
echo "  sudo -u $APP_USER -H env XDG_RUNTIME_DIR=/run/user/$(id -u "$APP_USER") \\"
echo "    systemctl --user list-timers"
echo "R2 mount (when configured): systemctl status rclone-roytalk-assets-private"
