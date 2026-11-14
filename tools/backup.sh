#!/bin/bash
# roytalk -- dump the database and uploaded images to
# prv/asset-private/roytalk/backup/, as a paired .sql.bz2 and -uploads.tar.bz2
#
# prv/asset-private/ is expected to be an rclone mount of the private R2
# bucket; to this script it is just a directory. Nothing is encrypted.
#
# Run from anywhere; it finds the app directory from its own path and reads
# the database settings from conf/artanis.conf (the one place they live).
# Run by roytalk-backup.timer every day; safe to run by hand:
#   tools/backup.sh
#
# Environment (all optional):
#   BACKUP_DIR   where to put the dumps   (default prv/asset-private/roytalk/backup)
#   KEEP_DAYS    delete dumps older than this many days; unset or 0 keeps all
#   LABEL        added to the file name, e.g. "prerestore" (used by restore.sh)
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$APP_DIR/conf/artanis.conf"
BACKUP_DIR="${BACKUP_DIR:-$APP_DIR/prv/asset-private/roytalk/backup}"
KEEP_DAYS="${KEEP_DAYS:-0}"

conf() { sed -n "s/^$1 = //p" "$CONF" | head -1; }
DB_NAME=$(conf db.name)
DB_USER=$(conf db.username)
DB_ADDR=$(conf db.addr)
DB_HOST=${DB_ADDR%:*}
DB_PORT=${DB_ADDR##*:}
export PGPASSWORD=$(conf db.passwd)

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME="$DB_NAME-${LABEL:+$LABEL-}$STAMP.sql.bz2"
UNAME="$DB_NAME-${LABEL:+$LABEL-}$STAMP-uploads.tar.bz2"
UPLOAD_DIR="$APP_DIR/pub/img/upload"

# Build and check the archive locally first, so a half-written file never
# lands in the mount (an upload of a broken dump would look like a backup).
WORK=$(mktemp -d "${TMPDIR:-/var/tmp}/roytalk-backup.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Plain SQL with DROP ... IF EXISTS first, so it restores into an empty or an
# existing database alike: bunzip2 -c FILE | psql. No owners or grants, so it
# also restores under another role name.
# Extensions (citext) are left alone on restore: an extension created by the
# superuser can't be dropped or commented on by the app's role, and CREATE
# EXTENSION IF NOT EXISTS in the dump is enough on a new database.
pg_dump --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" \
        --no-owner --no-privileges --clean --if-exists \
        "$DB_NAME" \
  | sed -e '/^DROP EXTENSION /d' -e '/^COMMENT ON EXTENSION /d' \
  | bzip2 -9 > "$WORK/$NAME"

bzip2 -t "$WORK/$NAME"
# A dump that ends early is still valid bzip2: check pg_dump finished.
bunzip2 -c "$WORK/$NAME" | tail -n 5 | grep -q "PostgreSQL database dump complete"

# The database was dumped first, so every image it references already existed
# when this tar runs. Uploads after the dump are harmless extras.
mkdir -p "$UPLOAD_DIR"
tar -C "$APP_DIR/pub/img" -cf - upload | bzip2 -9 > "$WORK/$UNAME"
bzip2 -t "$WORK/$UNAME"
tar -tjf "$WORK/$UNAME" > /dev/null

mkdir -p "$BACKUP_DIR"
# Copy under a temporary name, then rename, so readers of the directory
# (and rclone) never see a partial file under the final name.
for F in "$NAME" "$UNAME"; do
  cp "$WORK/$F" "$BACKUP_DIR/.$F.partial"
  mv "$BACKUP_DIR/.$F.partial" "$BACKUP_DIR/$F"
done

if [ "$KEEP_DAYS" -gt 0 ] 2>/dev/null; then
  find "$BACKUP_DIR" -maxdepth 1 \
    \( -name "$DB_NAME-*.sql.bz2" -o -name "$DB_NAME-*-uploads.tar.bz2" \) \
    -mtime +"$KEEP_DAYS" -delete
fi

echo "backup: $BACKUP_DIR/$NAME ($(du -h "$BACKUP_DIR/$NAME" | cut -f1))"
echo "backup: $BACKUP_DIR/$UNAME ($(du -h "$BACKUP_DIR/$UNAME" | cut -f1))"
