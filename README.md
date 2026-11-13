# roytalk

The source of **Roy on next generation software** — an essay site where readers
answer with questions, not applause. Built on [GNU Artanis](https://artanis.dev)
and PostgreSQL, rendered as plain HTML.

- Essays are written in Markdown and rendered **once, when saved**, by pandoc:
  syntax highlighting (LLVM IR, assembly, C, Scheme …) as classes, math as
  MathML. Readers get finished HTML; no script is needed to read.
- Select any sentence to question it. Hover or tap a questioned sentence to
  read the newest questions on it in a floating bubble; the full list is below
  the essay. The author can merge questions that ask the same thing, which
  groups their askers. Threads are two levels deep. No likes, no generic
  comment box.
- Sign in with GitHub, Google, X or a one-time email link. No passwords.
  An account is a handle and its sign-in methods, nothing else.
- Readers can send in links; the queue is private to the author.
- The letter (newsletter) is a separate list: double opt-in, one-click leave,
  and one digest a month with that month's writing.
- Human only: written by people. Open to every reader, machines included.

## Running it locally

Needs Guile 3, GNU Artanis (current master), guile-dbi + guile-dbd-postgresql
(master), guile-curl, guile-json, PostgreSQL 14+ and pandoc.
`deploy/setup-server.sh` shows the exact build steps.

```sh
cp prv/settings.example.scm prv/settings.scm   # set secret, author-emails,
                                               # base-url "http://127.0.0.1:3000"
# set db.passwd in conf/artanis.conf, then:
tools/init-db.sh                               # asks before changing the password
art work --refresh                # http://127.0.0.1:3000
guile -L lib tools/mailer.scm                  # another shell, with mail-mode send
guile -L lib tools/digest.scm --dry-run        # preview the monthly letter
```

`tools/init-db.sh` needs access to the local `postgres` superuser (it tries
sudo, runuser, or `PG_ADMIN_PSQL` plus the usual `PG*` variables for a remote
server). It creates the role and database named in `conf/artanis.conf`, creates
`citext`, runs the idempotent `db/schema.sql`, and applies every migration in
`db/migration/` that has not run yet, recording it in `roytalk_migrations`:
`*.sql` files, or Artanis `*.scm` files named
`<name>_<14-digit timestamp>.scm`. It is safe to re-run. Before creating a
role or changing its password it prints the `db.passwd` value and asks; pass
`--yes` to skip the question for unattended runs.

For local development set `base-url` in `prv/settings.scm` to the address you
open, e.g. `http://127.0.0.1:3000`. With an `https://` base URL, sign-in links
point at production and cookies are marked `Secure`, so they are not sent over
plain HTTP.

OAuth is optional: leave a provider's client id and secret empty and its
button disappears; email sign-in always works.

With `(mail-mode . log)` mail is written to `log/outbox/*.eml` and sign-in
links are also printed to the server log. With `(mail-mode . send)` the
mailer pipes each message to `sendmail-command` (msmtp by default, see
`deploy/msmtprc.example`). Sign in with an address listed in `author-emails`
and you are the author: the desk is at `/admin`.

## Writing

`/admin` → New piece. Markdown with `$x$` / `$$x$$` for math and fenced code
with a language name for highlighting. Tags decide what a piece is (an essay, a
commentary …). For commentary on an outside piece, fill in the source link and,
if a reader sent it in, their handle. A published piece joins the next monthly
digest automatically; nothing is sent for it on its own.

## Configuration

| Where | What |
|---|---|
| `conf/artanis.conf` | `host.name` (the domain, used for absolute URLs), port, database |
| `prv/settings.scm` | HMAC `secret`, `author-emails`, site name, OAuth client ids/secrets, mail |

OAuth callback URLs to register: `https://<host.name>/auth/{github,google,x}/callback`.
A provider without both id and secret is simply not offered.

Every page carries a canonical link, a `meta description`, Open Graph tags and,
on articles, JSON-LD `Article`; an article's description is its `dek`, or the
first 180 characters of the body. There are no per-article share images: every
page uses `pub/img/og-default.webp` (1200×630) for `og:image` and
`twitter:image`. After changing the site name or tagline, regenerate it with
`python3 tools/make-og-image.py` and commit the WebP.

## Mail

Everything goes through the `outbox` table; `tools/mailer.scm` sends it with
msmtp (`sendmail-command`), retrying with backoff. Two streams, meant for two
sending domains:

| Stream | Mails | Settings |
|---|---|---|
| `account` | sign-in link, subscription confirmation, welcome | `mail-from-account`, `ses-configuration-set-account` |
| `letter` | the monthly digest: each piece's opening, linked to the rest | `mail-from-letter`, `ses-configuration-set-letter` |

Each falls back to `mail-from`. Both streams are piped to `sendmail-command`
(msmtp with `--read-envelope-from`, so the envelope sender follows `From`);
`sendmail-command-account` / `sendmail-command-letter` override it per stream
when the two domains need different SMTP accounts (`deploy/msmtprc.example`). A configuration set, when set, goes out as the
`X-SES-CONFIGURATION-SET` header. Mail to subscribers carries `List-Unsubscribe`
and `List-Unsubscribe-Post` (one-click). Mails are multipart text + HTML; the
HTML uses tables and inline styles only, with no images, webfonts or tracking.

Templates are in `sys/mails/<name>/en.html` and `en.txt`. The front matter at
the top of the HTML sets `subject`, `preheader` and the button; `{{var}}` is
filled in (escaped in HTML). **The wording there is a draft: rewrite it.**

Submissions marked used send nothing. Thanks, if any, go in the piece.

### Monthly digest: step by step

The timer does the work. These steps deploy it, check it, and preview or send a
digest by hand. Run them on the server as root or with `sudo`.

#### 1. Deploy the code

From the repository checkout (the folder containing `deploy/setup-server.sh`):

```sh
sudo deploy/setup-server.sh
```

This is idempotent. It applies `db/schema.sql` (creating the `digests` table),
copies the new systemd units, clears the Guile compile cache, and restarts
`roytalk-web`, `roytalk-mailer` and `roytalk-digest.timer`. It does **not**
start a digest.

#### 2. Check the table

```sh
sudo -u postgres psql -d roytalk -c "SELECT to_regclass('public.digests') AS digests_table;"
```

Expected: one row, `digests`.

#### 3. Check the timer

```sh
systemctl list-timers roytalk-digest.timer --no-pager
systemctl status roytalk-digest.timer --no-pager
```

Expected: the next run is the first of the month at 08:17 UTC (shown in the
server's local time).

#### 4. Preview without writing or sending

```sh
cd /var/www/roytalk
sudo -u roytalk env LANG=C.UTF-8 XDG_CACHE_HOME=/var/lib/roytalk-guile-cache \
  guile -L lib tools/digest.scm --dry-run
```

This writes no rows and queues no mail; the preview always uses a fake
unsubscribe link. Outcomes:

| Output | Meaning |
|---|---|
| `Nothing to send.` | No published piece since the last digest is un-emailed |
| Subject, piece list, plain text | A preview; check the links |

A dry run skips the once-a-month guard and renders even when nobody is
subscribed, so it always shows what a real run would send. Check that links
point at your domain (`https://…`), not `127.0.0.1`.

#### 5. Send one by hand (optional)

```sh
sudo systemctl start roytalk-digest
sudo journalctl -u roytalk-digest -n 30 --no-pager
```

Look for `Queued N piece(s) for M recipient(s).`, `Nothing to send.` or
`No active subscribers; nothing sent.` The mails are only queued; the mailer
sends them.

#### 6. Check the queue and the digest record

```sh
sudo -u postgres psql -d roytalk -c \
  "SELECT id, to_addr, subject, sent_at IS NULL AS pending
     FROM outbox WHERE stream = 'letter' ORDER BY id DESC LIMIT 5;"

sudo -u postgres psql -d roytalk -c \
  "SELECT id, period_start, period_end, post_count, recipient_count
     FROM digests ORDER BY id DESC LIMIT 3;"
```

`pending = t` means the mailer has not sent it yet. Check the mailer:

```sh
systemctl status roytalk-mailer --no-pager
sudo journalctl -u roytalk-mailer -n 30 --no-pager
```

#### 7. See the exact message (local development)

With `(mail-mode . log)` in `prv/settings.scm`, nothing is sent; messages land
in `log/outbox/`:

```sh
guile -L lib tools/digest.scm
guile -L lib tools/mailer.scm --once
ls -l log/outbox/
```

Open the newest `.eml`. It should be `multipart/alternative`, carry both
`List-Unsubscribe` headers, and link each piece to the site. This is the safest
way to check wording and styling.

#### 8. What happens on its own

- `roytalk-digest.timer` runs on the first of each month at 08:17 UTC, with up
  to fifteen minutes of jitter.
- It takes every published piece since the previous digest's end (thirty days
  back on the first run) whose `emailed_at` is still NULL, newest first.
- In one transaction it queues one personalised copy per active subscriber,
  sets `emailed_at = now()` on the included pieces, and writes one `digests`
  row. The next run starts at that row's `period_end`, so a long month or a
  missed run cannot drop a piece; `emailed_at` prevents a second send.
- No pieces, or no active subscribers: nothing is sent and nothing is
  recorded. Pieces published later still go out with the next run.
- One digest per UTC calendar month. `--force` only bypasses that guard; it
  cannot resend pieces already marked `emailed_at`.
- The timer is not `Persistent`, so a redeploy never replays a missed run in
  the middle of a month. If the VM was off on the first, the next run covers
  the whole gap.

#### Troubleshooting

Nothing selected after publishing:

```sh
sudo -u postgres psql -d roytalk -c \
  "SELECT id, slug, status, published_at, emailed_at
     FROM posts ORDER BY published_at DESC NULLS FIRST LIMIT 10;"
```

A piece is only included when `status = 'published'`, `emailed_at IS NULL`,
and `published_at` is after the previous digest's `period_end`.

Links show `127.0.0.1`: `host.name` is missing from `conf/artanis.conf`, or the
command was not run from `/var/www/roytalk`. Fix `conf/artanis.conf` and rerun the
preview.

Old behaviour after changing library code: clear the cache and restart:

```sh
sudo rm -rf /var/lib/roytalk-guile-cache/*
sudo systemctl restart roytalk-web roytalk-mailer
```

SES notes: in a fresh region each identity starts in the sandbox; turn on the
account-level suppression list (`aws sesv2 put-account-suppression-attributes
--suppressed-reasons BOUNCE COMPLAINT`) and watch bounce and complaint rates per
region.

## Deploying

```sh
sudo deploy/setup-server.sh
```

It adds swap, builds the dependencies, tunes PostgreSQL for 1 GB, installs the
app to `/var/www/roytalk`, and starts two systemd services (`roytalk-web` and
`roytalk-mailer`) plus `roytalk-digest.timer` for the monthly letter. Backups
are user units, installed by hand (below). Running it again redeploys; it never
touches `prv/asset-private/`.

The work is split into stages, so a redeploy does not have to rebuild
everything (`sudo deploy/setup-server.sh --list` prints them):

| Stage | What |
|---|---|
| `swap` | create `/swapfile` |
| `packages` | `apt-get install` the runtime packages |
| `deps` | build guile-dbi, guile-curl, guile-redis and GNU Artanis |
| `user` | create the service account and its home (`$APP_DIR`) |
| `db` | size PostgreSQL, create the role, database and `citext` |
| `app` | copy the app to `$APP_DIR`, write `prv/settings.scm`, load the schema |
| `services` | install and (re)start the systemd units |

```sh
sudo deploy/setup-server.sh --from user      # user, db, app, services
sudo deploy/setup-server.sh --from db        # db, app, services
sudo deploy/setup-server.sh --from services  # just the systemd units
```

`--from` runs the named stage and everything after it, so `user` is the first
stage to use once the dependencies are built, and `services` the last one to
redo on its own. `APP_DIR` (default `/var/www/roytalk`) and `APP_USER`, `DB_NAME`,
`DB_USER`, `SRC` can be overridden in the environment. The units are rewritten
from `deploy/` with `$APP_DIR` substituted, so another location works without
hand-editing:

```sh
sudo APP_DIR=/var/www/roytalk deploy/setup-server.sh --from services
```

### nginx

The app speaks plain HTTP on `127.0.0.1:3000`, so nginx fronts it.
`deploy/nginx-roytalk.conf` listens on `127.0.0.1:8080`, proxies to the app,
hides the upstream `Server` header (GNU Artanis) and nginx's version, and
rate-limits per client IP — the client address comes from Cloudflare's
`CF-Connecting-IP`, which is only trusted on loopback, i.e. from cloudflared.

```sh
sudo apt-get install -y nginx
sudo install -m 644 deploy/nginx-roytalk.conf /etc/nginx/sites-available/roytalk.conf
sudo ln -sf /etc/nginx/sites-available/roytalk.conf /etc/nginx/sites-enabled/roytalk.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Then point the tunnel at it (`service: http://127.0.0.1:8080`, see
`deploy/cloudflared.yml.example`). To show the upstream banner instead of
hiding it, remove `proxy_hide_header Server;`; to send `Server: roytalk`, install
`nginx-extras` and uncomment the `more_set_headers` line.

