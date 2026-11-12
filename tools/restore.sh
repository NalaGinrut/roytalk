#!/bin/bash
# roytalk -- restore a dump made by tools/backup.sh
#
#   tools/restore.sh                  newest file in prv/asset-private/roytalk/backup/
#   tools/restore.sh FILE.sql.bz2     a given file
#
# The dump drops and recreates every object it contains, so it works on an
# empty database (a new VM after deploy/setup-server.sh) and on a live one.
# It runs as ONE transaction: if anything fails, nothing is changed.
# Before restoring, the current database is saved as
#   <db>-prerestore-<time>.sql.bz2
# in the same directory (skip with NO_SNAPSHOT=1), and never picked by default.
# Stop the site first on a live server:
#   sudo systemctl stop roytalk-web roytalk-mailer
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$APP_DIR/conf/artanis.conf"
BACKUP_DIR="${BACKUP_DIR:-$APP_DIR/prv/asset-private/roytalk/backup}"

conf() { sed -n "s/^$1 = //p" "$CONF" | head -1; }
DB_NAME=$(conf db.name)
DB_USER=$(conf db.username)
DB_ADDR=$(conf db.addr)
export PGPASSWORD=$(conf db.passwd)

# Newest regular dump; pre-restore snapshots are only used when named.
FILE=${1:-$(ls -1 "$BACKUP_DIR"/"$DB_NAME"-2*.sql.bz2 2>/dev/null | sort | tail -1)}
[ -n "$FILE" ] && [ -f "$FILE" ] || { echo "no backup found in $BACKUP_DIR" >&2; exit 1; }

bzip2 -t "$FILE"
if [ "${NO_SNAPSHOT:-0}" != 1 ]; then
  echo "Saving the current database first"
  LABEL=prerestore BACKUP_DIR="$BACKUP_DIR" "$APP_DIR/tools/backup.sh"
fi
echo "Restoring $FILE into $DB_NAME"
bunzip2 -c "$FILE" | psql --quiet --set ON_ERROR_STOP=1 --single-transaction \
  --host="${DB_ADDR%:*}" --port="${DB_ADDR##*:}" --username="$DB_USER" "$DB_NAME"
echo "Done."
