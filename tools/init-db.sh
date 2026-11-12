#!/bin/bash
# roytalk -- initialise the PostgreSQL database.
#
#   tools/init-db.sh          ask before changing/creating the password
#   tools/init-db.sh --yes    never ask (unattended runs)
#
# Idempotent: run it as often as you like. It reads db.name, db.username,
# db.passwd, db.addr and db.proto from conf/artanis.conf (the one place the
# database settings live) and:
#
#   1. creates the login role, or resets its password to the configured one;
#      it always warns and asks first, so a re-run never silently changes a
#      password. Pass --yes to skip the question (for unattended runs);
#   2. creates the database, owned by that role;
#   3. creates the citext extension and runs db/schema.sql as the app role;
#   4. applies every migration in db/migration/ that has not run yet, in file
#      name order, recording each in the roytalk_migrations table:
#        *.sql  run with psql --single-transaction (no BEGIN/COMMIT inside;
#               no CREATE INDEX CONCURRENTLY, which can't run in a transaction)
#        *.scm  Artanis migrations, <name>_<14-digit timestamp>.scm, run with
#               `art migrate up <name> VERSION=<timestamp>`
#
# The admin connection defaults to the local postgres superuser:
#   - `psql -d postgres` if the current user already is a superuser;
#   - `runuser -u postgres -- psql` when run as root;
#   - `sudo -u postgres psql` otherwise (it may ask for your password).
# Set PG_ADMIN_PSQL to use another psql binary, and the usual PG* variables
# (PGHOST, PGUSER, PGPASSWORD, ...) to reach a remote server, e.g.
#
#   PG_ADMIN_PSQL=psql PGUSER=postgres PGHOST=db.example PGPASSWORD=... \
#     tools/init-db.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$APP_DIR/conf/artanis.conf"
[ -f "$CONF" ] || { echo "missing $CONF" >&2; exit 1; }

conf() { sed -n "s/^$1 = //p" "$CONF" | head -1; }

DB_NAME=$(conf db.name)
DB_USER=$(conf db.username)
DB_PASS=$(conf db.passwd)
DB_ADDR=$(conf db.addr)
DB_PROTO=$(conf db.proto)
: "${DB_NAME:=roytalk}" "${DB_USER:=roytalk}" "${DB_PASS:=CHANGE-ME}"

if [ "${DB_PROTO:-tcp}" = socketfile ]; then
  DB_HOST=$(conf db.socketfile)
  DB_PORT=5432
elif [[ "$DB_ADDR" == *:* ]]; then
  DB_HOST=${DB_ADDR%:*}
  DB_PORT=${DB_ADDR##*:}
else
  DB_HOST=${DB_ADDR:-127.0.0.1}
  DB_PORT=5432
fi

say() { printf '\n== %s\n' "$*"; }

# A single-quoted SQL literal, for the file names and settings we read above.
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

usage() {
  sed -n '2,/^set -euo/{s/^# \{0,1\}//;p}' "$0" | sed '$d'
  exit "${1:-0}"
}

ASSUME_YES=0
case "${1:-}" in
  -y|--yes) ASSUME_YES=1 ;;
  -h|--help) usage 0 ;;
  "") ;;
  *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
