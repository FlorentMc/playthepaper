#!/bin/bash
# Play the Paper: refresh the served site from GitHub on the cPanel host.
# Run by a cPanel cron job every 5 minutes (see infra/README.md).
#
#   $HOME/repos/playthepaper-live   <- branch `live`  (main after validate-content passed)
#   $HOME/repos/playthepaper-build  <- branch `build` (Flutter web build, force-pushed by build-web)
#   $HOME/play.commuteglance.com    <- document root: build output + content/ + .htaccess
#
# Nothing is built here: clone if missing, fetch, hard-reset, rsync into the
# document root, done. Content goes first, the app second. The copy only runs
# when a branch moved (or PLAYTHEPAPER_FORCE=1), so a quiet run costs two
# fetches and prints nothing.
#
# Edition boundary: edition dates roll at 04:00 UTC. The nightly news upgrade
# for edition date D reaches `live` around 02:30-03:30 UTC on D and must be
# on disk before 04:00 UTC; the 5-minute cadence is assumed by the 03:10 /
# 03:45 UTC checks in .github/workflows/edition-watch.yml.
#
# Environment overrides (set them on the cron line if the defaults change):
#   PLAYTHEPAPER_REPO_URL  clone URL; for a private repo use
#                          https://x-access-token:TOKEN@github.com/FlorentMc/playthepaper.git
#   PLAYTHEPAPER_DOCROOT   document root of the subdomain
#   PLAYTHEPAPER_FORCE=1   copy even if nothing moved (repairs a damaged docroot)
#
# The whole script is one function called on the last line, so bash has parsed
# all of it before the git reset below replaces this very file.

set -euo pipefail

main() {
  local home=${HOME:?HOME is not set}
  local repo_url=${PLAYTHEPAPER_REPO_URL:-https://github.com/FlorentMc/playthepaper.git}
  local docroot=${PLAYTHEPAPER_DOCROOT:-$home/play.commuteglance.com}
  local live=$home/repos/playthepaper-live
  local build=$home/repos/playthepaper-build
  local state=$home/repos/.playthepaper-pull.state
  local lock=$home/repos/.playthepaper-pull.lock
  local git rsync
  git=$(command -v git || true)
  [ -n "$git" ] || git=/usr/local/cpanel/3rdparty/bin/git
  [ -x "$git" ] || { echo "$(stamp) ERROR: git not found"; exit 1; }
  rsync=$(command -v rsync || true)
  [ -n "$rsync" ] || { echo "$(stamp) ERROR: rsync not found (ask hosting support to enable it)"; exit 1; }
  export GIT_TERMINAL_PROMPT=0

  mkdir -p "$home/repos" "$home/logs"
  exec 9>"$lock"
  if command -v flock >/dev/null 2>&1; then
    flock -n 9 || { echo "$(stamp) another pull is still running, skipping"; exit 0; }
  fi

  refresh "$git" "$live" live "$repo_url"
  refresh "$git" "$build" build "$repo_url"

  local live_sha build_sha now
  live_sha=$("$git" -C "$live" rev-parse --short HEAD)
  build_sha=$("$git" -C "$build" rev-parse --short HEAD)
  now="live=$live_sha build=$build_sha"
  if [ "${PLAYTHEPAPER_FORCE:-0}" != "1" ] && [ -f "$state" ] && [ "$(cat "$state")" = "$now" ] \
     && [ -f "$docroot/.htaccess" ] && [ -f "$docroot/content/index.json" ] && [ -f "$docroot/index.html" ]; then
    exit 0
  fi

  mkdir -p "$docroot/content"
  # Content first. reports/ is for the operator (repo only), never served.
  "$rsync" -a --delete --exclude 'reports/' "$live/content/" "$docroot/content/"
  # Then the app. The build checkout is the whole docroot minus what we own.
  "$rsync" -a --delete --exclude '.git' --exclude 'content/' --exclude '.htaccess' "$build/" "$docroot/"
  install -m 644 "$live/infra/cpanel/htaccess" "$docroot/.htaccess"
  echo "$now" > "$state"
  echo "$(stamp) synced $now -> $docroot"
}

# refresh GIT DIR BRANCH URL: shallow clone if missing, else fetch + hard reset.
refresh() {
  local git=$1 dir=$2 branch=$3 url=$4
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    "$git" clone -q --depth 50 --single-branch --branch "$branch" "$url" "$dir"
    echo "$(stamp) cloned $branch into $dir"
    return
  fi
  "$git" -C "$dir" fetch -q --depth 50 origin "$branch"
  "$git" -C "$dir" reset -q --hard "origin/$branch"
  "$git" -C "$dir" clean -qfd
}

stamp() { date -u +%FT%TZ; }

main "$@"
