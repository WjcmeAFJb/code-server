#!/usr/bin/env bash
# Build (if needed) and run the dance-embedded code-server container locally.
#
# Usage:
#   ./dance/serve.sh                # build + run, bound to 127.0.0.1:8080
#   ./dance/serve.sh --port 8088    # custom port
#   ./dance/serve.sh --rebuild      # force a fresh build even if the image exists
#   ./dance/serve.sh --runtime docker   # use docker instead of podman

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PORT=8080
BIND=127.0.0.1
IMAGE=vscodium-dance-server:dev
REBUILD=0
# Auto-detect: prefer podman (rootless by default on most Linux distros).
if command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
else
  echo "neither podman nor docker available" >&2
  exit 1
fi

while (( $# )); do
  case "$1" in
    --port)    PORT="$2"; shift 2 ;;
    --bind)    BIND="$2"; shift 2 ;;
    --runtime) RUNTIME="$2"; shift 2 ;;
    --image)   IMAGE="$2"; shift 2 ;;
    --rebuild) REBUILD=1; shift ;;
    *) echo "unknown flag $1" >&2; exit 2 ;;
  esac
done

have_image() { "$RUNTIME" image exists "$IMAGE" 2>/dev/null || "$RUNTIME" image inspect "$IMAGE" >/dev/null 2>&1; }

if (( REBUILD )) || ! have_image; then
  echo "[serve] building $IMAGE with $RUNTIME …"
  "$RUNTIME" build -t "$IMAGE" -f dance/Dockerfile .
fi

mkdir -p "$HOME/.config/code-server-dance" "$HOME/.local/share/code-server-dance"

echo "[serve] starting code-server on http://$BIND:$PORT"
exec "$RUNTIME" run --rm \
  --name vscodium-dance-server \
  -p "$BIND:$PORT:8080" \
  -v "$HOME/.config/code-server-dance:/home/coder/.config" \
  -v "$HOME/.local/share/code-server-dance:/home/coder/.local/share" \
  -v "$PWD:/home/coder/project" \
  "$IMAGE"
