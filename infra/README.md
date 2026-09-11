# Play the Paper publishing infrastructure: runbook

Static hosting on the existing commuteglance.com cPanel shared hosting
(hosting.com, LiteSpeed) as the subdomain **play.commuteglance.com**, deploy by
git pull from a cron job, content published by a Claude cloud routine, watched
by GitHub Actions. No server-side code, nothing built on the host, no push
into the host, nothing touching the commuteglance site or the API droplet.

## Placeholders

Every ALL_CAPS placeholder used anywhere under `infra/` and `.github/`:

| Placeholder | Where | Meaning |
|---|---|---|
| `ROUTINE_ID` | GitHub secret (optional) | Id of the Claude routine (from its page at claude.ai/code/routines); enables the 03:10 retry |
| `ROUTINE_TOKEN` | GitHub secret (optional) | Bearer token for the routine's fire endpoint |
| `SOURCE_n_API_KEY` | PROMPT.md SOURCES (only if a keyed source is ever added) | Credential variable in the routine environment; none today |

`DATE`, `N`, `PUBLISHER` inside the JSON templates of `PROMPT.md` are values
the routine fills in at run time, not configuration.

Fixed values (not placeholders): GitHub repository `FlorentMc/playthepaper`
(public; the host clones it anonymously); branches `main` (source +
`content/`), `live` (validated `main`, served), `build` (web app); site
`https://play.commuteglance.com` (`lib/core/site.dart`); cPanel account home
`/home/faqgolf`, document root `/home/faqgolf/play.commuteglance.com`,
checkouts under `/home/faqgolf/repos/`, log `/home/faqgolf/logs/playthepaper-pull.log`.

## Architecture

```
                    GitHub: FlorentMc/playthepaper
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
                           │ git fetch/reset       │ git fetch/reset (every 5 min, cron -> infra/cpanel/pull.sh)
                           │                       │
  Claude routine ──push──► main (content/ only)    │
  02:15 UTC daily                                  │
                    ┌──────┴───────────────────────┴───────────────────────┐
                    │ cPanel host (LiteSpeed, AutoSSL)                     │
                    │  ~/repos/playthepaper-build  <- build                │
                    │  ~/repos/playthepaper-live   <- live                 │
                    │  ~/play.commuteglance.com/   <- rsync of both + .htaccess
                    │  https://play.commuteglance.com/          app (SPA)  │
                    │  https://play.commuteglance.com/content/  content    │
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
| `infra/cpanel/pull.sh` | cron script: clone/fetch `live` and `build`, rsync into the document root, install `.htaccess` |
| `infra/cpanel/htaccess` | LiteSpeed/Apache rules: https, share-page routing, app fallback, cache and security headers |
| `infra/routine/PROMPT.md` | the routine's prompt, SOURCES and ENVIRONMENT |
| `.github/workflows/build-web.yml` | Flutter web build → branch `build` |
| `.github/workflows/validate-content.yml` | validator → promote `main` to `live` |
| `.github/workflows/edition-watch.yml` | retry / verify / reserve checks, owner alert |

Why `live` and not `main` on the host: the validator is the trust boundary
and must pass in CI before anything is served. The host therefore tracks
`live`, which `validate-content.yml` fast-forwards to `main` only after a
green run. To serve `main` directly instead, change `live` to `main` in
`infra/cpanel/pull.sh`.

Why rsync into the document root rather than serving the checkouts: cPanel
gives one document root per subdomain and no per-path aliases, and the
checkouts contain `.git`. `pull.sh` copies the build output and `content/`
(minus `reports/`) into the document root; `.htaccess` refuses dotfiles as a
second line of defence.

## One-time setup

Order matters: 2 needs 1; 4 needs 2 and 3.

1. **Subdomain.** cPanel → Domains → Create a New Domain →
   `play.commuteglance.com`, *Share document root* unchecked, document root
   `play.commuteglance.com`. This also creates the DNS record (the zone is
   hosted at hosting.com). AutoSSL issues the certificate on its own within
   the hour; cPanel → SSL/TLS Status → *Run AutoSSL* to hurry it. Check:
   `dig +short play.commuteglance.com` and
   `curl -sI https://play.commuteglance.com/ | head -1`.

2. **GitHub repository `FlorentMc/playthepaper`**, public.
   * `main` unprotected (the routine pushes to it and pushes must carry only
     the owner's commits, so do not add other collaborators' commits to it).
   * The Claude GitHub App installed on the repository (github.com/apps/claude
     → Configure → select `playthepaper`), otherwise the routine's push is
     refused with 403. Its commits are authored `Claude <noreply@anthropic.com>`.
   * Settings → Actions → General → Workflow permissions: *Read and write*
     (the workflows also declare `permissions: contents: write`).
   * Settings → Secrets and variables → Actions: `ROUTINE_ID`,
     `ROUTINE_TOKEN` (optional, from step 5).
   * Your notification settings: Actions → *Send notifications for failed
     workflows only*, by email. A failed scheduled run notifies the user who
     last committed the workflow file, so `edition-watch.yml` must have been
     last committed by you.
   * Push this repository. `build-web` runs and creates `build`. Run
     `validate-content` once from the Actions tab (workflow_dispatch) to create
     `live`.