`deploy/tune-sysctl.sh` writes and applies `/etc/sysctl.d/90-roytalk.conf`:
accept-queue and SYN backlog, keep-alive/TIME_WAIT handling, socket buffers,
flood protection, file descriptors and swap pressure. Run it once with
`sudo deploy/tune-sysctl.sh`.

Put Cloudflare in front with a tunnel (`deploy/cloudflared.yml.example`): no
inbound port is opened and only Cloudflare can reach nginx, which is what makes
the `CF-Connecting-IP` header (used for rate limits) trustworthy. Public pages
send `Cache-Control: s-maxage=60`, so Cloudflare may serve them for a minute.

**Treat the VM as disposable.** Free instances can be reclaimed. Everything
except the database is in this repository.

### Backups

`tools/backup.sh` (nightly, from the `roytalk-backup.timer` user unit) writes
`prv/asset-private/roytalk/backup/roytalk-<UTC time>.sql.bz2`: plain SQL from
`pg_dump`, bzip2, not encrypted. Each file is checked (bzip2 and a complete
dump) before it appears under its final name. `KEEP_DAYS` in the unit prunes
old ones; the default keeps everything.

`prv/asset-private/` is meant to be an rclone mount of a private R2 bucket, so
the script only does file operations. Until it is mounted, dumps stay on the
VM's disk.

