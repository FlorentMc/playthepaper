#!/usr/bin/env bash
# Daypencil: one-time droplet setup. Idempotent; safe to re-run. Run as root.
#
#   scp -r infra root@142.93.63.8:/root/daypencil-infra
#   ssh root@142.93.63.8 'bash /root/daypencil-infra/deploy/setup-droplet.sh --dry-run'
#   ssh root@142.93.63.8 'bash /root/daypencil-infra/deploy/setup-droplet.sh'
#
# What it does (and nothing else):
#   1. creates system user `daypencil` (nologin, home /var/www/daypencil)
#   2. creates /var/www/daypencil/{src,app} as empty git repos pointing at REPO_URL
#      (src tracks branch `live`, app tracks branch `build`; the pull unit fills them)
#   3. optional: generates a read-only SSH deploy key when REPO_URL is an ssh URL
#   4. installs daypencil-pull.service/.timer and starts the timer
#   5. installs the nginx site: the port-80 file always, the HTTPS file only
#      once /etc/letsencrypt/live/daypencil.com/ exists (re-run after certbot)
#   6. prints the DNS reminder and the certbot command
#
# It never touches the commuteglance site, /etc/nginx/nginx.conf, or the
# timezone (America/New_York stays; every schedule in this project is in UTC:
# edition dates roll at 04:00 UTC).
#
# Environment overrides:
#   REPO_URL   default https://github.com/OWNER/daypencil.git   (public repo, HTTPS, no credentials)
#              or      git@github.com:OWNER/daypencil.git       (private repo, deploy key generated here)
#   INFRA_DIR  default: the infra/ directory containing this script
#
# Flags:
#   --dry-run  print every action instead of performing it

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/OWNER/daypencil.git}"
INFRA_DIR="${INFRA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

DP_USER=daypencil
BASE=/var/www/daypencil
SRC="$BASE/src"
APP="$BASE/app"
CONTENT_BRANCH=live
APP_BRANCH=build
CERT_DIR=/etc/letsencrypt/live/daypencil.com
NGINX_AVAIL=/etc/nginx/sites-available
NGINX_ENABLED=/etc/nginx/sites-enabled
DROPLET_IP=142.93.63.8

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\n== %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# run <cmd...>: execute, or print when --dry-run.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

# as_dp <cmd...>: run as the daypencil user (works with a nologin shell).
# HOME is set explicitly so git reads ~/.gitconfig and ~/.ssh under $BASE.
as_dp() {
  run runuser -u "$DP_USER" -- env HOME="$BASE" "$@"
}

# --- preflight ---------------------------------------------------------------

[ "$(id -u)" = 0 ] || die "run as root"
command -v git    >/dev/null || die "git is not installed (apt-get install -y git)"
command -v nginx  >/dev/null || die "nginx is not installed"
command -v runuser >/dev/null || die "runuser (util-linux) missing"
[ -d "$NGINX_AVAIL" ] && [ -d "$NGINX_ENABLED" ] || die "expected Debian/Ubuntu nginx layout ($NGINX_AVAIL, $NGINX_ENABLED)"
for f in nginx/daypencil-http.conf nginx/daypencil.conf systemd/daypencil-pull.service systemd/daypencil-pull.timer; do
  [ -f "$INFRA_DIR/$f" ] || die "missing $INFRA_DIR/$f (set INFRA_DIR to the repo's infra/ directory)"
done
command -v certbot >/dev/null || warn "certbot not found; install it before requesting the certificate (apt-get install -y certbot python3-certbot-nginx)"
[ "$DRY_RUN" = 1 ] && log "DRY RUN: nothing below is executed"

# --- 1. user and directories --------------------------------------------------

log "user $DP_USER"
if id "$DP_USER" >/dev/null 2>&1; then
  echo "exists"
else
  run useradd --system --user-group --home-dir "$BASE" --no-create-home --shell /usr/sbin/nologin "$DP_USER"
fi

log "directories under $BASE"
run install -d -m 755 -o "$DP_USER" -g "$DP_USER" "$BASE" "$SRC" "$APP"

# --- 2. deploy key (ssh URLs only) -------------------------------------------