3. **Cron job on the host.** cPanel → Cron Jobs → Add New Cron Job, every
   5 minutes (`*/5 * * * *`), command:

   ```
   /bin/bash -c 'd=$HOME/repos/playthepaper-live; mkdir -p $HOME/logs; [ -d "$d/.git" ] || git clone -q --depth 50 --single-branch --branch live https://github.com/FlorentMc/playthepaper.git "$d"; bash "$d/infra/cpanel/pull.sh"' >> $HOME/logs/playthepaper-pull.log 2>&1
   ```

   The command bootstraps itself: the first run clones `live`, then runs
   `pull.sh` from it, which clones `build` and fills the document root.
   Until `live` and `build` exist on GitHub the log shows a clone error every
   5 minutes; that is harmless. Leave cPanel's email-on-output setting off
   (the script prints only when something changed) or point it at yourself.
   For a private repository set `PLAYTHEPAPER_REPO_URL` with a token on the
   cron line (see the header of `pull.sh`).

4. **First deploy check**, about 10 minutes after `live` and `build` exist:

   ```
   curl -sI https://play.commuteglance.com/ | grep -i 'HTTP/\|cache-control'
   curl -s https://play.commuteglance.com/content/index.json | jq .latest
   curl -s https://play.commuteglance.com/content/editions/$(date -u +%F).json | jq .kind
   curl -sI https://play.commuteglance.com/p/$(curl -s https://play.commuteglance.com/content/editions/$(date -u +%F).json | jq -r '.puzzles.word') | head -1
   ```

   and `tail ~/logs/playthepaper-pull.log` in cPanel → Terminal (or File
   Manager). A wrong `.htaccess` shows as HTTP 500 on every path: fix it on
   `main`, the next pull replaces it.

5. **Routine.** Created from this machine with the routine API (or by hand
   at claude.ai/code/routines) with:
   * repository `FlorentMc/playthepaper`, branch `main`;
   * schedule cron `15 2 * * *`, timezone UTC; model Opus;
   * prompt: `infra/routine/PROMPT.md` below the `---` line, verbatim;
   * tools Bash, Read, Write, Edit, Glob, Grep;
   * the environment's network access set to *Full*, or *Custom* with the
     hosts listed in PROMPT.md's ENVIRONMENT. No variables, no secrets, no
     setup script: `infra/routine/bootstrap.sh` installs the toolchain in
     the run.
   Test it with a manual run whose payload is `Publish edition <tomorrow>`
   and read the final status line (`PUBLISHED` / `NOOP` / `ABANDONED`). A
   green run status alone means nothing.
   Optional: on the routine's page create its API token and store it with
   the routine id as the GitHub secrets `ROUTINE_TOKEN` / `ROUTINE_ID`; that
   enables the 03:10 UTC retry. Without them the retry job only logs a
   warning.

6. **Reserve.** `content/` already holds classics to 2026-12-31 and the
   optional games to 2026-10-31 (see *Reserve replenishment* to extend).
   After `validate-content` has run once, check step 4 again.

7. **Smoke test the watch.** Actions → edition-watch → Run workflow → `verify`
   (fails until the first news edition; that is the alert path working) and
   `reserve` (must pass).

## Daily operation (UTC)

| Time | What | Where to look |
|---|---|---|
| 02:15 | routine starts (may be a few minutes late), fetches sources, writes `content_src/news/D.json` (stories, five quiz questions, seed words), runs `build_content --date D --news` and the validator, pushes `content: news edition D` | claude.ai/code/routines run log, final status line |
| ~02:30–03:30 | `validate-content` re-validates, fast-forwards `live`; the host pulls within 5 min | Actions tab; `~/logs/playthepaper-pull.log` |
| 03:10 | `retry`: if the served manifest is still evergreen, fires the routine again (job succeeds) | Actions → edition-watch |
| 03:45 | `verify`: still evergreen → job fails → email. 404 → `FALLBACK MISSING` | email; Actions → edition-watch |
| 04:00 | edition D opens (news if upgraded, evergreen otherwise) | `curl …/editions/D.json \| jq .kind` |
| 05:00 | `reserve`: fails if `index.json.latest` < D + 30 days or D+1's file is missing | email; Actions → edition-watch |
| any time | app deploy: push to `main` outside `content/` → `build-web` → `build` → host | Actions → build-web |

Nothing needs attention on a normal day. An evergreen day is not an incident;
two in a row is.

## Rollback

**Content (before 04:00 UTC, or anything not yet open):**

```
git revert <sha> && git push origin main      # validate-content → live → host, ≤ ~10 min total
```

**Content already open (after 04:00 UTC):** do not revert; published puzzle
identities are frozen. Use a correction (next section).

**App:** either revert the source commit on `main` (rebuild takes ~10 min), or
go to Actions → build-web → the last good run → *Re-run all jobs*, which
rebuilds that commit and force-pushes it to `build` without touching `main`.