esac
[ $# -gt 1 ] && { echo "too many arguments (see --help)" >&2; exit 2; }

# Ask before creating or changing a password; never do it silently.
confirm() {
  local question=$1 answer
  if [ "$ASSUME_YES" = 1 ]; then
    echo "  $question -> yes (--yes)"
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "stdin is not a terminal; pass --yes to confirm the password change" >&2
    exit 1
  fi
  read -r -p "  $question [Y/n] " answer || answer=
  case "${answer:-y}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------- admin access
if [ -n "${PG_ADMIN_PSQL:-}" ]; then
  ADMIN=("$PG_ADMIN_PSQL")
elif psql -w -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
  ADMIN=(psql)
elif [ "$(id -u)" -eq 0 ] && id postgres >/dev/null 2>&1; then
  ADMIN=(runuser -u postgres -- psql)
elif command -v sudo >/dev/null 2>&1 && id postgres >/dev/null 2>&1; then
  ADMIN=(sudo -u postgres psql)
else
  echo "no PostgreSQL superuser access found" >&2
  echo "run as root, install sudo, or set PG_ADMIN_PSQL plus PGUSER/PGHOST/PGPASSWORD" >&2
  exit 1
fi

# --------------------------------------------------------- role and database
say "Role and database"
admin_sql() { "${ADMIN[@]}" -X -d postgres -v ON_ERROR_STOP=1 "$@"; }
role_exists() {
  [ -n "$(admin_sql -tAc "SELECT 1 FROM pg_roles WHERE rolname = $(sql_lit "$DB_USER")")" ]
}

# The password is never touched silently: show it, then ask. The value in
# conf/artanis.conf is what the app and tools/backup.sh will use from now on.
if role_exists; then
  echo "The login role \"$DB_USER\" already exists."
  echo "conf/artanis.conf sets db.passwd to: $DB_PASS"
  if confirm "Change the role password to this value?"; then
    admin_sql <<SQL
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', $(sql_lit "$DB_USER"), $(sql_lit "$DB_PASS")) \gexec
SQL
  else
    echo "  keeping the existing role password"
  fi
else
  echo "The login role \"$DB_USER\" does not exist."
  echo "conf/artanis.conf sets db.passwd to: $DB_PASS"
  confirm "Create the role with this password?" || {
    echo "aborted: no role was created" >&2
    exit 1
  }
  admin_sql <<SQL
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', $(sql_lit "$DB_USER"), $(sql_lit "$DB_PASS")) \gexec
SQL
fi

admin_sql <<SQL
SELECT format('CREATE DATABASE %I OWNER %I', $(sql_lit "$DB_NAME"), $(sql_lit "$DB_USER"))
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = $(sql_lit "$DB_NAME")) \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', $(sql_lit "$DB_NAME"), $(sql_lit "$DB_USER")) \gexec
SQL

if [ "$DB_PASS" = CHANGE-ME ]; then
  echo "note: using the example password CHANGE-ME; set a real one in conf/artanis.conf before deploying"
fi

export PGPASSWORD="$DB_PASS"
APP=(psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1)

# Fail clearly if the password in conf/artanis.conf is not the role's password
# (e.g. the question above was answered "no"), rather than in db/schema.sql.
if ! "${APP[@]}" -tAc 'SELECT 1' >/dev/null 2>&1; then
  echo "cannot connect as \"$DB_USER\" to \"$DB_NAME\" with db.passwd from conf/artanis.conf" >&2
  echo "re-run and answer yes to the password change, or put the role's current password in conf/artanis.conf" >&2
  exit 1
fi

# ------------------------------------------------------ extension and schema
say "Extension and schema"
# citext is trusted, so the database owner (the app role) can create it.
"${APP[@]}" -q -c 'CREATE EXTENSION IF NOT EXISTS citext'
"${APP[@]}" -q -f "$APP_DIR/db/schema.sql"
"${APP[@]}" -q -c 'CREATE TABLE IF NOT EXISTS roytalk_migrations (
                      name       text PRIMARY KEY,
                      applied_at timestamptz NOT NULL DEFAULT now())'

# --------------------------------------------------------------- migrations
MIGRATIONS=()
while IFS= read -r f; do MIGRATIONS+=("$f"); done < <(
  find "$APP_DIR/db/migration" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.scm' \) | sort)

if [ "${#MIGRATIONS[@]}" -eq 0 ]; then
  say "Migrations: none"
else
  say "Migrations"
  for f in "${MIGRATIONS[@]}"; do
    name=$(basename "$f")
    if [ -n "$("${APP[@]}" -tAc "SELECT 1 FROM roytalk_migrations WHERE name = $(sql_lit "$name")")" ]; then
      echo "  skip   $name (already applied)"
      continue
    fi
    case "$f" in
      *.sql)
        echo "  apply  $name"
        { cat "$f"
          printf '\nINSERT INTO roytalk_migrations (name) VALUES (%s) ON CONFLICT DO NOTHING;\n' \
                 "$(sql_lit "$name")"
        } | "${APP[@]}" -q --single-transaction
        ;;
      *.scm)
        [[ "$name" =~ ^(.+)_([0-9]{14})\.scm$ ]] || {
          echo "bad migration name: $name (want <name>_<14-digit timestamp>.scm)" >&2
          exit 1
        }
        command -v art >/dev/null 2>&1 || { echo "art not found (needed for $name)" >&2; exit 1; }
        echo "  apply  $name"
        ( cd "$APP_DIR" &&
          art migrate up "${BASH_REMATCH[1]}" "VERSION=${BASH_REMATCH[2]}" )
        "${APP[@]}" -q -c "INSERT INTO roytalk_migrations (name)
                           VALUES ($(sql_lit "$name")) ON CONFLICT DO NOTHING"
        ;;
    esac
  done
fi

say "Done"
if [ ! -f "$APP_DIR/prv/settings.scm" ]; then
  echo "Next: cp prv/settings.example.scm prv/settings.scm   # set secret, author-emails"
fi
echo "Then: LANG=C.UTF-8 art work                          # http://127.0.0.1:3000"
