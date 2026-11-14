#!/bin/bash
# roytalk -- restore a dump made by tools/backup.sh
#
#   tools/restore.sh                  newest file in prv/asset-private/roytalk/backup/
#   tools/restore.sh FILE.sql.bz2     a given file
#
# The dump drops and recreates every object it contains, so it works on an
# empty database (a new VM after deploy/setup-server.sh) and on a live one.
# It runs as ONE transaction: if anything fails, nothing is changed.
# The matching <db>-...-uploads.tar.bz2 (if present) is extracted afterwards;
# set UPLOADS_FILE to point at another archive when a dump was renamed.
# Before restoring, the current database and uploads are saved as
#   <db>-prerestore-<time>.sql.bz2 and ...-uploads.tar.bz2
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
UPLOADS="${UPLOADS_FILE:-${FILE%.sql.bz2}-uploads.tar.bz2}"

bzip2 -t "$FILE"
if [ "${NO_SNAPSHOT:-0}" != 1 ]; then
  echo "Saving the current database first"
  LABEL=prerestore BACKUP_DIR="$BACKUP_DIR" "$APP_DIR/tools/backup.sh"
fi
echo "Restoring $FILE into $DB_NAME"
bunzip2 -c "$FILE" | psql --quiet --set ON_ERROR_STOP=1 --single-transaction \
  --host="${DB_ADDR%:*}" --port="${DB_ADDR##*:}" --username="$DB_USER" "$DB_NAME"

if [ -f "$UPLOADS" ]; then
  echo "Restoring images from $UPLOADS"
  bzip2 -t "$UPLOADS"
  STAGE=$(mktemp -d "${TMPDIR:-/var/tmp}/roytalk-uploads.XXXXXX")
  trap 'rm -rf "$STAGE"' EXIT
  tar -xjf "$UPLOADS" -C "$STAGE"
  mkdir -p "$APP_DIR/pub/img/upload"
  # Content-addressed names are immutable; add what is missing and leave the
  # images from before this restore in place.
  rsync -a --ignore-existing "$STAGE/upload/" "$APP_DIR/pub/img/upload/"
  rm -rf "$STAGE"
  trap - EXIT
else
  echo "no paired uploads archive for $FILE; images left as they are" >&2
fi
echo "Done."