case "$REPO_URL" in
  git@*|ssh://*)
    log "ssh deploy key for $REPO_URL"
    SSH_DIR="$BASE/.ssh"
    KEY="$SSH_DIR/id_ed25519"
    run install -d -m 700 -o "$DP_USER" -g "$DP_USER" "$SSH_DIR"
    if [ -f "$KEY" ]; then
      echo "key exists: $KEY"
    else
      as_dp ssh-keygen -q -t ed25519 -N '' -C "daypencil-pull@$DROPLET_IP" -f "$KEY"
    fi
    if ! grep -qs '^github.com ' "$SSH_DIR/known_hosts"; then
      # TOFU. Compare against https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
      run bash -c "ssh-keyscan -t ed25519 github.com >> '$SSH_DIR/known_hosts'"
      run chown "$DP_USER:$DP_USER" "$SSH_DIR/known_hosts"
      run chmod 644 "$SSH_DIR/known_hosts"
    fi
    if [ -f "$KEY.pub" ]; then
      echo "Add this key to GitHub -> repo -> Settings -> Deploy keys (read-only):"
      cat "$KEY.pub"
    fi
    ;;
  https://*)
    log "HTTPS clone URL $REPO_URL (repo must be public; no credentials are stored)"
    ;;
  *)
    die "REPO_URL must start with https://, git@ or ssh://"
    ;;
esac

# --- 3. checkouts -------------------------------------------------------------
# Empty repos with a remote; the pull unit does the first fetch. This works
# whether or not the branches exist yet (e.g. before the first CI run).

init_checkout() {
  local dir=$1 branch=$2
  if [ -d "$dir/.git" ]; then
    echo "$dir: already a git repo (branch $branch)"
    as_dp git -C "$dir" remote set-url origin "$REPO_URL"
    return
  fi
  as_dp git init -q "$dir"
  as_dp git -C "$dir" symbolic-ref HEAD "refs/heads/$branch"
  as_dp git -C "$dir" remote add origin "$REPO_URL"
  as_dp git -C "$dir" config advice.detachedHead false
  as_dp git -C "$dir" config gc.auto 256
}

log "checkout $SRC (branch $CONTENT_BRANCH)"
init_checkout "$SRC" "$CONTENT_BRANCH"
log "checkout $APP (branch $APP_BRANCH)"
init_checkout "$APP" "$APP_BRANCH"

# --- 4. systemd ---------------------------------------------------------------

log "systemd units"
run install -m 644 "$INFRA_DIR/systemd/daypencil-pull.service" /etc/systemd/system/daypencil-pull.service
run install -m 644 "$INFRA_DIR/systemd/daypencil-pull.timer"   /etc/systemd/system/daypencil-pull.timer
run systemctl daemon-reload
run systemctl enable --now daypencil-pull.timer
if [ "$DRY_RUN" = 1 ]; then
  run systemctl start daypencil-pull.service
elif ! systemctl start daypencil-pull.service; then
  warn "first pull failed (branches '$CONTENT_BRANCH'/'$APP_BRANCH' not published yet, or no network). The timer retries every 5 minutes: journalctl -u daypencil-pull -n 30"
fi

# --- 5. nginx -----------------------------------------------------------------

log "nginx: port-80 site (always enabled)"
run install -m 644 "$INFRA_DIR/nginx/daypencil-http.conf" "$NGINX_AVAIL/daypencil-http.conf"
run ln -sfn "$NGINX_AVAIL/daypencil-http.conf" "$NGINX_ENABLED/daypencil-http.conf"

log "nginx: HTTPS site"
run install -m 644 "$INFRA_DIR/nginx/daypencil.conf" "$NGINX_AVAIL/daypencil.conf"
HTTPS_ENABLED=0
if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
  run ln -sfn "$NGINX_AVAIL/daypencil.conf" "$NGINX_ENABLED/daypencil.conf"
  HTTPS_ENABLED=1
else
  echo "certificate not found in $CERT_DIR: HTTPS site installed but NOT enabled (see next steps)"
  run rm -f "$NGINX_ENABLED/daypencil.conf"
fi

log "nginx: test and reload"
run nginx -t
run systemctl reload nginx

# --- 6. next steps ------------------------------------------------------------

log "next steps"
cat <<EOF
1. DNS (registrar): A record  daypencil.com      -> $DROPLET_IP
                    A record  www.daypencil.com  -> $DROPLET_IP
   Wait until: dig +short daypencil.com  prints $DROPLET_IP
EOF
if [ "$HTTPS_ENABLED" = 0 ]; then
  cat <<EOF
2. Certificate (after DNS resolves):
     certbot certonly --nginx -d daypencil.com -d www.daypencil.com \\
         --deploy-hook 'systemctl reload nginx'
3. Re-run this script to enable the HTTPS site:
     bash ${BASH_SOURCE[0]}
EOF
else
  cat <<EOF
2. Certificate present; HTTPS site enabled. Renewal: certbot renew --dry-run
EOF
fi
cat <<EOF
4. Check:  curl -sI https://daypencil.com/content/index.json | head -5
           journalctl -u daypencil-pull -n 20
           systemctl list-timers daypencil-pull.timer
Timezone untouched: $(timedatectl show -p Timezone --value 2>/dev/null || echo unknown) (schedules are UTC; edition boundary 04:00 UTC)
EOF