The units in `deploy/systemd-user/` run under a normal user (`systemctl
--user`):

| Unit | What |
|---|---|
| `roytalk-backup.timer` | runs `roytalk-backup.service` every night at 03:17 UTC |
| `roytalk-backup.service` | runs `tools/backup.sh`, after the mount if there is one |
| `roytalk-asset-mount.service` | optional: the rclone mount of `prv/asset-private` |

The user needs to read `conf/artanis.conf` and write `prv/asset-private/`.
`setup-server.sh` gives `/var/www/roytalk` to the `roytalk` user and makes `prv/`
private (700), so the simplest is to install the units for `roytalk`:

```sh
sudo loginctl enable-linger roytalk          # user units run without a login
sudo -u roytalk mkdir -p ~roytalk/.config/systemd/user ~roytalk/.config/rclone
sudo install -o roytalk -g roytalk -m 644 deploy/systemd-user/* ~roytalk/.config/systemd/user/
sudo -u roytalk rclone config                # create the R2 remote, e.g. "r2"
# edit RCLONE_REMOTE (and ROYTALK_DIR if not /var/www/roytalk) in the units, then:
sudo systemctl start user@$(id -u roytalk)
sudo -u roytalk XDG_RUNTIME_DIR=/run/user/$(id -u roytalk) \
  systemctl --user enable --now roytalk-asset-mount roytalk-backup.timer
```

