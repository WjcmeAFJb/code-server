#!/usr/bin/env bash
# Apply the Dance integration to lib/vscode.
#
# Mirrors what our VSCodium fork does via its src/stable/ overlay + patches/user/
# patch, but adapted for code-server's quilt-style patch flow:
#
#   1. Drop the pre-built built-in extension into vscode/extensions/dance/
#   2. Drop the renderer-side workbench contribution into
#      vscode/src/vs/workbench/contrib/dance/browser/
#   3. Patch workbench.common.main.ts so the contribution actually loads
#
# Idempotent: re-running over an already-patched tree is a no-op.

set -euo pipefail

DANCE_DIR="$(cd "$(dirname "$0")" && pwd)"
VSCODE_DIR="$(cd "$DANCE_DIR/.." && pwd)/lib/vscode"

if [[ ! -d "$VSCODE_DIR" ]]; then
  echo "[dance] $VSCODE_DIR not found — run 'git submodule update --init lib/vscode' first" >&2
  exit 1
fi

echo "[dance] copying built-in extension → $VSCODE_DIR/extensions/dance/"
mkdir -p "$VSCODE_DIR/extensions/dance"
# rsync would be cleaner but we don't assume it is installed in the build image.
cp -rT "$DANCE_DIR/extension" "$VSCODE_DIR/extensions/dance"

echo "[dance] copying workbench contribution → $VSCODE_DIR/src/vs/workbench/contrib/dance/"
mkdir -p "$VSCODE_DIR/src/vs/workbench/contrib/dance"
cp -rT "$DANCE_DIR/contrib" "$VSCODE_DIR/src/vs/workbench/contrib/dance"

WORKBENCH_MAIN="$VSCODE_DIR/src/vs/workbench/workbench.common.main.ts"
if grep -q "contrib/dance/browser/dance.contribution" "$WORKBENCH_MAIN"; then
  echo "[dance] workbench.common.main.ts already wires up the contribution — skipping patch"
else
  echo "[dance] applying register-contrib.patch"
  (cd "$VSCODE_DIR" && git apply --ignore-whitespace "$DANCE_DIR/register-contrib.patch") \
    || (cd "$VSCODE_DIR" && git apply --ignore-whitespace --recount --reject "$DANCE_DIR/register-contrib.patch")
fi

echo "[dance] integration applied."
