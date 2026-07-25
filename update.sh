#!/usr/bin/env bash
# One-action update: trigger a fresh Railway build on the LATEST Hermes release.
# The Dockerfile resolves `latest` at build time, so no version editing needed.
set -euo pipefail
cd "$(dirname "$0")"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# Keep local in sync with the remote so the empty commit lands cleanly.
git pull --ff-only origin "$BRANCH" >/dev/null 2>&1 || true

STAMP="$(date -u +%Y-%m-%dT%H:%MZ)"
git commit --allow-empty -m "rebuild: pull latest Hermes release ($STAMP)"
git push origin "$BRANCH"

cat <<'EOF'

Pushed. Railway is now building a fresh image on the latest Hermes release.
Build takes ~8 min; the old version keeps serving until health checks pass.

Verify when done:
  railway logs --build | grep "hermes-agent=="
EOF
