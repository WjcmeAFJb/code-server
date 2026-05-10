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
  echo "[dance] workbench.common.main.ts already wires up the contribution — skipping"
else
  # Insert our import directly after the performance contribution import.  The
  # line-number-keyed patch breaks across vscode versions; an in-place edit
  # against a unique anchor is robust to upstream churn.
  ANCHOR="import './contrib/performance/browser/performance.contribution.js';"
  if ! grep -qF "$ANCHOR" "$WORKBENCH_MAIN"; then
    echo "[dance] anchor line not found in workbench.common.main.ts — vscode layout has changed" >&2
    exit 1
  fi
  echo "[dance] inserting workbench import after the performance contribution"
  awk -v anchor="$ANCHOR" '
    {print}
    $0 == anchor && !done {
      print ""
      print "// Dance (modal editing) core contribution"
      print "import '\''./contrib/dance/browser/dance.contribution.js'\'';"
      done = 1
    }
  ' "$WORKBENCH_MAIN" > "$WORKBENCH_MAIN.tmp" && mv "$WORKBENCH_MAIN.tmp" "$WORKBENCH_MAIN"
fi

echo "[dance] integration applied."
