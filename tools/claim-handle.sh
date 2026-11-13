#!/bin/bash
# roytalk -- give an existing account a reserved handle (the owner's @roy).
#
#   tools/claim-handle.sh                  roy@hardenedlinux.org -> roy
#   tools/claim-handle.sh EMAIL HANDLE     any account -> any handle
#
# Reserved handles (see *reserved* in lib/roytalk/util.scm) can never be
# picked at /welcome, so the owner claims one here, out of band. The account
# must already exist: sign in once with EMAIL first, then run this.
#
# It only rewrites accounts.handle. It refuses to touch an account that is not
# an author (author-emails in prv/settings.scm) and refuses to take a handle
# that belongs to another account.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$APP_DIR/conf/artanis.conf"

conf() { sed -n "s/^$1 = //p" "$CONF" | head -1; }
DB_NAME=$(conf db.name)
DB_USER=$(conf db.username)
DB_ADDR=$(conf db.addr)
DB_HOST=${DB_ADDR%:*}
DB_PORT=${DB_ADDR##*:}
export PGPASSWORD=$(conf db.passwd)

EMAIL=${1:-roy@hardenedlinux.org}
HANDLE=${2:-roy}

db() {
  psql --quiet --no-psqlrc --set ON_ERROR_STOP=1 \
       --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" "$DB_NAME" \
       -tA -v email="$EMAIL" -v handle="$HANDLE" "$@"
}

row=$(db <<'SQL'
SELECT a.id || '|' || coalesce(a.handle::text, '') || '|' || a.is_author
  FROM identities i JOIN accounts a ON a.id = i.account_id
 WHERE i.email = :'email'::citext
 ORDER BY i.id LIMIT 1;
SQL
)

if [ -z "$row" ]; then
  echo "No account signs in with $EMAIL. Sign in with that address once, then run this again." >&2
  exit 1
fi
IFS='|' read -r ID CURRENT AUTHOR <<<"$row"

if [ "$AUTHOR" != "t" ]; then
  echo "Account $ID ($EMAIL) is not an author; check author-emails in prv/settings.scm and sign in again." >&2
  exit 1
fi

if [ "$CURRENT" = "$HANDLE" ]; then
  echo "Account $ID ($EMAIL) already has the handle @$HANDLE. Nothing to do."
  exit 0
fi

taken=$(db -v id="$ID" <<'SQL'
SELECT a.id FROM accounts a
 WHERE a.handle = :'handle'::citext AND a.id <> :'id'::bigint
 LIMIT 1;
SQL
)
if [ -n "$taken" ]; then
  echo "The handle @$HANDLE already belongs to account $taken; not overwriting." >&2
  exit 1
fi

db -v id="$ID" <<'SQL'
UPDATE accounts SET handle = :'handle'::citext WHERE id = :'id'::bigint;
SQL

echo "Account $ID ($EMAIL): @${CURRENT:-(none)} -> @$HANDLE"
echo "Sign out and back in so the rt_handle cookie shows the new name."