`roytalk`'s home is `/var/www/roytalk`, so these land in `/var/www/roytalk/.config/`;
redeploys leave dot directories alone and nothing outside `pub/` is served.
Under another user, give that user read access to `conf/` and write access to
`prv/asset-private/` first. Check with `systemctl --user list-timers` and
`systemctl --user start roytalk-backup` (then `journalctl --user -u roytalk-backup`).

To rebuild on a new VM: `setup-server.sh`, mount `prv/asset-private/`, then

```sh
sudo systemctl stop roytalk-web roytalk-mailer
sudo -u roytalk /var/www/roytalk/tools/restore.sh          # newest dump
sudo systemctl start roytalk-web roytalk-mailer
```

`restore.sh` runs the whole dump as one transaction (an error changes
nothing) and first saves the current database as
`roytalk-prerestore-<time>.sql.bz2`, which is never picked by default.

## Notes on GNU Artanis

Things learned building this, kept here for whoever works on it next:

- `<%= %>` must not be wrapped in quotes (`href="<%= x %>"` breaks the lexer, as
  `tpl/lexer.scm` warns). Templates use `href=<%= (qa "/posts/" slug) %>`, where
  `qa` escapes and adds the quotes.
- `<%= %>` does not escape. Everything that is not our own HTML goes through `h`.
- A connection taken with `DB-open` is returned to the pool by the
  before-response hook, which does not run when a handler throws. With
  `db.pool = fixed`, a handful of 404s thrown after a query would empty the pool
  and hang the server. `lib/roytalk/db.scm` borrows a connection per query and
  always gives it back.
- Guile drops the `#fragment` when writing `Location`; `lib/roytalk/web.scm`
  re-declares the header so a redirect can land on `#q-123`.
- `Cache-Control` and `WWW-Authenticate` need Guile's structured values, not strings.
- Artanis' static MIME table (`artanis/mime.scm`) has no `webp`, so the static
  route would send `og-default.webp` as `application/octet-stream`. `ENTRY`
  adds the type to that table at startup (it is a private hash, so this is the
  one place that reaches into Artanis internals rather than around it).
- Guile 3 inlines small procedures across modules into the caller's compiled
  `.go`. Change a library procedure without touching its callers and the
  cached callers keep running the old code. `setup-server.sh` empties the compile
  cache on every deploy; locally, start with `art work --refresh` or clear
  `~/.cache/guile` when in doubt.

## Licence

GNU General Public License v3 or later (see `COPYING`). Fonts: SIL Open Font
License 1.1 (see `pub/fonts/licenses/`).
