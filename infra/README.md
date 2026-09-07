# Daypencil publishing infrastructure: runbook

Static hosting on the existing DigitalOcean droplet, deploy by git pull,
content published by a Claude cloud routine, watched by GitHub Actions.
No server-side code, nothing built on the droplet, no push into the droplet.

## Placeholders

Every ALL_CAPS placeholder used anywhere under `infra/` and `.github/`:

| Placeholder | Where | Meaning |
|---|---|---|
| `OWNER` | workflows, PROMPT.md, setup script default | GitHub owner of the `daypencil` repository |
| `REPO_URL` | `infra/deploy/setup-droplet.sh` (env var) | Clone URL used by the droplet: `https://github.com/OWNER/daypencil.git` (public) or `git@github.com:OWNER/daypencil.git` (private, deploy key) |
| `ROUTINE_ID` | GitHub secret | Id of the Claude routine (from its page at claude.ai/code/routines) |
| `ROUTINE_TOKEN` | GitHub secret | Bearer token for the routine's fire endpoint |
| `OWNER_GIT_NAME`, `OWNER_GIT_EMAIL` | routine environment | Commit identity the routine uses (must be the owner's) |
| `SOURCE_n_NAME`, `SOURCE_n_FEED_URL`, `SOURCE_n_DOMAIN`, `SOURCE_n_FEED_DOMAIN`, `SOURCE_n_API_KEY` | PROMPT.md SOURCES table, routine network allowlist and environment | One allowlisted news source: display name, feed/API URL, article host, API host (if different), credential variable |
| `CERTBOT_EMAIL` | certbot, first registration only | Contact address for Let's Encrypt (omit if certbot is already registered on the box for commuteglance) |

`DATE`, `N`, `PUBLISHER` inside the JSON templates of `PROMPT.md` are values
the routine fills in at run time, not configuration.

Fixed values (not placeholders): droplet `142.93.63.8`; branches `main`
(source + `content/`), `live` (validated `main`, served), `build` (web app);
paths `/var/www/daypencil/{src,app}`; Linux user `daypencil`; certificate
`/etc/letsencrypt/live/daypencil.com/`.

## Architecture

```
                    GitHub: OWNER/daypencil
                    ┌──────────────────────────────────────────────────────┐
  owner (laptop) ──►│ main  = source + content/ + docs/ + infra/           │
                    │   │ push (non-content)      │ push (content/**)      │
                    │   ▼                         ▼                        │
                    │ build-web.yml           validate-content.yml         │
                    │  analyze/test/build      dart run tool/validate.dart │
                    │   │ force-push             │ fast-forward on green   │
                    │   ▼                         ▼                        │
                    │ build (orphan)           live                        │
                    └──────▲──────────────────────▲────────────────────────┘
                           │ git fetch/reset       │ git fetch/reset (every 5 min, daypencil-pull.timer)
                           │                       │
  Claude routine ──push──► main (content/ only)    │
  02:15 UTC daily                                  │
                    ┌──────┴───────────────────────┴───────────────────────┐
                    │ droplet 142.93.63.8  (nginx 1.24, certbot)           │
                    │  /var/www/daypencil/app         <- build             │
                    │  /var/www/daypencil/src/content <- live              │
                    │  https://daypencil.com/          -> app/ (SPA)       │
                    │  https://daypencil.com/content/  -> src/content/     │
                    └──────────────────────────────────────────────────────┘
                           ▲
  GitHub Actions ──curl────┘  edition-watch.yml: 03:10 retry, 03:45 verify, 05:00 reserve (UTC)
       │ POST /routines/ROUTINE_ID/fire (retry only)
       ▼
  Claude routine
```

Edition boundary: edition dates roll at **04:00 UTC**. The routine running at
02:15 UTC on day D upgrades edition D, which opens at 04:00 UTC the same
morning. Every file in this directory says the same thing; if you change the
boundary in `lib/core/edition_clock.dart`, change every schedule here.

Files:

| File | Purpose |
|---|---|
| `infra/nginx/daypencil-http.conf` | port 80: ACME-friendly redirect to https |
| `infra/nginx/daypencil.conf` | port 443: app + content, cache and security headers |
| `infra/systemd/daypencil-pull.{service,timer}` | fetch + hard-reset both checkouts every 5 minutes |
| `infra/deploy/setup-droplet.sh` | idempotent droplet setup, `--dry-run` supported |
| `infra/routine/PROMPT.md` | the routine's prompt, SOURCES and ENVIRONMENT |
| `.github/workflows/build-web.yml` | Flutter web build → branch `build` |
| `.github/workflows/validate-content.yml` | validator → promote `main` to `live` |
| `.github/workflows/edition-watch.yml` | retry / verify / reserve checks, owner alert |

Why `live` and not `main` on the droplet: the validator is the trust
boundary and must pass in CI before anything is served. The droplet therefore
tracks `live`, which `validate-content.yml` fast-forwards to `main` only after
a green run. To serve `main` directly instead, change `live` to `main` in
`infra/systemd/daypencil-pull.service` and in `setup-droplet.sh`.

## One-time setup

Order matters: 3 needs 1; 4 needs 3; 6 needs 5.

1. **Registrar DNS.** `A daypencil.com → 142.93.63.8` and
   `A www.daypencil.com → 142.93.63.8`. No AAAA record (the nginx config has
   no IPv6 listener). Check: `dig +short daypencil.com`.

2. **GitHub repository `OWNER/daypencil`.**
   * `main` unprotected (the routine pushes to it and pushes must carry only
     the owner's commits, so do not add other collaborators' commits to it).
   * Settings → Actions → General → Workflow permissions: *Read and write*
     (the workflows also declare `permissions: contents: write`).
   * Settings → Secrets and variables → Actions: `ROUTINE_ID`,
     `ROUTINE_TOKEN` (from step 5; can be added afterwards).
   * Your notification settings: Actions → *Send notifications for failed
     workflows only*, by email. A failed scheduled run notifies the user who
     last committed the workflow file, so `edition-watch.yml` must have been
     last committed by you.
   * Push this repository. `build-web` runs and creates `build`. Run
     `validate-content` once from the Actions tab (workflow_dispatch) to create
     `live`; it needs `content/` to be valid, so do this after the first
     reserve is generated (step 6).

3. **Droplet.** As root on 142.93.63.8:

   ```
   apt-get install -y git certbot python3-certbot-nginx     # if missing; nginx is already there
   scp -r infra root@142.93.63.8:/root/daypencil-infra      # from your laptop
   REPO_URL=https://github.com/OWNER/daypencil.git bash /root/daypencil-infra/deploy/setup-droplet.sh --dry-run
   REPO_URL=https://github.com/OWNER/daypencil.git bash /root/daypencil-infra/deploy/setup-droplet.sh
   ```

   For a private repo use `REPO_URL=git@github.com:OWNER/daypencil.git`; the
   script prints a public key to add under Settings → Deploy keys (read-only).
   The script creates user `daypencil`, the two checkouts, the timer, and the
   port-80 site. It does not touch commuteglance, `nginx.conf` or the
   timezone (America/New_York; all schedules here are UTC).

4. **Certificate.** After DNS resolves:

   ```
   certbot certonly --nginx -d daypencil.com -d www.daypencil.com --deploy-hook 'systemctl reload nginx'
   bash /root/daypencil-infra/deploy/setup-droplet.sh     # re-run: enables the HTTPS site
   curl -sI https://daypencil.com/ | head -3
   ```

   Add `--email CERTBOT_EMAIL --agree-tos` only if certbot has never been
   registered on this box. `certonly` keeps certbot from rewriting the
   hand-written server blocks; renewal is automatic (`certbot renew
   --dry-run` to check).

5. **Routine.** At claude.ai/code/routines create a routine:
   * repository `OWNER/daypencil`, branch `main`;
   * schedule cron `15 2 * * *`, timezone UTC;
   * prompt: `infra/routine/PROMPT.md` below the `---` line, placeholders
     filled in;
   * network: *Custom*, with every domain listed in PROMPT.md's ENVIRONMENT;
   * environment setup script and variables as in ENVIRONMENT (Flutter SDK
     install; `SOURCE_n_API_KEY`; git identity `OWNER_GIT_NAME` /
     `OWNER_GIT_EMAIL`);
   * copy its id and API token into the GitHub secrets `ROUTINE_ID` and
     `ROUTINE_TOKEN`.
   Run it once manually and read the final status line
   (`PUBLISHED` / `NOOP` / `ABANDONED`). A green run status alone means
   nothing.

6. **First reserve.** Generate at least 90 days of classics and evergreen
   editions (see *Reserve replenishment*), validate, commit, push. Then run
   `validate-content` from the Actions tab once so `live` exists, wait 5
   minutes, and check:

   ```
   curl -s https://daypencil.com/content/index.json | jq .latest
   curl -s https://daypencil.com/content/editions/$(date -u +%F).json | jq .kind
   ```

7. **Smoke test the watch.** Actions → edition-watch → Run workflow → `verify`
   (fails until the first news edition; that is the alert path working) and
   `reserve` (must pass).

## Daily operation (UTC)

| Time | What | Where to look |
|---|---|---|
| 02:15 | routine starts (may be a few minutes late), fetches sources, writes 3 puzzles + manifest + report, validates, pushes `content: news edition D` | claude.ai/code/routines run log, final status line |
| ~02:30–03:30 | `validate-content` re-validates, fast-forwards `live`; droplet pulls within 5 min | Actions tab; `journalctl -u daypencil-pull` |
| 03:10 | `retry`: if the served manifest is still evergreen, fires the routine again (job succeeds) | Actions → edition-watch |
| 03:45 | `verify`: still evergreen → job fails → email. 404 → `FALLBACK MISSING` | email; Actions → edition-watch |
| 04:00 | edition D opens (news if upgraded, evergreen otherwise) | `curl …/editions/D.json \| jq .kind` |
| 05:00 | `reserve`: fails if `index.json.latest` < D + 30 days or D+1's file is missing | email; Actions → edition-watch |
| any time | app deploy: push to `main` outside `content/` → `build-web` → `build` → droplet | Actions → build-web |

Nothing needs attention on a normal day. An evergreen day is not an incident;
two in a row is.

## Rollback

**Content (before 04:00 UTC, or anything not yet open):**

```
git revert <sha> && git push origin main      # validate-content → live → droplet, ≤ ~10 min total
```

**Content already open (after 04:00 UTC):** do not revert; published puzzle
identities are frozen. Use a correction (next section).

**App:** either revert the source commit on `main` (rebuild takes ~10 min), or
go to Actions → build-web → the last good run → *Re-run all jobs*, which
rebuilds that commit and force-pushes it to `build` without touching `main`.

**Emergency, on the droplet** (bypasses CI; use only when GitHub or CI is
down). Run git as the `daypencil` user or git refuses with "dubious
ownership":

```
systemctl stop daypencil-pull.timer
runuser -u daypencil -- git -C /var/www/daypencil/src fetch --depth 50 origin <sha>
runuser -u daypencil -- git -C /var/www/daypencil/src reset --hard <sha>
# ... fix main / CI ...
systemctl start daypencil-pull.timer         # next pull re-syncs to live
```

Same pattern with `/var/www/daypencil/app` and a `build` commit sha.

## Correcting a puzzle

Puzzle files are immutable; a correction is a new version with a new id.

1. Copy `content/puzzles/<game>-<date>-en-vN.json` to `…-v(N+1).json`, fix
   it, set `contentVersion` to N+1 (and the `id`). Never edit or delete the
   old file: existing share links point at it.
2. In `content/editions/<date>.json` replace the id in `puzzles`, increment
   `version`, and add `"correctionNote": "…"` (one sentence, shown to
   players).
3. `dart run tool/validate.dart content`, then commit
   `content: correction <new id>` and push `main`. Live within ~10 minutes.

## Reserve replenishment

Target: `index.json.latest` at least 30 days ahead at all times (the 05:00
UTC job alerts below that); generate 90 days at a time.

```
dart run tool/gen_word.dart      …    # classic generators, one per game; see each tool's --help
dart run tool/gen_sudoku.dart    …    # for the date range flags
dart run tool/gen_letters.dart   …
dart run tool/gen_crossword.dart …
dart run tool/build_content.dart      # stamps evergreen editions (content_src/evergreen) onto
                                      # every date that has classics but no manifest, writes index.json
dart run tool/validate.dart content
git add content && git commit -m "content: reserve to <last date>" && git push origin main
```

Generators are deterministic per date, so re-running for an existing date
reproduces the same file. `content_src/evergreen/` templates and the
crossword clue bank need occasional additions so evergreen days and clues do
not repeat; that is editorial work, reviewed before it enters the bank.

The bundled starter content in `assets/content/` is a subset of `content/`
and only changes with an app build; keep it to a few recent dates.

## When edition-watch fails

| Failure | Meaning | Check, in order |
|---|---|---|
| `verify`: still evergreen | the routine did not publish, CI rejected it, or the droplet did not pull | 1. routine run log: last status line (`ABANDONED …` gives the reason; no run at all → usage limits or schedule) 2. Actions → validate-content: red run → validator errors on `main`; `live` was not advanced, site still serves last good content; fix or `git revert` 3. `journalctl -u daypencil-pull -n 30` on the droplet; `systemctl list-timers` 4. `content/reports/<date>.md` on `main` |
| `verify`: `FALLBACK MISSING` | no manifest for today at all; the app shows the latest older edition | replenish the reserve now; check `index.json`; check the droplet actually has `live` checked out |
| `verify`: other HTTP code | site down | `systemctl status nginx`, `nginx -t`, `certbot certificates`, DNS, droplet reachable? |
| `retry` failed | fire call rejected | secrets `ROUTINE_ID`/`ROUTINE_TOKEN` missing or rotated; API error body in the log (usage limits) |
| `reserve`: reserve low | fewer than 30 days published ahead | replenish |
| `reserve`: fallback missing for tomorrow | date gap in the reserve | replenish; run the validator (it should have caught a gap: ask why it did not) |
| workflow did not run at all | schedules disabled after 60 days of inactivity, or the workflow file was last committed by someone else | Actions tab → enable; commit the file yourself |

The routine cannot reach the droplet and never needs to; every fix is a
commit to `main` or a command on the droplet.

## Operator checklist

Monthly:
* Droplet: `apt-get update && apt-get upgrade`, reboot if the kernel changed
  (the timer's `Persistent=true` catches up). `certbot renew --dry-run`.
  `df -h`, `du -sh /var/www/daypencil` (git objects grow with every build;
  `runuser -u daypencil -- git -C /var/www/daypencil/app gc --prune=now` if
  large).
* Read the last few `content/reports/*.md`: source failures, rejected
  candidates, validator retries. A source that fails three days running
  needs attention (*source-access changes*).
* Actions tab: any red `validate-content` or `build-web` runs.

Quarterly:
* **Dependency updates.** `flutter pub outdated`; Flutter version pin
  (`3.41.x`) in both workflows and in PROMPT.md's setup script move
  together; `actions/checkout`, `subosito/flutter-action`,
  `peaceiris/actions-gh-pages` majors; nginx/certbot via apt.
* **Source-access changes.** API keys expiring, terms changing, feed URLs
  moving: update the SOURCES table in PROMPT.md, the routine's network
  allowlist and environment variables together. Keep the record of what each
  source permits (retrieve, retain, display attributed excerpts) next to the
  table.
* **Content-bank replenishment.** Reserve ≥ 90 days; new evergreen templates;
  new reviewed crossword clues; dictionary version bump only with a new
  `dictionaryVersion` string (old puzzles keep theirs).
* **Platform compatibility.** After a Flutter upgrade: `flutter build web`
  locally, load the site in iOS Safari and Android Chrome, check
  `flutter_bootstrap.js` / `index.html` are still the entry points assumed
  by `infra/nginx/daypencil.conf`, check nothing in the build output is
  content-hashed (if Flutter starts hashing assets, the app cache policy can
  become `immutable` for those files).

Yearly:
* **Domain renewal.** `daypencil.com` at the registrar; enable auto-renew.
  Registrar account email must be one you read.
* Rotate `ROUTINE_TOKEN` and any `SOURCE_n_API_KEY`; update GitHub secrets and
  the routine environment.
* Re-read `docs/daypencil-concept-and-implementation.md` "Release
  requirements" against the live site.
