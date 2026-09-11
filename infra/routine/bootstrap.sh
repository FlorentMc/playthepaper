#!/usr/bin/env bash
# Play the Paper routine bootstrap: run once at the start of every routine run.
#
#   bash infra/routine/bootstrap.sh
#
# Makes `dart` available in the sandbox (the package depends on Flutter, so
# the Flutter SDK is installed, which bundles Dart), fetches packages, sets
# the commit identity the sandbox can sign for, and smoke-runs the validator. Idempotent: a sandbox
# that already has Flutter on PATH skips the download. Needs outbound HTTPS to
# storage.googleapis.com (Flutter archive) and pub.dev (packages).
#
# After it succeeds, every later shell needs:  export PATH="$HOME/flutter/bin:$PATH"

set -euo pipefail

FLUTTER_VERSION=3.41.1                     # keep equal to .github/workflows (3.41.x)
ARCHIVE="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
# The cloud sandbox signs pushes only for this identity (its stop hook flags
# anything else as "Unverified"), so the nightly commits are authored by
# Claude and pushed through the owner's GitHub App installation.
GIT_NAME="Claude"
GIT_EMAIL="noreply@anthropic.com"

root=$(git rev-parse --show-toplevel)
cd "$root"
export PATH="$HOME/flutter/bin:$PATH"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true

if ! command -v dart >/dev/null 2>&1; then
  if [ ! -x "$HOME/flutter/bin/flutter" ]; then
    for tool in curl tar xz; do
      command -v "$tool" >/dev/null 2>&1 || { echo "bootstrap: $tool is missing"; exit 1; }
    done
    echo "bootstrap: downloading Flutter ${FLUTTER_VERSION} ..."
    start=$(date +%s)
    curl -fsSL --retry 3 "$ARCHIVE" | tar -xJ -C "$HOME"
    echo "bootstrap: Flutter unpacked in $(( $(date +%s) - start ))s"
  fi
  export PATH="$HOME/flutter/bin:$PATH"
fi

git config --global --add safe.directory "$HOME/flutter" 2>/dev/null || true
git config --global --add safe.directory "$root" 2>/dev/null || true
flutter config --no-analytics --no-cli-animations >/dev/null 2>&1 || true

git config user.name "$GIT_NAME"
git config user.email "$GIT_EMAIL"

flutter pub get >/dev/null
echo "bootstrap: $(dart --version 2>&1)"
dart run tool/validate.dart content
echo "bootstrap: ok. Use  export PATH=\"\$HOME/flutter/bin:\$PATH\"  in every later shell."
