#!/usr/bin/env bash
# Build and push the prebuilt LeRobot image used by the RunPod template.
#
# Bakes the ~4.7 GB torch + CUDA 13 stack into the image so a fresh pod pulls
# it from the registry instead of downloading wheels from PyPI at boot.
#
# Usage:
#   bash scripts/build_image.sh <dockerhub-user>            # build + push :0.6.0
#   bash scripts/build_image.sh <dockerhub-user> --no-push  # build only
#
# Requires docker and `docker login`. Docker Hub public repos are free and
# unlimited; a public image also needs no registry credentials on RunPod.

set -euo pipefail

USER_NS="${1:-}"
PUSH=1
[ "${2:-}" = "--no-push" ] && PUSH=0

if [ -z "$USER_NS" ]; then
  echo "usage: bash scripts/build_image.sh <dockerhub-user> [--no-push]" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Tagged with the LeRobot version it pins -- bump when the pin changes at a
# phase gate (roadmap section 8 rule 2).
TAG="$USER_NS/lerobot-so101:0.6.0"
CTX="$REPO_ROOT/docker"

command -v docker >/dev/null || { echo "FAIL: docker is not installed." >&2; exit 1; }

# The Dockerfile installs from the lock file; copy it into the build context so
# the image and the workstation stay in sync from a single source.
cp "$REPO_ROOT/env/lerobot-env.lock.txt" "$CTX/lerobot-env.lock.txt"
trap 'rm -f "$CTX/lerobot-env.lock.txt"' EXIT

echo "==> building $TAG (this takes ~10-15 min the first time)"
# RunPod hosts are x86_64; --platform matters if you ever build on ARM.
docker build --platform=linux/amd64 -t "$TAG" "$CTX"

echo "==> image size"
docker images --format '    {{.Repository}}:{{.Tag}}  {{.Size}}' "$TAG"

if [ "$PUSH" -eq 1 ]; then
  echo "==> pushing $TAG"
  docker push "$TAG"
  cat <<EOF

==> done

Create the RunPod template once:
  Templates -> New Template
    Container Image:   $TAG
    Volume Mount Path: /workspace
    Env:               WANDB_API_KEY = {{ RUNPOD_SECRET_wandb_api_key }}
                       HF_TOKEN      = {{ RUNPOD_SECRET_hf_token }}

Then deploy with Additional filters -> CUDA Versions -> 13.x, as always.
EOF
else
  echo "==> built only (--no-push)"
fi