**Emergency, on the host** (bypasses CI; use only when GitHub or CI is
down). In cPanel → Terminal:

```
crontab -l                      # note the pull line, then remove it with crontab -e (or pause it in Cron Jobs)
cd ~/repos/playthepaper-live && git fetch --depth 50 origin <sha> && git reset --hard <sha>
PLAYTHEPAPER_FORCE=1 bash ~/repos/playthepaper-live/infra/cpanel/pull.sh   # copies that checkout into the document root
# ... fix main / CI ...; restore the cron line: the next pull re-syncs to live
```

Same pattern with `~/repos/playthepaper-build` and a `build` commit sha.

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
dart run tool/gen_sudoku.dart --from <first> --to <last> --out content/puzzles   # sudoku is unseeded
dart run tool/build_content.dart --from <first> --to <last>   # per date: picks the evergreen template by
                                                              # rotation (or content_src/news/<date>.json if
                                                              # present), generates the seeded Daily Word,
                                                              # Letters and Mini Crossword, writes the quiz,
                                                              # the manifest with its seeds map, share pages
                                                              # and index.json
dart run tool/validate.dart content
git add content && git commit -m "content: reserve to <last date>" && git push origin main
```

Generation is deterministic per date and template, so re-running for an
existing date reproduces the same file; when a template changes, the builder
writes a new version of each affected puzzle rather than overwriting. `content_src/evergreen/` templates and the
crossword clue bank need occasional additions so evergreen days and clues do
not repeat; that is editorial work, reviewed before it enters the bank.

The optional games (logic, play, editorial) have their own reserves and
window; see `docs/content-and-rights.md` and `kOptionalGamesTo` in
`tool/build_content.dart`.

The bundled starter content in `assets/content/` is a subset of `content/`
and only changes with an app build; keep it to a few recent dates.

## When edition-watch fails

| Failure | Meaning | Check, in order |
|---|---|---|
| `verify`: still evergreen | the routine did not publish, CI rejected it, or the host did not pull | 1. routine run log: last status line (`ABANDONED …` gives the reason; no run at all → usage limits or schedule) 2. Actions → validate-content: red run → validator errors on `main`; `live` was not advanced, site still serves last good content; fix or `git revert` 3. `tail -50 ~/logs/playthepaper-pull.log` on the host; cPanel → Cron Jobs: is the line still there? 4. `content/reports/<date>.md` on `main` |
| `verify`: `FALLBACK MISSING` | no manifest for today at all; the app shows the latest older edition | replenish the reserve now; check `index.json`; check the host actually has `live` checked out (`~/repos/playthepaper-live`) |
| `verify`: other HTTP code | site down | HTTP 500 on every path → `.htaccess` broken (fix on `main`); certificate → cPanel SSL/TLS Status; otherwise hosting.com status page and support |
| `retry` failed | fire call rejected | secrets `ROUTINE_ID`/`ROUTINE_TOKEN` rotated (missing ones only warn); API error body in the log (usage limits) |
| `reserve`: reserve low | fewer than 30 days published ahead | replenish |
| `reserve`: fallback missing for tomorrow | date gap in the reserve | replenish; run the validator (it should have caught a gap: ask why it did not) |
| workflow did not run at all | schedules disabled after 60 days of inactivity, or the workflow file was last committed by someone else | Actions tab → enable; commit the file yourself |

The routine cannot reach the host and never needs to; every fix is a
commit to `main` or a command in cPanel's Terminal.

## Operator checklist

Monthly:
* Host: `tail ~/logs/playthepaper-pull.log`; `du -sh ~/repos ~/play.commuteglance.com`
  (git objects grow with every build; `git -C ~/repos/playthepaper-build gc --prune=now`
  if large, or delete the checkout: the next pull re-clones it). Truncate the
  log when it passes a few MB.
* Read the last few `content/reports/*.md`: source failures, rejected
  candidates, validator retries. A source that fails three days running
  needs attention (*source-access changes*).
* Actions tab: any red `validate-content` or `build-web` runs.

Quarterly:
* **Dependency updates.** `flutter pub outdated`; Flutter version pin
  (`3.41.x`) in both workflows and in PROMPT.md's setup script move
  together; `actions/checkout`, `subosito/flutter-action`,
  `peaceiris/actions-gh-pages` majors.
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
  by `infra/cpanel/htaccess`, check nothing in the build output is
  content-hashed (if Flutter starts hashing assets, the app cache policy can
  become `immutable` for those files).

Yearly:
* **Domain and hosting renewal.** `commuteglance.com` and the cPanel plan at
  hosting.com; enable auto-renew. If the site ever moves to its own domain:
  `lib/core/site.dart`, the Android app-links host, `CONTENT_URL` in
  `edition-watch.yml`, the cron command and `pull.sh` defaults, regenerate
  `content/share/`, and keep a redirect on the old host for shared links.
* Rotate `ROUTINE_TOKEN` and any `SOURCE_n_API_KEY`; update GitHub secrets and
  the routine environment.
* Re-read `docs/playthepaper-concept-and-implementation.md` "Release
  requirements" against the live site.
