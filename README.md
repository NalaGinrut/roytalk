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
- The letter (newsletter) is a separate list: double opt-in, one-click leave.
- Human only: written by people. Open to every reader, machines included.

## Layout

```
ENTRY                     Artanis entry; static file types
conf/artanis.conf         Artanis config. The domain lives here only: host.name
prv/settings.example.scm  private settings (copy to prv/settings.scm, never commit)
db/schema.sql             the whole schema, idempotent; the schema authority
app/models/               one module per table; all SQL lives here
app/controllers/          index posts account letter submit admin api
app/views/<controller>/   *.html.tpl templates
app/views/shared/         partials (head, bar, footer, sponsor); not served
lib/roytalk/              util settings db web auth oauth views render mail
pub/css/                  site.css (one hand-written stylesheet), fonts.css
pub/fonts/                self-hosted woff2/woff + OFL licences
pub/js/                   site.js (readers), admin.js (the desk)
sys/mails/                mail templates: base.html/.txt + one folder per mail
tools/init-db.sh          create the role, database, schema and migrations
tools/mailer.scm          sends the outbox; a separate process
tools/backup.sh           nightly dump to prv/asset-private/roytalk/backup/*.sql.bz2
tools/restore.sh          restore a dump, in one transaction
deploy/                   server setup, systemd units
```

`app/models/` modules hold every SQL statement and are imported by
controllers and by the `lib/roytalk/` services; controllers do HTTP, checks and
rendering. They are Artanis model modules: each opens with
`(import (artanis mvc model))` and a `create-artanis-model` declaration, and
uses the generated `$model` through `(roytalk db)`'s `model-conn` /
`model-set!`. The declaration mirrors the columns; `db/schema.sql` is still
the schema authority, so run `tools/init-db.sh` before `art work` and change
schema there, not in a model. The macro's `try-create` checks
`information_schema` first and leaves an existing table alone, and it cannot
express `citext`, `timestamptz` defaults, generated `tsvector`, foreign keys,
partial indexes or checks. Keep `:deps` to one module: Artanis passes it to
`process-use-modules` as a single nested list. guile-dbd-postgresql cannot
convert `citext` result columns to Scheme ("unknown field type 16391"), so a
model function that returns one casts it to text and reads it through the
parameterised `q` helpers; writes still go through `$model`.

## Running it locally

Needs Guile 3, GNU Artanis (current master), guile-dbi + guile-dbd-postgresql
(master), guile-curl, guile-json, PostgreSQL 14+ and pandoc.
`deploy/setup-server.sh` shows the exact build steps.

```sh
cp prv/settings.example.scm prv/settings.scm   # set secret, author-emails,
                                               # base-url "http://127.0.0.1:3000"
# set db.passwd in conf/artanis.conf, then:
tools/init-db.sh                               # asks before changing the password
LANG=C.UTF-8 art work                          # http://127.0.0.1:3000
guile -L lib tools/mailer.scm                  # another shell, with mail-mode send
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
if a reader sent it in, their handle. Publish, then **Send to the letter** once.

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
| `letter` | the newsletter: a piece's opening, linked to the rest | `mail-from-letter`, `ses-configuration-set-letter` |

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

SES notes: in a fresh region each identity starts in the sandbox; turn on the
account-level suppression list (`aws sesv2 put-account-suppression-attributes
--suppressed-reasons BOUNCE COMPLAINT`) and watch bounce and complaint rates per
region.

## Deploying (Oracle Cloud Always Free, 1 GB)

```sh
sudo deploy/setup-server.sh
```

It adds swap, builds the dependencies, tunes PostgreSQL for 1 GB, installs the
app to `/srv/roytalk`, and starts two systemd services: `roytalk-web` and
`roytalk-mailer`. Backups are user units, installed by hand (below). Running
it again redeploys; it never touches `prv/asset-private/`.

Put Cloudflare in front with a tunnel (`deploy/cloudflared.yml.example`): no
inbound port is opened and only Cloudflare can reach the app, which is what makes
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
`setup-server.sh` gives `/srv/roytalk` to the `roytalk` user and makes `prv/`
private (700), so the simplest is to install the units for `roytalk`:

```sh
sudo loginctl enable-linger roytalk          # user units run without a login
sudo -u roytalk mkdir -p ~roytalk/.config/systemd/user ~roytalk/.config/rclone
sudo install -o roytalk -g roytalk -m 644 deploy/systemd-user/* ~roytalk/.config/systemd/user/
sudo -u roytalk rclone config                # create the R2 remote, e.g. "r2"
# edit RCLONE_REMOTE (and ROYTALK_DIR if not /srv/roytalk) in the units, then:
sudo systemctl start user@$(id -u roytalk)
sudo -u roytalk XDG_RUNTIME_DIR=/run/user/$(id -u roytalk) \
  systemctl --user enable --now roytalk-asset-mount roytalk-backup.timer
```

`roytalk`'s home is `/srv/roytalk`, so these land in `/srv/roytalk/.config/`;
redeploys leave dot directories alone and nothing outside `pub/` is served.
Under another user, give that user read access to `conf/` and write access to
`prv/asset-private/` first. Check with `systemctl --user list-timers` and
`systemctl --user start roytalk-backup` (then `journalctl --user -u roytalk-backup`).

To rebuild on a new VM: `setup-server.sh`, mount `prv/asset-private/`, then

```sh
sudo systemctl stop roytalk-web roytalk-mailer
sudo -u roytalk /srv/roytalk/tools/restore.sh          # newest dump
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
  cache on every deploy; do the same locally (`~/.cache/guile`) when in doubt.

## Licence

GNU General Public License v3 or later (see `COPYING`). Fonts: SIL Open Font
License 1.1 (see `pub/fonts/licenses/`).
